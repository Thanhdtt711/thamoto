<script setup lang="ts">
import { Trash2, Plus, Minus, ShoppingBag } from 'lucide-vue-next';

useSeoMeta({
  title: 'Giỏ Hàng | Trung Thành Auto',
  description: 'Xem lại cấu hình thảm lót sàn ô tô trong giỏ hàng trước khi thanh toán.'
});

const { items, subtotal, updateQuantity, removeItem } = useCart();
const { supabase, isConfigured } = useSupabase();

const couponInput = ref('');
const couponMsg = ref('');
const couponError = ref(false);
const isCheckingCoupon = ref(false);
const appliedCoupon = ref<{ code: string; type: 'fixed' | 'percent'; value: number; discountAmount?: number } | null>(null);

onMounted(() => {
  try {
    const saved = sessionStorage.getItem('thamoto_applied_coupon');
    if (saved) appliedCoupon.value = JSON.parse(saved);
  } catch {
    // Ignore
  }
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

const grandTotal = computed(() => Math.max(0, subtotal.value - discountAmount.value));

const applyCoupon = async () => {
  const code = couponInput.value.trim().toUpperCase();
  if (!code) {
    couponError.value = true;
    couponMsg.value = 'Vui lòng nhập mã giảm giá.';
    return;
  }

  isCheckingCoupon.value = true;
  try {
    if (isConfigured && supabase) {
      const { data, error } = await supabase.rpc('validate_coupon', {
        p_code: code,
        p_subtotal: subtotal.value
      });
      if (error) throw error;
      if (!data?.valid) {
        couponError.value = true;
        couponMsg.value = data?.message || 'Mã giảm giá không hợp lệ.';
        appliedCoupon.value = null;
        if (import.meta.client) sessionStorage.removeItem('thamoto_applied_coupon');
        return;
      }
      couponError.value = false;
      couponMsg.value = data.message || `Áp dụng mã ${data.code} thành công!`;
      appliedCoupon.value = {
        code: data.code,
        type: data.discount_type,
        value: Number(data.discount_value),
        discountAmount: Number(data.discount_amount)
      };
      if (import.meta.client) {
        sessionStorage.setItem('thamoto_applied_coupon', JSON.stringify(appliedCoupon.value));
      }
    } else {
      couponError.value = true;
      couponMsg.value = 'Chưa kết nối máy chủ để xác thực mã giảm giá.';
    }
  } catch {
    couponError.value = true;
    couponMsg.value = 'Không thể kiểm tra mã giảm giá lúc này. Vui lòng thử lại.';
  } finally {
    isCheckingCoupon.value = false;
  }
};
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-5">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54]">Giỏ hàng</span>
    </nav>

    <h1 class="section-heading">GIỎ HÀNG CỦA BẠN</h1>

    <div v-if="items.length === 0" class="card-surface p-10 text-center space-y-4">
      <div class="w-16 h-16 rounded-full bg-slate-100 text-slate-400 flex items-center justify-center mx-auto">
        <ShoppingBag class="w-8 h-8" />
      </div>
      <p class="text-sm font-semibold text-slate-700 m-0">Giỏ hàng của bạn hiện đang trống</p>
      <NuxtLink to="/san-pham" class="btn-cta text-xs px-6">CHỌN DÒNG XE NGAY</NuxtLink>
    </div>

    <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
      <div class="lg:col-span-2 space-y-3">
        <div
          v-for="(item, idx) in items"
          :key="item.id"
          class="card-surface p-4 flex gap-4 items-start"
        >
          <img :src="item.image" :alt="item.name" width="96" height="96" class="w-20 h-20 sm:w-24 sm:h-24 rounded-xl object-cover bg-slate-100 border border-slate-200 shrink-0">
          <div class="flex-1 min-w-0 space-y-1.5">
            <div class="flex items-start justify-between gap-2">
              <h2 class="text-sm font-bold text-[#0D2C54] m-0">{{ item.name }}</h2>
              <button type="button" class="text-slate-400 hover:text-[#C81E2B] p-1" aria-label="Xóa sản phẩm" @click="removeItem(idx)">
                <Trash2 class="w-4 h-4" />
              </button>
            </div>
            <p class="text-xs text-slate-600 m-0">{{ item.material }} · {{ item.color }}</p>
            <p v-if="item.formLabel" class="text-xs text-slate-500 m-0">{{ item.formLabel }}</p>
            <p v-if="item.addons?.length" class="text-[11px] text-[#0D2C54] font-medium m-0">+ {{ item.addons.join(', ') }}</p>
            <div class="flex items-center justify-between pt-2">
              <div class="inline-flex items-center border border-slate-300 rounded-lg bg-white">
                <button type="button" class="w-8 h-8 flex items-center justify-center text-slate-600" aria-label="Giảm" @click="updateQuantity(idx, -1)">
                  <Minus class="w-3.5 h-3.5" />
                </button>
                <span class="w-8 text-center text-xs font-semibold tabular-nums">{{ item.quantity }}</span>
                <button type="button" class="w-8 h-8 flex items-center justify-center text-slate-600" aria-label="Tăng" @click="updateQuantity(idx, 1)">
                  <Plus class="w-3.5 h-3.5" />
                </button>
              </div>
              <span class="font-bold text-[#15803D] text-sm sm:text-base tabular-nums">{{ formatCurrency(item.price * item.quantity) }}</span>
            </div>
          </div>
        </div>
      </div>

      <aside class="card-surface p-5 space-y-4">
        <h2 class="text-sm font-bold uppercase text-[#0D2C54] pb-3 border-b border-slate-200 m-0">Tóm tắt đơn hàng</h2>

        <form class="flex gap-2" @submit.prevent="applyCoupon">
          <input v-model="couponInput" type="text" placeholder="Mã giảm giá (VD: THAMOTO2026)" class="field-input text-xs uppercase">
          <button type="submit" class="btn-outline text-xs px-3.5 shrink-0">Áp dụng</button>
        </form>
        <p v-if="couponMsg" class="text-xs m-0 font-semibold" :class="couponError ? 'text-[#C81E2B]' : 'text-[#15803D]'">
          {{ couponMsg }}
        </p>

        <div class="space-y-2 text-xs sm:text-sm pt-2 border-t border-slate-200">
          <div class="flex justify-between text-slate-600">
            <span>Tạm tính</span>
            <span class="font-semibold text-slate-900 tabular-nums">{{ formatCurrency(subtotal) }}</span>
          </div>
          <div class="flex justify-between text-slate-600">
            <span>Vận chuyển &amp; Lắp đặt</span>
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

        <NuxtLink to="/thanh-toan" class="btn-cta w-full text-xs">TIẾN HÀNH THANH TOÁN</NuxtLink>
      </aside>
    </div>
  </main>
</template>
