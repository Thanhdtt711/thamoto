<script setup lang="ts">
import { X, CheckCircle2, XCircle, Building2 } from 'lucide-vue-next';

const props = defineProps<{ affiliateId: string | null }>();
const emit = defineEmits<{ close: []; updated: [] }>();

const { supabase } = useSupabase();
const { showToast } = useToast();

const loading = ref(false);
const errorMsg = ref('');
const detail = ref<any>(null);
const busy = ref(false);

const loadDetail = async () => {
  if (!supabase || !props.affiliateId) return;
  loading.value = true;
  errorMsg.value = '';
  const { data, error } = await supabase.rpc('admin_get_affiliate_detail', { p_affiliate_id: props.affiliateId });
  loading.value = false;
  if (error) {
    errorMsg.value = error.message || 'Không tải được hồ sơ CTV.';
    return;
  }
  detail.value = data;
};

watch(() => props.affiliateId, (id) => {
  if (id) loadDetail();
  else detail.value = null;
}, { immediate: true });

const verifyBank = async (status: 'verified' | 'rejected') => {
  if (!supabase || !props.affiliateId) return;
  let reason: string | null = null;
  if (status === 'rejected') {
    const input = window.prompt('Nhập lý do từ chối tài khoản ngân hàng (bắt buộc):', '');
    if (!input || input.trim().length < 3) {
      showToast('Cần nhập lý do tối thiểu 3 ký tự.');
      return;
    }
    reason = input.trim();
  }
  busy.value = true;
  const { error } = await supabase.rpc('admin_verify_bank_account', {
    p_affiliate_id: props.affiliateId,
    p_status: status,
    p_reject_reason: reason
  });
  busy.value = false;
  if (error) {
    showToast(error.message || 'Không cập nhật được trạng thái ngân hàng.');
    return;
  }
  showToast(status === 'verified' ? 'Đã xác minh tài khoản ngân hàng CTV!' : 'Đã từ chối tài khoản ngân hàng CTV.');
  await loadDetail();
  emit('updated');
};
</script>

<template>
  <Teleport to="body">
    <div v-if="affiliateId" class="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4">
      <div class="absolute inset-0 bg-slate-900/60 backdrop-blur-[2px]" @click="emit('close')" />
      <div class="bg-white border border-slate-200 rounded-2xl w-full max-w-xl max-h-[90vh] overflow-y-auto relative z-10 shadow-2xl p-5 sm:p-6 space-y-5">
        <div class="flex items-center justify-between border-b border-slate-200 pb-3">
          <h3 class="text-base font-extrabold text-[#0D2C54] uppercase m-0">
            Hồ sơ CTV <span v-if="detail?.affiliate" class="text-[#C81E2B]">{{ detail.affiliate.code }}</span>
          </h3>
          <button type="button" aria-label="Đóng" class="w-10 h-10 rounded-lg border border-slate-200 flex items-center justify-center bg-white cursor-pointer" @click="emit('close')">
            <X class="w-5 h-5 text-slate-600" />
          </button>
        </div>

        <div v-if="loading" class="py-10 text-center text-sm text-slate-500">Đang tải hồ sơ CTV...</div>
        <p v-else-if="errorMsg" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] rounded-lg p-3 m-0">{{ errorMsg }}</p>

        <template v-else-if="detail?.affiliate">
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-2.5 text-center">
            <div class="bg-slate-50 rounded-xl p-3">
              <p class="text-[10px] uppercase text-slate-500 font-bold m-0">Lượt click</p>
              <p class="text-base font-extrabold text-[#0D2C54] m-0 mt-0.5 tabular-nums">{{ detail.stats?.clicks_count || 0 }}</p>
            </div>
            <div class="bg-slate-50 rounded-xl p-3">
              <p class="text-[10px] uppercase text-slate-500 font-bold m-0">Đơn hàng</p>
              <p class="text-base font-extrabold text-[#0D2C54] m-0 mt-0.5 tabular-nums">{{ detail.stats?.total_orders || 0 }}</p>
            </div>
            <div class="bg-slate-50 rounded-xl p-3">
              <p class="text-[10px] uppercase text-slate-500 font-bold m-0">Khả dụng</p>
              <p class="text-sm font-extrabold text-[#15803D] m-0 mt-0.5 tabular-nums">{{ formatCurrency(detail.stats?.available_balance || 0) }}</p>
            </div>
            <div class="bg-slate-50 rounded-xl p-3">
              <p class="text-[10px] uppercase text-slate-500 font-bold m-0">Đã chi trả</p>
              <p class="text-sm font-extrabold text-slate-800 m-0 mt-0.5 tabular-nums">{{ formatCurrency(detail.stats?.paid_total || 0) }}</p>
            </div>
          </div>

          <div class="bg-slate-50 rounded-xl p-4 text-xs space-y-1.5">
            <p class="m-0"><strong>Họ tên:</strong> {{ detail.affiliate.full_name }}</p>
            <p class="m-0"><strong>Email:</strong> {{ detail.affiliate.email }}</p>
            <p class="m-0"><strong>SĐT / Zalo:</strong> {{ detail.affiliate.phone || '—' }} / {{ detail.affiliate.zalo || '—' }}</p>
            <p class="m-0"><strong>Khu vực / Nghề:</strong> {{ detail.affiliate.area || '—' }} · {{ detail.affiliate.job_type || '—' }}</p>
            <p class="m-0"><strong>Hoa hồng:</strong> {{ detail.affiliate.commission_rate }}% · <strong>Vai trò:</strong> {{ detail.affiliate.role }}</p>
          </div>

          <div class="border border-slate-200 rounded-xl p-4 space-y-3">
            <div class="flex items-center justify-between">
              <h4 class="text-xs font-extrabold uppercase text-[#0D2C54] m-0 flex items-center gap-1.5">
                <Building2 class="w-4 h-4" /> Tài khoản ngân hàng
              </h4>
              <span
                v-if="detail.bank"
                class="px-2 py-0.5 rounded-full text-[11px] font-bold border"
                :class="detail.bank.status === 'verified' ? 'bg-green-50 text-[#15803D] border-green-200' : detail.bank.status === 'rejected' ? 'bg-[#FEF2F2] text-[#C81E2B] border-[#C81E2B]/25' : 'bg-amber-50 text-amber-700 border-amber-200'"
              >
                {{ detail.bank.status === 'verified' ? 'Đã xác minh' : detail.bank.status === 'rejected' ? 'Từ chối' : 'Chờ xác minh' }}
              </span>
            </div>

            <p v-if="!detail.bank" class="text-xs text-slate-500 m-0">CTV chưa cập nhật thông tin ngân hàng.</p>
            <template v-else>
              <div class="text-xs space-y-1">
                <p class="m-0"><strong>Ngân hàng:</strong> {{ detail.bank.bank_name }} <span v-if="detail.bank.branch">({{ detail.bank.branch }})</span></p>
                <p class="m-0"><strong>Số tài khoản:</strong> <span class="font-mono font-bold">{{ detail.bank.account_number }}</span></p>
                <p class="m-0"><strong>Chủ tài khoản:</strong> {{ detail.bank.account_holder }}</p>
                <p v-if="detail.bank.reject_reason" class="m-0 text-[#C81E2B] font-semibold">Lý do từ chối: {{ detail.bank.reject_reason }}</p>
              </div>
              <div class="flex flex-wrap gap-2 pt-1">
                <button type="button" :disabled="busy || detail.bank.status === 'verified'" class="btn-cta text-xs px-4" @click="verifyBank('verified')">
                  <CheckCircle2 class="w-4 h-4" /> Xác minh ngân hàng
                </button>
                <button type="button" :disabled="busy" class="btn-outline text-xs px-4 text-[#C81E2B] border-[#C81E2B]/40" @click="verifyBank('rejected')">
                  <XCircle class="w-4 h-4" /> Từ chối
                </button>
              </div>
            </template>
          </div>
        </template>
      </div>
    </div>
  </Teleport>
</template>
