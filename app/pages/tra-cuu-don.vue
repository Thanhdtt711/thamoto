<script setup lang="ts">
import { Search, Package, Truck, CheckCircle2, Clock, XCircle } from 'lucide-vue-next';

useSeoMeta({
  title: 'Tra Cứu Đơn Hàng | Trung Thành Auto',
  description: 'Kiểm tra trạng thái đơn hàng, thanh toán và mã vận đơn thảm lót sàn ô tô Trung Thành Auto.'
});

const route = useRoute();
const { supabase, isConfigured } = useSupabase();

const orderCode = ref(route.query.code ? String(route.query.code).trim().toUpperCase() : '');
const phone = ref('');
const loading = ref(false);
const errorMsg = ref('');
const order = ref<any>(null);

const STATUS_LABELS: Record<string, string> = {
  new: 'Mới đặt — chờ xác nhận phom xe',
  confirmed: 'Đã xác nhận — đang cắt may',
  shipping: 'Đang giao hàng / lắp đặt',
  completed: 'Đã hoàn thành',
  cancelled: 'Đã hủy',
  returned: 'Đã hoàn trả'
};

const PAY_LABELS: Record<string, string> = {
  unpaid: 'Chưa thanh toán',
  paid: 'Đã thanh toán',
  refunded: 'Đã hoàn tiền'
};

const STEPS = [
  { key: 'new', label: 'Tiếp nhận', icon: Clock },
  { key: 'confirmed', label: 'Xác nhận & May', icon: Package },
  { key: 'shipping', label: 'Đang giao', icon: Truck },
  { key: 'completed', label: 'Hoàn thành', icon: CheckCircle2 }
];

const currentStepIndex = computed(() => {
  if (!order.value) return -1;
  const idx = STEPS.findIndex((s) => s.key === order.value.status);
  return idx;
});

const formatDate = (iso: string) =>
  iso ? new Date(iso).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';

const handleTrack = async () => {
  errorMsg.value = '';
  order.value = null;
  const cleanCode = orderCode.value.trim().toUpperCase();
  const cleanPhone = phone.value.replace(/[^0-9]/g, '');

  if (cleanCode.length < 5) {
    errorMsg.value = 'Vui lòng nhập mã đơn hàng hợp lệ (VD: TT-261125-XXXXXX).';
    return;
  }
  if (cleanPhone.length < 9) {
    errorMsg.value = 'Vui lòng nhập đúng số điện thoại đã dùng khi đặt hàng.';
    return;
  }
  if (!isConfigured || !supabase) {
    errorMsg.value = 'Hệ thống tra cứu đang bảo trì. Vui lòng nhắn Zalo 0963 294 492 để kiểm tra đơn.';
    return;
  }

  loading.value = true;
  try {
    const { data, error } = await supabase.rpc('track_order', {
      p_order_code: cleanCode,
      p_phone: cleanPhone
    });
    if (error) throw error;
    if (!data?.found) {
      errorMsg.value = data?.message || 'Không tìm thấy đơn hàng khớp với thông tin đã nhập.';
      return;
    }
    order.value = data.order;
  } catch (err: any) {
    errorMsg.value = err?.message || 'Không thể tra cứu lúc này. Vui lòng thử lại sau.';
  } finally {
    loading.value = false;
  }
};
</script>

<template>
  <main id="main-content" class="container-app py-6 md:py-10 space-y-6">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54]">Tra cứu đơn hàng</span>
    </nav>

    <div class="max-w-xl mx-auto space-y-5">
      <div class="card-surface p-5 sm:p-7 space-y-4">
        <div class="text-center space-y-1">
          <h1 class="text-xl font-extrabold uppercase text-[#0D2C54] m-0">Tra Cứu Đơn Hàng</h1>
          <p class="text-xs sm:text-sm text-slate-500 m-0">Nhập mã đơn và số điện thoại đặt hàng để xem tiến độ cắt may &amp; giao lắp.</p>
        </div>

        <p v-if="errorMsg" role="alert" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3.5 py-2.5 m-0">
          {{ errorMsg }}
        </p>

        <form class="space-y-3.5" @submit.prevent="handleTrack">
          <div class="space-y-1">
            <label for="track-code" class="text-xs font-semibold text-slate-700 block">Mã đơn hàng *</label>
            <input id="track-code" v-model="orderCode" type="text" required placeholder="VD: TT-261125-AB12CD" class="field-input uppercase">
          </div>
          <div class="space-y-1">
            <label for="track-phone" class="text-xs font-semibold text-slate-700 block">Số điện thoại đặt hàng *</label>
            <input id="track-phone" v-model="phone" type="tel" required placeholder="VD: 0963294492" class="field-input tabular-nums">
          </div>
          <button type="submit" :disabled="loading" class="btn-cta w-full text-sm">
            <Search class="w-4 h-4" /> {{ loading ? 'ĐANG TRA CỨU...' : 'TRA CỨU ĐƠN HÀNG' }}
          </button>
        </form>
      </div>

      <!-- Result Card -->
      <div v-if="order" class="card-surface p-5 sm:p-6 space-y-5">
        <div class="flex flex-wrap items-center justify-between gap-2 pb-3 border-b border-slate-200">
          <div>
            <span class="text-xs text-slate-500 block">Mã đơn hàng</span>
            <strong class="text-base text-[#0D2C54] tabular-nums">#{{ order.order_code }}</strong>
          </div>
          <span
            class="px-3 py-1 rounded-full text-xs font-bold border"
            :class="order.status === 'completed' ? 'bg-green-50 text-[#15803D] border-green-200' : (order.status === 'cancelled' || order.status === 'returned') ? 'bg-[#FEF2F2] text-[#C81E2B] border-[#C81E2B]/30' : 'bg-[#EFF4FA] text-[#0D2C54] border-[#0D2C54]/20'"
          >
            {{ STATUS_LABELS[order.status] || order.status }}
          </span>
        </div>

        <!-- Stepper for active/completed orders -->
        <div v-if="currentStepIndex >= 0" class="grid grid-cols-4 gap-2 text-center">
          <div v-for="(s, idx) in STEPS" :key="s.key" class="flex flex-col items-center gap-1.5">
            <div
              class="w-9 h-9 rounded-full flex items-center justify-center border text-xs font-bold"
              :class="idx <= currentStepIndex ? 'bg-[#0D2C54] text-white border-[#0D2C54]' : 'bg-slate-50 text-slate-400 border-slate-200'"
            >
              <component :is="s.icon" class="w-4 h-4" />
            </div>
            <span class="text-[11px] font-semibold" :class="idx <= currentStepIndex ? 'text-[#0D2C54]' : 'text-slate-400'">{{ s.label }}</span>
          </div>
        </div>
        <div v-else class="flex items-center gap-2 text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] rounded-lg p-3">
          <XCircle class="w-4 h-4 shrink-0" />
          <span>{{ STATUS_LABELS[order.status] }}<template v-if="order.cancel_reason"> — {{ order.cancel_reason }}</template></span>
        </div>

        <div class="bg-[#F4F6F9] rounded-xl p-4 text-xs sm:text-sm space-y-2">
          <div class="flex justify-between gap-2"><span class="text-slate-500">Khách hàng:</span><span class="font-semibold text-slate-900">{{ order.customer_name_masked }}</span></div>
          <div class="flex justify-between gap-2"><span class="text-slate-500">Ngày đặt:</span><span class="font-semibold text-slate-900 tabular-nums">{{ formatDate(order.created_at) }}</span></div>
          <div class="flex justify-between gap-2"><span class="text-slate-500">Thanh toán:</span><span class="font-semibold text-slate-900">{{ order.payment_method }} · {{ PAY_LABELS[order.payment_status] || order.payment_status }}</span></div>
          <div v-if="order.shipping_carrier || order.tracking_code" class="flex justify-between gap-2">
            <span class="text-slate-500">Vận chuyển:</span>
            <span class="font-semibold text-[#0D2C54]">{{ [order.shipping_carrier, order.tracking_code].filter(Boolean).join(' · ') }}</span>
          </div>
          <div v-if="order.items_summary" class="pt-2 border-t border-slate-200">
            <span class="text-slate-500 block mb-1">Sản phẩm:</span>
            <p class="m-0 text-slate-800 whitespace-pre-line text-xs">{{ order.items_summary }}</p>
          </div>
          <div class="flex justify-between pt-2 border-t border-slate-200">
            <span class="font-semibold text-slate-700">Tổng thanh toán:</span>
            <strong class="text-[#15803D] tabular-nums">{{ formatCurrency(order.total_amount) }}</strong>
          </div>
        </div>

        <div class="text-center">
          <a href="https://zalo.me/0963294492" target="_blank" rel="noopener" class="btn-outline text-xs px-5 no-underline">
            Cần hỗ trợ? Nhắn Zalo 0963 294 492
          </a>
        </div>
      </div>
    </div>
  </main>
</template>
