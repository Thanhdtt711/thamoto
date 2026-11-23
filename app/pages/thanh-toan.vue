<script setup lang="ts">
import { Check, MapPin, CreditCard } from 'lucide-vue-next';

useSeoMeta({
  title: 'Thanh Toán Đơn Hàng | Trung Thành Auto',
  description: 'Thanh toán đơn hàng thảm lót sàn ô tô Trung Thành Auto. Hỗ trợ COD nhận hàng kiểm tra lắp đặt mới trả tiền hoặc chuyển khoản VietQR.'
});

const router = useRouter();
const { items, subtotal, clearCart } = useCart();
const { getRefCode } = useAffiliate();
const { supabase, isConfigured } = useSupabase();

const name = ref('');
const phone = ref('');
const address = ref('');
const notes = ref('');
const refCode = ref('');
const paymentMethod = ref<'COD' | 'BANK'>('COD');

const formError = ref('');
const isSubmitting = ref(false);
const showQrModal = ref(false);
const appliedCoupon = ref<{ code: string; type: 'fixed' | 'percent'; value: number } | null>(null);

const completedOrder = ref<{
  orderCode: string;
  name: string;
  phone: string;
  methodText: string;
  total: number;
  refCode: string;
} | null>(null);

onMounted(() => {
  refCode.value = getRefCode();
  try {
    const saved = sessionStorage.getItem('thamoto_applied_coupon');
    if (saved) appliedCoupon.value = JSON.parse(saved);
  } catch {
    // Ignore
  }
  if (items.value.length === 0) {
    router.replace('/gio-hang');
  }
});

const discountAmount = computed(() => {
  if (!appliedCoupon.value) return 0;
  return appliedCoupon.value.type === 'percent'
    ? Math.round(subtotal.value * appliedCoupon.value.value)
    : appliedCoupon.value.value;
});

const grandTotal = computed(() => Math.max(0, subtotal.value - discountAmount.value));

const buildItemsSummary = () =>
  items.value.map((item) => {
    const vStr = item.vehicle ? `${item.vehicle.brand} ${item.vehicle.model}` : '';
    const parts = [vStr, item.formLabel, item.material, item.color].filter(Boolean).join(' | ');
    return `${item.quantity}x ${item.name} (${parts})`;
  }).join('\n');

const submitOrder = async (methodKey: 'COD' | 'VietQR', methodText: string) => {
  if (isSubmitting.value) return;
  const cleanPhone = phone.value.replace(/\s+/g, '');
  const cleanRef = refCode.value.trim().toUpperCase() || getRefCode();
  const orderCode = `TT-${Math.floor(10000 + Math.random() * 90000)}`;

  isSubmitting.value = true;
  formError.value = '';

  try {
    if (isConfigured && supabase) {
      const { error } = await supabase.from('orders').insert({
        order_code: orderCode,
        customer_name: name.value.trim(),
        phone: cleanPhone,
        address: address.value.trim(),
        notes: notes.value.trim() || null,
        payment_method: methodKey,
        coupon_code: appliedCoupon.value?.code || null,
        total_amount: grandTotal.value,
        items: items.value,
        items_summary: buildItemsSummary(),
        affiliate_code: cleanRef || null
      });
      if (error) throw error;
    }

    completedOrder.value = {
      orderCode,
      name: name.value.trim(),
      phone: cleanPhone,
      methodText,
      total: grandTotal.value,
      refCode: cleanRef
    };

    clearCart();
    if (import.meta.client) {
      sessionStorage.removeItem('thamoto_applied_coupon');
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
  } catch {
    formError.value = `Không thể gửi đơn lúc này (mã tham chiếu #${orderCode}). Vui lòng thử lại hoặc nhắn Zalo 0963 294 492 để chốt đơn ngay.`;
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

  if (paymentMethod.value === 'BANK') {
    showQrModal.value = true;
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

    <!-- Success Screen -->
    <div v-if="completedOrder" class="max-w-xl mx-auto card-surface p-6 sm:p-8 text-center space-y-5">
      <div class="w-16 h-16 rounded-full bg-green-50 border border-green-200 text-[#15803D] flex items-center justify-center mx-auto">
        <Check class="w-8 h-8" />
      </div>
      <h1 class="text-xl sm:text-2xl font-bold text-[#0D2C54] m-0">Đặt Hàng Thành Công!</h1>
      <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
        Mã đơn hàng của bạn là <strong class="text-[#C81E2B] tabular-nums">#{{ completedOrder.orderCode }}</strong>. Nhân viên kỹ thuật sẽ liên hệ xác nhận phom xe trong 15 phút.
      </p>
      <div class="bg-[#F4F6F9] border border-slate-200 rounded-xl p-4 text-left text-xs sm:text-sm space-y-2">
        <div class="flex justify-between"><span class="text-slate-500">Khách hàng:</span><span class="font-semibold text-slate-900">{{ completedOrder.name }}</span></div>
        <div class="flex justify-between"><span class="text-slate-500">Số điện thoại:</span><span class="font-semibold text-slate-900 tabular-nums">{{ completedOrder.phone }}</span></div>
        <div class="flex justify-between"><span class="text-slate-500">Thanh toán:</span><span class="font-semibold text-slate-900">{{ completedOrder.methodText }}</span></div>
        <div v-if="completedOrder.refCode" class="flex justify-between"><span class="text-slate-500">Mã giới thiệu (CTV):</span><span class="font-semibold text-[#0D2C54] uppercase">{{ completedOrder.refCode }}</span></div>
        <div class="flex justify-between pt-2 border-t border-slate-200"><span class="font-semibold text-slate-700">Tổng tiền:</span><span class="font-bold text-[#15803D] tabular-nums">{{ formatCurrency(completedOrder.total) }}</span></div>
      </div>
      <div class="flex flex-col sm:flex-row gap-3 justify-center">
        <a href="https://zalo.me/0963294492" target="_blank" rel="noopener" class="btn-outline text-xs px-6 no-underline">NHẮN ZALO XÁC NHẬN NHANH (0963 294 492)</a>
        <NuxtLink to="/" class="btn-cta text-xs px-8">QUAY LẠI TRANG CHỦ</NuxtLink>
      </div>
    </div>

    <!-- Active Checkout -->
    <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
      <form id="checkout-form" class="lg:col-span-2 space-y-5" novalidate @submit.prevent="handleFormSubmit">
        <div class="card-surface p-5 space-y-4">
          <h1 class="text-base font-bold uppercase text-[#0D2C54] pb-3 border-b border-slate-200 m-0 flex items-center gap-2">
            <MapPin class="w-4 h-4" /> Thông tin giao hàng &amp; lắp đặt
          </h1>

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
            <input id="billing-ref" v-model="refCode" type="text" placeholder="VD: CTV01 (tự động điền khi vào từ link giới thiệu)" class="field-input uppercase">
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
              <span class="text-xs text-slate-500 block mt-0.5">VietinBank · STK: 1098 7654 3210 · CT CỔ PHẦN TRUNG THÀNH.</span>
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
            <span class="font-semibold text-[#15803D]">Miễn phí</span>
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
          {{ isSubmitting ? 'ĐANG GỬI ĐƠN...' : 'ĐẶT HÀNG NGAY' }}
        </button>
      </aside>
    </div>

    <!-- VietQR Modal -->
    <Teleport to="body">
      <div v-if="showQrModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-slate-900/60 backdrop-blur-[2px]" @click="showQrModal = false" />
        <div class="bg-white border border-slate-200 rounded-2xl w-full max-w-md p-6 relative z-10 shadow-2xl space-y-4">
          <div class="text-center">
            <h3 class="text-base font-bold text-[#0D2C54] m-0">Thanh Toán Qua VietQR</h3>
            <p class="text-xs text-slate-500 mt-1 m-0">Quét mã QR bằng ứng dụng ngân hàng để thanh toán</p>
          </div>
          <div class="bg-[#F4F6F9] border border-slate-200 rounded-xl p-3.5 text-xs space-y-2">
            <div class="flex justify-between"><span class="text-slate-500">Ngân hàng:</span><span class="font-semibold text-slate-900">VietinBank</span></div>
            <div class="flex justify-between"><span class="text-slate-500">Số tài khoản:</span><span class="font-semibold text-slate-900 tabular-nums">1098 7654 3210</span></div>
            <div class="flex justify-between"><span class="text-slate-500">Chủ tài khoản:</span><span class="font-semibold text-slate-900">CT CỔ PHẦN TRUNG THÀNH</span></div>
            <div class="flex justify-between"><span class="text-slate-500">Nội dung:</span><span class="font-semibold text-[#0D2C54] select-all">TT {{ phone.replace(/\s+/g, '') }}</span></div>
            <div class="flex justify-between"><span class="text-slate-500">Số tiền:</span><span class="font-bold text-[#15803D] tabular-nums">{{ formatCurrency(grandTotal) }}</span></div>
          </div>
          <div class="flex justify-center">
            <div class="w-44 h-44 bg-white p-2 rounded-xl border border-slate-200">
              <img src="/assets/images/vietqr-mockup.webp" alt="Mã chuyển khoản VietQR" width="176" height="176" class="w-full h-full object-contain">
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <button type="button" class="btn-outline text-xs" @click="showQrModal = false">Hủy bỏ</button>
            <button type="button" :disabled="isSubmitting" class="btn-cta text-xs" @click="showQrModal = false; submitOrder('VietQR', 'Chuyển khoản (VietQR)')">
              {{ isSubmitting ? 'ĐANG GỬI...' : 'ĐÃ CHUYỂN KHOẢN' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </main>
</template>
