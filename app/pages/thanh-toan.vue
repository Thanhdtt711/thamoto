<script setup lang="ts">
import { Check, MapPin, CreditCard, Search, MessageCircle, Home } from 'lucide-vue-next';

useSeoMeta({
  title: 'Thanh Toán Đơn Hàng | Trung Thành Auto',
  description: 'Thanh toán đơn hàng thảm lót sàn ô tô Trung Thành Auto. Hỗ trợ COD nhận hàng kiểm tra lắp đặt mới trả tiền hoặc chuyển khoản VietQR.',
  robots: 'noindex, nofollow'
});

const router = useRouter();
const { items, subtotal, clearCart } = useCart();
const { getRefCode, refSource, refClickId } = useAffiliate();
const { supabase, isConfigured } = useSupabase();

const name = ref('');
const phone = ref('');
const address = ref('');
const notes = ref('');
const refCode = ref('');
const initialTrackedRef = ref('');
const refValidationMsg = ref('');
const refValid = ref<boolean | null>(null);
const paymentMethod = ref<'COD' | 'BANK'>('COD');

const formError = ref('');
const priceChangedNotice = ref('');
const isSubmitting = ref(false);
const appliedCoupon = ref<{ code: string; type: 'fixed' | 'percent'; value: number; discountAmount?: number } | null>(null);

// Cấu hình ngân hàng & phí ship từ app_settings (RPC get_storefront_config) — không hardcode
const storeConfig = ref({
  bank_name: 'VietinBank',
  bank_bin: '970415',
  bank_account: '109876543210',
  bank_holder: 'CT CO PHAN TRUNG THANH',
  shipping_base_fee: 0,
  free_ship_threshold: 1500000
});

const completedOrder = ref<{
  orderCode: string;
  name: string;
  phone: string;
  methodKey: 'COD' | 'VietQR';
  methodText: string;
  total: number;
  refCode: string;
  warning?: string;
} | null>(null);

const vietQrUrl = computed(() => {
  if (!completedOrder.value || completedOrder.value.methodKey !== 'VietQR') return '';
  const bin = encodeURIComponent(storeConfig.value.bank_bin);
  const acc = encodeURIComponent(storeConfig.value.bank_account);
  const amt = Math.max(0, Math.round(completedOrder.value.total));
  const info = encodeURIComponent(completedOrder.value.orderCode);
  const holder = encodeURIComponent(storeConfig.value.bank_holder);
  return `https://img.vietqr.io/image/${bin}-${acc}-compact2.png?amount=${amt}&addInfo=${info}&accountName=${holder}`;
});

const loadStorefrontAndSyncCart = async () => {
  if (!isConfigured || !supabase) return;
  try {
    const [cfgRes, catRes] = await Promise.all([
      supabase.rpc('get_storefront_config'),
      supabase.rpc('get_catalog_prices')
    ]);
    if (!cfgRes.error && cfgRes.data) {
      const c = cfgRes.data as Record<string, any>;
      storeConfig.value = {
        bank_name: String(c.bank_name || storeConfig.value.bank_name),
        bank_bin: String(c.bank_bin || storeConfig.value.bank_bin),
        bank_account: String(c.bank_account || storeConfig.value.bank_account),
        bank_holder: String(c.bank_holder || storeConfig.value.bank_holder),
        shipping_base_fee: Number(c.shipping_base_fee ?? 0),
        free_ship_threshold: Number(c.free_ship_threshold ?? 1500000)
      };
    }
    if (!catRes.error && Array.isArray(catRes.data)) {
      const matPrices = new Map<string, number>();
      const addonPrices = new Map<string, number>();
      for (const p of catRes.data as any[]) {
        if (p.product_type === 'mat') matPrices.set(String(p.name), Number(p.base_price) || 0);
        if (p.product_type === 'addon') addonPrices.set(String(p.name).toLowerCase(), Number(p.base_price) || 0);
      }
      let changed = false;
      for (const item of items.value) {
        const dbBase = matPrices.get(item.material);
        if (dbBase !== undefined) {
          const addonSum = (item.addons || []).reduce((sum, a) => {
            const matched = Array.from(addonPrices.entries()).find(([k]) => a.toLowerCase().includes(k));
            return sum + (matched ? matched[1] : 0);
          }, 0);
          const freshPrice = dbBase + addonSum;
          if (freshPrice > 0 && freshPrice !== item.price) {
            item.price = freshPrice;
            changed = true;
          }
        }
      }
      if (changed) {
        priceChangedNotice.value = 'Giá sản phẩm vừa được cập nhật theo bảng giá mới nhất từ hệ thống.';
      }
    }
  } catch {
    // Fallback an toàn
  }
};

onMounted(() => {
  const tracked = getRefCode();
  refCode.value = tracked;
  initialTrackedRef.value = tracked;
  try {
    const saved = sessionStorage.getItem('thamoto_applied_coupon');
    if (saved) appliedCoupon.value = JSON.parse(saved);
  } catch {
    // Ignore
  }
  if (items.value.length === 0) {
    router.replace('/gio-hang');
    return;
  }
  loadStorefrontAndSyncCart();
});

const discountAmount = computed(() => {
  if (!appliedCoupon.value) return 0;
  if (typeof appliedCoupon.value.discountAmount === 'number') {
    return Math.min(appliedCoupon.value.discountAmount, subtotal.value);
  }
  return appliedCoupon.value.type === 'percent'
    ? Math.floor((subtotal.value * appliedCoupon.value.value) / 100)
    : appliedCoupon.value.value;
});

const shippingFee = computed(() => {
  const base = Number(storeConfig.value.shipping_base_fee || 0);
  const threshold = Number(storeConfig.value.free_ship_threshold || 0);
  if (base <= 0) return 0;
  if (threshold > 0 && subtotal.value >= threshold) return 0;
  return base;
});

const grandTotal = computed(() => Math.max(0, subtotal.value - discountAmount.value + shippingFee.value));

const checkAffiliateCode = async () => {
  const code = refCode.value.trim().toUpperCase();
  if (!code) {
    refValid.value = null;
    refValidationMsg.value = '';
    return;
  }
  if (!isConfigured || !supabase) return;
  try {
    const { data } = await supabase.rpc('validate_affiliate_code', { p_code: code });
    refValid.value = Boolean(data?.valid);
    refValidationMsg.value = data?.message || '';
  } catch {
    refValid.value = null;
    refValidationMsg.value = '';
  }
};

const submitOrder = async (methodKey: 'COD' | 'VietQR', methodText: string) => {
  if (isSubmitting.value) return;
  if (!isConfigured || !supabase) {
    formError.value = 'Hệ thống đặt hàng đang bảo trì kết nối. Vui lòng nhắn Zalo 0963 294 492 để được lên đơn ngay.';
    return;
  }

  const cleanPhone = phone.value.replace(/\s+/g, '');
  const cleanRef = refCode.value.trim().toUpperCase();
  const effectiveSource = cleanRef
    ? (cleanRef !== initialTrackedRef.value ? 'manual' : refSource.value)
    : null;

  isSubmitting.value = true;
  formError.value = '';

  try {
    const payloadItems = items.value.map((i) => ({
      name: i.name,
      material: i.material,
      color: i.color,
      formLabel: i.formLabel || '',
      addons: i.addons || [],
      vehicle: i.vehicle || null,
      quantity: i.quantity
    }));

    const { data, error } = await supabase.rpc('create_order', {
      p_customer_name: name.value.trim(),
      p_phone: cleanPhone,
      p_address: address.value.trim(),
      p_notes: notes.value.trim() || null,
      p_payment_method: methodKey,
      p_coupon_code: appliedCoupon.value?.code || null,
      p_affiliate_code: cleanRef || null,
      p_ref_source: effectiveSource,
      p_items: payloadItems,
      p_ref_click_id: effectiveSource === 'link' ? refClickId.value : null
    });
    if (error) throw error;

    completedOrder.value = {
      orderCode: String(data?.order_code || ''),
      name: name.value.trim(),
      phone: cleanPhone,
      methodKey,
      methodText,
      total: Number(data?.total_amount ?? grandTotal.value),
      refCode: data?.affiliate_code || '',
      warning: data?.warning || ''
    };

    clearCart();
    if (import.meta.client) {
      sessionStorage.removeItem('thamoto_applied_coupon');
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
  } catch (err: any) {
    formError.value = err?.message || 'Không thể gửi đơn lúc này. Vui lòng thử lại hoặc nhắn Zalo 0963 294 492 để chốt đơn ngay.';
  } finally {
    isSubmitting.value = false;
  }
};

const handleFormSubmit = () => {
  const cleanPhone = phone.value.replace(/\s+/g, '');
  if (name.value.trim().length < 2) {
    formError.value = 'Vui lòng nhập họ và tên nhận hàng (ít nhất 2 ký tự).';
    return;
  }
  if (!/^0[35789]\d{8}$/.test(cleanPhone)) {
    formError.value = 'Số điện thoại không hợp lệ. Vui lòng nhập đúng 10 số (VD: 0963294492).';
    return;
  }
  if (address.value.trim().length < 5) {
    formError.value = 'Vui lòng nhập đầy đủ địa chỉ nhận hàng / lắp đặt.';
    return;
  }
  formError.value = '';

  // P1-1a: Luôn tạo đơn trên server TRƯỚC để có mã đơn chính xác làm nội dung chuyển khoản VietQR
  if (paymentMethod.value === 'BANK') {
    submitOrder('VietQR', 'Chuyển khoản ngân hàng (VietQR)');
  } else {
    submitOrder('COD', 'Thanh toán khi nhận hàng (COD)');
  }
};
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-5">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <NuxtLink to="/gio-hang">Giỏ hàng</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54]">Thanh toán</span>
    </nav>

    <!-- Success Screen (+ Dynamic VietQR with Order Code if BANK) -->
    <div v-if="completedOrder" class="max-w-xl mx-auto card-surface p-6 sm:p-8 text-center space-y-5">
      <div class="w-16 h-16 rounded-full bg-green-50 border border-green-200 text-[#15803D] flex items-center justify-center mx-auto">
        <Check class="w-8 h-8" />
      </div>
      <h1 class="text-xl sm:text-2xl font-bold text-[#0D2C54] m-0">Đặt Hàng Thành Công!</h1>
      <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
        Mã đơn hàng của bạn là <strong class="text-[#C81E2B] tabular-nums">#{{ completedOrder.orderCode }}</strong>. Nhân viên kỹ thuật sẽ liên hệ xác nhận phom xe trong 15 phút.
      </p>

      <!-- Dynamic VietQR Payment Box (chỉ hiện sau khi đã tạo đơn thật trên DB) -->
      <div v-if="completedOrder.methodKey === 'VietQR'" class="bg-[#EFF4FA] border border-[#0D2C54]/20 rounded-xl p-4 space-y-3 text-center">
        <p class="text-xs font-extrabold uppercase text-[#0D2C54] m-0">Quét mã VietQR để chuyển khoản đúng mã đơn</p>
        <div class="bg-white rounded-xl p-3 inline-block border border-slate-200">
          <img
            :src="vietQrUrl"
            :alt="`Mã VietQR thanh toán đơn ${completedOrder.orderCode}`"
            width="220"
            height="220"
            class="w-52 h-52 object-contain mx-auto"
          >
        </div>
        <div class="text-xs text-left bg-white rounded-lg p-3 space-y-1.5 border border-slate-200">
          <div class="flex justify-between"><span class="text-slate-500">Ngân hàng:</span><strong>{{ storeConfig.bank_name }}</strong></div>
          <div class="flex justify-between"><span class="text-slate-500">Số tài khoản:</span><strong class="font-mono">{{ storeConfig.bank_account }}</strong></div>
          <div class="flex justify-between"><span class="text-slate-500">Chủ tài khoản:</span><strong>{{ storeConfig.bank_holder }}</strong></div>
          <div class="flex justify-between"><span class="text-slate-500">Số tiền:</span><strong class="text-[#15803D] tabular-nums">{{ formatCurrency(completedOrder.total) }}</strong></div>
          <div class="flex justify-between"><span class="text-slate-500">Nội dung CK (bắt buộc):</span><strong class="text-[#C81E2B] font-mono">{{ completedOrder.orderCode }}</strong></div>
        </div>
      </div>

      <div class="bg-[#F4F6F9] border border-slate-200 rounded-xl p-4 text-left text-xs sm:text-sm space-y-2">
        <div class="flex justify-between"><span class="text-slate-500">Khách hàng:</span><span class="font-semibold text-slate-900">{{ completedOrder.name }}</span></div>
        <div class="flex justify-between"><span class="text-slate-500">Số điện thoại:</span><span class="font-semibold text-slate-900 tabular-nums">{{ completedOrder.phone }}</span></div>
        <div class="flex justify-between"><span class="text-slate-500">Thanh toán:</span><span class="font-semibold text-slate-900">{{ completedOrder.methodText }}</span></div>
        <div v-if="completedOrder.refCode" class="flex justify-between"><span class="text-slate-500">Mã giới thiệu (CTV):</span><span class="font-semibold text-[#0D2C54] uppercase">{{ completedOrder.refCode }}</span></div>
        <div class="flex justify-between pt-2 border-t border-slate-200"><span class="font-semibold text-slate-700">Tổng tiền:</span><span class="font-bold text-[#15803D] tabular-nums">{{ formatCurrency(completedOrder.total) }}</span></div>
      </div>
      <p v-if="completedOrder.warning" role="status" class="text-xs font-medium text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3.5 py-2.5 m-0 text-left">
        Lưu ý: {{ completedOrder.warning }}
      </p>
      <div class="space-y-2.5 pt-1">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
          <NuxtLink
            :to="`/tra-cuu-don?code=${completedOrder.orderCode}`"
            class="btn-outline w-full text-xs px-4 whitespace-nowrap no-underline"
          >
            <Search class="w-4 h-4 shrink-0" />
            <span>TRA CỨU ĐƠN HÀNG</span>
          </NuxtLink>
          <a
            href="https://zalo.me/0963294492"
            target="_blank"
            rel="noopener"
            class="btn-outline w-full text-xs px-4 whitespace-nowrap no-underline"
          >
            <MessageCircle class="w-4 h-4 shrink-0" />
            <span>NHẮN ZALO XÁC NHẬN</span>
          </a>
        </div>
        <NuxtLink to="/" class="btn-cta w-full text-xs px-6 whitespace-nowrap no-underline">
          <Home class="w-4 h-4 shrink-0" />
          <span>QUAY LẠI TRANG CHỦ</span>
        </NuxtLink>
      </div>
    </div>

    <!-- Active Checkout -->
    <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
      <form id="checkout-form" class="lg:col-span-2 space-y-5" novalidate @submit.prevent="handleFormSubmit">
        <div class="card-surface p-5 space-y-4">
          <h1 class="text-base font-bold uppercase text-[#0D2C54] pb-3 border-b border-slate-200 m-0 flex items-center gap-2">
            <MapPin class="w-4 h-4" /> Thông tin giao hàng &amp; lắp đặt
          </h1>

          <p v-if="priceChangedNotice" role="status" class="text-xs font-semibold text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3.5 py-2.5 m-0">
            {{ priceChangedNotice }}
          </p>

          <p v-if="formError" role="alert" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3.5 py-2.5 m-0">
            {{ formError }}
          </p>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="space-y-1.5">
              <label for="billing-name" class="text-xs font-semibold text-slate-700 block">Họ và tên *</label>
              <input id="billing-name" v-model="name" type="text" required placeholder="Nhập họ tên nhận hàng..." class="field-input">
            </div>
            <div class="space-y-1.5">
              <label for="billing-phone" class="text-xs font-semibold text-slate-700 block">Số điện thoại *</label>
              <input id="billing-phone" v-model="phone" type="tel" required placeholder="VD: 0963294492" class="field-input">
            </div>
          </div>

          <div class="space-y-1.5">
            <label for="billing-address" class="text-xs font-semibold text-slate-700 block">Địa chỉ nhận hàng / lắp đặt *</label>
            <input id="billing-address" v-model="address" type="text" required placeholder="Số nhà, đường, phường/xã, quận/huyện, tỉnh thành..." class="field-input">
          </div>

          <div class="space-y-1.5">
            <label for="billing-notes" class="text-xs font-semibold text-slate-700 block">Ghi chú (giờ giao, lưu ý xe...)</label>
            <textarea id="billing-notes" v-model="notes" rows="2" placeholder="Ghi chú thêm cho kỹ thuật viên..." class="field-input min-h-[76px] resize-none" />
          </div>

          <div class="space-y-1.5">
            <label for="billing-ref" class="text-xs font-semibold text-slate-700 block">Mã CTV / Người giới thiệu (nếu có)</label>
            <input id="billing-ref" v-model="refCode" type="text" placeholder="VD: CTV01 (tự động điền khi vào từ link giới thiệu)" class="field-input uppercase" @blur="checkAffiliateCode">
            <p v-if="refValidationMsg" class="text-[11px] font-semibold m-0" :class="refValid ? 'text-[#15803D]' : 'text-[#C81E2B]'">
              {{ refValidationMsg }}
            </p>
          </div>
        </div>

        <div class="card-surface p-5 space-y-3">
          <h2 class="text-base font-bold uppercase text-[#0D2C54] pb-3 border-b border-slate-200 m-0 flex items-center gap-2">
            <CreditCard class="w-4 h-4" /> Phương thức thanh toán
          </h2>

          <label class="flex items-start gap-3 p-3.5 rounded-xl border border-slate-200 hover:border-[#0D2C54] cursor-pointer transition bg-white">
            <input v-model="paymentMethod" type="radio" value="COD" class="mt-1 w-4 h-4 accent-[#0D2C54]">
            <div>
              <span class="text-sm font-semibold text-slate-900 block">Thanh toán khi nhận hàng (COD)</span>
              <span class="text-xs text-slate-500 block mt-0.5">Kiểm tra lắp vừa vặn 100% lên xe mới thanh toán.</span>
            </div>
          </label>

          <label class="flex items-start gap-3 p-3.5 rounded-xl border border-slate-200 hover:border-[#0D2C54] cursor-pointer transition bg-white">
            <input v-model="paymentMethod" type="radio" value="BANK" class="mt-1 w-4 h-4 accent-[#0D2C54]">
            <div>
              <span class="text-sm font-semibold text-slate-900 block">Chuyển khoản ngân hàng (VietQR)</span>
              <span class="text-xs text-slate-500 block mt-0.5">
                {{ storeConfig.bank_name }} · STK: {{ storeConfig.bank_account }} · {{ storeConfig.bank_holder }}. Mã QR kèm đúng mã đơn sẽ hiện ngay sau khi xác nhận đặt hàng.
              </span>
            </div>
          </label>
        </div>
      </form>

      <aside class="card-surface p-5 space-y-4">
        <h2 class="text-sm font-bold uppercase text-[#0D2C54] pb-3 border-b border-slate-200 m-0">Đơn hàng của bạn</h2>
        <div class="max-h-64 overflow-y-auto space-y-2.5">
          <div v-for="item in items" :key="item.id" class="flex items-start justify-between gap-3 py-2 border-b border-slate-100 text-xs">
            <div class="min-w-0">
              <p class="font-semibold text-slate-900 m-0 truncate">{{ item.quantity }}x {{ item.name }}</p>
              <p class="text-[11px] text-slate-500 m-0">{{ item.material }} · {{ item.color }}</p>
              <p v-if="item.formLabel" class="text-[11px] text-slate-500 m-0">{{ item.formLabel }}</p>
            </div>
            <span class="font-semibold text-slate-900 tabular-nums shrink-0">{{ formatCurrency(item.price * item.quantity) }}</span>
          </div>
        </div>

        <div class="space-y-2 text-xs sm:text-sm pt-3 border-t border-slate-200">
          <div class="flex justify-between text-slate-600">
            <span>Tạm tính</span>
            <span class="font-semibold text-slate-900 tabular-nums">{{ formatCurrency(subtotal) }}</span>
          </div>
          <div class="flex justify-between text-slate-600">
            <span>Phí vận chuyển</span>
            <span class="font-semibold" :class="shippingFee === 0 ? 'text-[#15803D]' : 'text-slate-900 tabular-nums'">
              {{ shippingFee === 0 ? 'Miễn phí' : formatCurrency(shippingFee) }}
            </span>
          </div>
          <div v-if="discountAmount > 0" class="flex justify-between text-[#15803D] font-semibold">
            <span>Ưu đãi ({{ appliedCoupon?.code }})</span>
            <span class="tabular-nums">-{{ formatCurrency(discountAmount) }}</span>
          </div>
        </div>

        <div class="flex justify-between items-baseline pt-3 border-t border-slate-200">
          <span class="text-sm font-semibold text-slate-900">Tổng thanh toán</span>
          <span class="text-xl font-bold text-[#15803D] tabular-nums">{{ formatCurrency(grandTotal) }}</span>
        </div>

        <button type="submit" form="checkout-form" :disabled="isSubmitting" class="btn-cta w-full text-sm">
          {{ isSubmitting ? 'ĐANG GỬI ĐƠN...' : (paymentMethod === 'BANK' ? 'ĐẶT HÀNG & HIỆN MÃ VIETQR' : 'ĐẶT HÀNG NGAY') }}
        </button>
      </aside>
    </div>
  </main>
</template>
