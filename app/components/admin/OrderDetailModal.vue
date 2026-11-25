<script setup lang="ts">
import { X, CreditCard, History, Package, Truck, Printer } from 'lucide-vue-next';

const props = defineProps<{ orderId: string | null }>();
const emit = defineEmits<{ close: []; updated: [] }>();

const { supabase } = useSupabase();
const { showToast } = useToast();

const loading = ref(false);
const errorMsg = ref('');
const detail = ref<any>(null);
const savingPayment = ref(false);
const savingShipping = ref(false);
const carrierInput = ref('');
const trackingInput = ref('');

const formatDate = (iso: string) =>
  iso ? new Date(iso).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';

const ACTION_LABELS: Record<string, string> = {
  admin_set_order_status: 'Đổi trạng thái đơn hàng',
  admin_set_payment_status: 'Đổi trạng thái thu tiền',
  admin_approve_commissions: 'Duyệt mở khóa hoa hồng',
  admin_pay_commissions: 'Chi trả hoa hồng'
};

const VALUE_LABELS: Record<string, string> = {
  unpaid: 'Chưa thu tiền',
  paid: 'Đã thanh toán',
  refunded: 'Đã hoàn tiền',
  new: 'Mới',
  confirmed: 'Đã xác nhận',
  shipping: 'Đang giao',
  completed: 'Hoàn thành',
  cancelled: 'Đã hủy',
  returned: 'Hoàn trả'
};

const formatAuditChange = (log: any) => {
  const parts: string[] = [];
  if (log.old_data?.payment_status !== undefined || log.new_data?.payment_status !== undefined) {
    const from = VALUE_LABELS[log.old_data?.payment_status] || log.old_data?.payment_status || '—';
    const to = VALUE_LABELS[log.new_data?.payment_status] || log.new_data?.payment_status || '—';
    parts.push(`${from} → ${to}`);
  }
  if (log.old_data?.status !== undefined || log.new_data?.status !== undefined) {
    const from = VALUE_LABELS[log.old_data?.status] || log.old_data?.status || '—';
    const to = VALUE_LABELS[log.new_data?.status] || log.new_data?.status || '—';
    if (from !== to) parts.push(`${from} → ${to}`);
  }
  if (log.reason) parts.push(`Lý do: ${log.reason}`);
  return parts.join(' · ');
};

const loadDetail = async () => {
  if (!supabase || !props.orderId) return;
  loading.value = true;
  errorMsg.value = '';
  const { data, error } = await supabase.rpc('admin_get_order_detail', { p_order_id: props.orderId });
  loading.value = false;
  if (error) {
    errorMsg.value = error.message || 'Không tải được chi tiết đơn hàng.';
    return;
  }
  detail.value = data;
  carrierInput.value = data?.order?.shipping_carrier || '';
  trackingInput.value = data?.order?.tracking_code || '';
};

const saveShipping = async () => {
  if (!supabase || !props.orderId) return;
  savingShipping.value = true;
  const { error } = await supabase.rpc('admin_update_shipping', {
    p_order_id: props.orderId,
    p_carrier: carrierInput.value.trim(),
    p_tracking_code: trackingInput.value.trim()
  });
  savingShipping.value = false;
  if (error) {
    showToast(error.message || 'Không lưu được thông tin vận đơn.');
    return;
  }
  showToast('Đã cập nhật đơn vị vận chuyển & mã vận đơn.');
  await loadDetail();
  emit('updated');
};

const printOrder = () => {
  if (import.meta.client) window.print();
};

watch(() => props.orderId, (id) => {
  if (id) loadDetail();
  else detail.value = null;
}, { immediate: true });

const updatePaymentStatus = async (status: string) => {
  if (!supabase || !props.orderId) return;
  savingPayment.value = true;
  const { error } = await supabase.rpc('admin_set_payment_status', {
    p_order_id: props.orderId,
    p_payment_status: status
  });
  savingPayment.value = false;
  if (error) {
    showToast(error.message || 'Không cập nhật được trạng thái thanh toán.');
    return;
  }
  showToast('Đã cập nhật trạng thái thanh toán.');
  await loadDetail();
  emit('updated');
};
</script>

<template>
  <Teleport to="body">
    <div v-if="orderId" class="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4">
      <div class="absolute inset-0 bg-slate-900/60 backdrop-blur-[2px]" @click="emit('close')" />
      <div class="bg-white border border-slate-200 rounded-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto relative z-10 shadow-2xl p-5 sm:p-6 space-y-5">
        <div class="flex items-center justify-between border-b border-slate-200 pb-3">
          <div>
            <h3 class="text-base font-extrabold text-[#0D2C54] uppercase m-0">
              Chi tiết đơn hàng <span v-if="detail?.order" class="text-[#C81E2B] tabular-nums">#{{ detail.order.order_code }}</span>
            </h3>
            <p v-if="detail?.order" class="text-xs text-slate-500 m-0 mt-0.5">{{ formatDate(detail.order.created_at) }}</p>
          </div>
          <div class="flex items-center gap-2">
            <button type="button" class="btn-outline text-xs px-3 min-h-[38px]" @click="printOrder">
              <Printer class="w-4 h-4" /> In phiếu
            </button>
            <button type="button" aria-label="Đóng" class="w-10 h-10 rounded-lg border border-slate-200 flex items-center justify-center bg-white cursor-pointer" @click="emit('close')">
              <X class="w-5 h-5 text-slate-600" />
            </button>
          </div>
        </div>

        <div v-if="loading" class="py-10 text-center text-sm text-slate-500">Đang tải chi tiết đơn hàng...</div>
        <p v-else-if="errorMsg" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] rounded-lg p-3 m-0">{{ errorMsg }}</p>

        <template v-else-if="detail?.order">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
            <div class="bg-slate-50 rounded-xl p-3.5 space-y-1.5">
              <p class="font-bold uppercase text-[#0D2C54] m-0">Khách hàng</p>
              <p class="m-0 font-semibold text-slate-900">{{ detail.order.customer_name }}</p>
              <p class="m-0 text-slate-700 tabular-nums">{{ detail.order.phone || detail.order.customer_phone }}</p>
              <p class="m-0 text-slate-600">{{ detail.order.address || detail.order.customer_address || '—' }}</p>
              <p v-if="detail.order.notes" class="m-0 text-slate-500 italic">Ghi chú: {{ detail.order.notes }}</p>
            </div>
            <div class="bg-slate-50 rounded-xl p-3.5 space-y-2">
              <p class="font-bold uppercase text-[#0D2C54] m-0 flex items-center gap-1.5">
                <CreditCard class="w-3.5 h-3.5" /> Thanh toán &amp; CTV
              </p>
              <p class="m-0">Phương thức: <strong>{{ detail.order.payment_method }}</strong></p>
              <div class="flex items-center gap-2">
                <label for="odm-pay-status" class="text-slate-600 shrink-0">Thu tiền:</label>
                <select
                  id="odm-pay-status"
                  :value="detail.order.payment_status || 'unpaid'"
                  :disabled="savingPayment"
                  class="field-input py-1 text-xs min-h-[36px]"
                  @change="updatePaymentStatus(($event.target as HTMLSelectElement).value)"
                >
                  <option value="unpaid">Chưa thu tiền</option>
                  <option value="paid">Đã thanh toán</option>
                  <option value="refunded">Đã hoàn tiền</option>
                </select>
              </div>
              <p v-if="detail.order.affiliate_code" class="m-0">
                CTV: <strong class="text-[#0D2C54]">{{ detail.order.affiliate_code }}</strong>
                (HH: <strong class="text-[#15803D] tabular-nums">{{ formatCurrency(detail.order.commission_amount) }}</strong>)
              </p>
              <p v-if="detail.order.cancel_reason" class="m-0 text-[#C81E2B] font-semibold">
                Lý do hủy/hoàn: {{ detail.order.cancel_reason }}
              </p>
            </div>
          </div>

          <!-- Shipping & Tracking Code (P1-2) -->
          <div class="bg-slate-50 rounded-xl p-3.5 space-y-2 text-xs">
            <p class="font-bold uppercase text-[#0D2C54] m-0 flex items-center gap-1.5">
              <Truck class="w-3.5 h-3.5" /> Vận chuyển &amp; Mã vận đơn
            </p>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
              <input v-model="carrierInput" type="text" placeholder="ĐVVC (VD: GHTK, GHN, Lắp tại nhà)" class="field-input py-1.5 text-xs min-h-[38px]">
              <input v-model="trackingInput" type="text" placeholder="Mã vận đơn (nếu có)" class="field-input py-1.5 text-xs min-h-[38px]">
              <button type="button" :disabled="savingShipping" class="btn-outline text-xs min-h-[38px]" @click="saveShipping">
                {{ savingShipping ? 'Đang lưu...' : 'Lưu vận đơn' }}
              </button>
            </div>
          </div>

          <!-- Items -->
          <div class="space-y-2">
            <h4 class="text-xs font-extrabold uppercase text-[#0D2C54] m-0 flex items-center gap-1.5">
              <Package class="w-4 h-4" /> Danh sách sản phẩm
            </h4>
            <div class="border border-slate-200 rounded-xl overflow-hidden">
              <table class="w-full text-left text-xs border-collapse">
                <thead class="bg-slate-50 border-b border-slate-200 text-[11px] text-slate-500 uppercase">
                  <tr>
                    <th class="py-2 px-3">Sản phẩm</th>
                    <th class="py-2 px-3 text-right">SL</th>
                    <th class="py-2 px-3 text-right">Đơn giá</th>
                    <th class="py-2 px-3 text-right">Thành tiền</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="(it, idx) in (detail.order_items?.length ? detail.order_items : (detail.order.items || []))" :key="idx" class="border-b border-slate-100 last:border-0">
                    <td class="py-2 px-3">
                      <span class="font-semibold text-slate-900 block">{{ it.product_name || it.name }}</span>
                      <span v-if="it.material || it.color" class="text-[11px] text-slate-500">{{ [it.material, it.color, it.form_label || it.formLabel].filter(Boolean).join(' · ') }}</span>
                    </td>
                    <td class="py-2 px-3 text-right tabular-nums">{{ it.quantity }}</td>
                    <td class="py-2 px-3 text-right tabular-nums">{{ formatCurrency(it.unit_price ?? it.price) }}</td>
                    <td class="py-2 px-3 text-right font-semibold tabular-nums">{{ formatCurrency(it.line_total ?? ((it.price || 0) * (it.quantity || 1))) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="flex flex-col items-end text-xs space-y-1 pt-1">
              <span>Tạm tính: <strong class="tabular-nums">{{ formatCurrency(detail.order.subtotal_amount ?? detail.order.total_amount) }}</strong></span>
              <span v-if="Number(detail.order.discount_amount || 0) > 0" class="text-[#15803D]">
                Giảm giá ({{ detail.order.coupon_code || 'KM' }}): <strong class="tabular-nums">-{{ formatCurrency(detail.order.discount_amount) }}</strong>
              </span>
              <span class="text-sm font-extrabold text-[#0D2C54]">Tổng cộng: <span class="text-[#15803D] tabular-nums">{{ formatCurrency(detail.order.total_amount ?? detail.order.total) }}</span></span>
            </div>
          </div>

          <!-- Audit history -->
          <div class="space-y-2">
            <h4 class="text-xs font-extrabold uppercase text-[#0D2C54] m-0 flex items-center gap-1.5">
              <History class="w-4 h-4" /> Lịch sử thao tác
            </h4>
            <div v-if="!detail.audit_logs?.length" class="text-xs text-slate-500">Chưa có nhật ký thay đổi cho đơn này.</div>
            <div v-else class="space-y-1.5 max-h-40 overflow-y-auto">
              <div v-for="log in detail.audit_logs" :key="log.id" class="text-[11px] bg-slate-50 border border-slate-100 rounded-lg px-3 py-2 flex items-start justify-between gap-2">
                <div class="space-y-0.5">
                  <div>
                    <span class="font-bold text-[#0D2C54]">{{ ACTION_LABELS[log.action] || log.action }}</span>
                    <span class="text-slate-500 ml-1.5">({{ log.actor_role || 'hệ thống' }})</span>
                  </div>
                  <p v-if="formatAuditChange(log)" class="m-0 text-slate-600">{{ formatAuditChange(log) }}</p>
                </div>
                <span class="text-slate-400 tabular-nums shrink-0">{{ formatDate(log.created_at) }}</span>
              </div>
            </div>
          </div>
        </template>
      </div>
    </div>
  </Teleport>
</template>
