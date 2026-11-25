<script setup lang="ts">
import { ChevronLeft, ChevronRight } from 'lucide-vue-next';

const { supabase } = useSupabase();
const { showToast } = useToast();

const entityFilter = ref('all');
const search = ref('');
const page = ref(1);
const pageSize = 30;
const total = ref(0);
const logs = ref<any[]>([]);
const loading = ref(false);

const totalPages = computed(() => Math.max(1, Math.ceil(total.value / pageSize)));
const formatDate = (iso: string) =>
  iso ? new Date(iso).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';

const ACTION_LABELS: Record<string, string> = {
  admin_set_order_status: 'Đổi trạng thái đơn hàng',
  admin_set_payment_status: 'Đổi trạng thái thu tiền',
  admin_update_affiliate: 'Cập nhật CTV',
  develop_set_account_role: 'Đổi vai trò tài khoản',
  admin_approve_commissions: 'Duyệt mở khóa hoa hồng',
  admin_pay_commissions: 'Chi trả hoa hồng',
  admin_verify_bank_account: 'Xác minh ngân hàng CTV',
  ctv_update_profile: 'CTV cập nhật hồ sơ',
  ctv_update_bank_account: 'CTV cập nhật ngân hàng',
  ctv_request_payout: 'CTV yêu cầu rút tiền',
  admin_approve_payout_request: 'Duyệt yêu cầu rút tiền',
  admin_reject_payout_request: 'Từ chối yêu cầu rút tiền'
};

const loadLogs = async () => {
  if (!supabase) return;
  loading.value = true;
  const { data, error } = await supabase.rpc('admin_list_audit_logs', {
    p_entity_type: entityFilter.value,
    p_search: search.value.trim() || null,
    p_page: page.value,
    p_page_size: pageSize
  });
  loading.value = false;
  if (error) {
    showToast(error.message || 'Không tải được nhật ký hoạt động.');
    return;
  }
  logs.value = Array.isArray(data?.items) ? data.items : [];
  total.value = Number(data?.total || 0);
};

let timer: ReturnType<typeof setTimeout> | null = null;
watch([entityFilter, search], () => {
  page.value = 1;
  if (timer) clearTimeout(timer);
  timer = setTimeout(loadLogs, 250);
});

onMounted(loadLogs);
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4">
    <div class="flex flex-col sm:flex-row gap-3">
      <input v-model="search" type="text" placeholder="Tìm theo hành động hoặc ID đối tượng..." class="field-input flex-1">
      <select v-model="entityFilter" class="field-input sm:w-52">
        <option value="all">Tất cả đối tượng</option>
        <option value="orders">Đơn hàng (orders)</option>
        <option value="affiliates">CTV (affiliates)</option>
        <option value="commission_payouts">Chi trả (payouts)</option>
        <option value="payout_requests">Yêu cầu rút tiền</option>
        <option value="affiliate_bank_accounts">Ngân hàng CTV</option>
      </select>
    </div>

    <div v-if="loading" class="py-10 text-center text-sm text-slate-500">Đang tải nhật ký hoạt động...</div>
    <div v-else-if="!logs.length" class="py-10 text-center text-sm text-slate-500">Chưa có nhật ký nào.</div>
    <div v-else class="overflow-x-auto">
      <table class="w-full text-left text-xs border-collapse min-w-[680px]">
        <thead class="bg-slate-50 border-b border-slate-200 text-[11px] uppercase text-slate-500">
          <tr>
            <th class="py-2.5 px-3">Thời gian</th>
            <th class="py-2.5 px-3">Vai trò</th>
            <th class="py-2.5 px-3">Hành động</th>
            <th class="py-2.5 px-3">Đối tượng</th>
            <th class="py-2.5 px-3">Dữ liệu mới</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="l in logs" :key="l.id" class="border-b border-slate-100">
            <td class="py-2.5 px-3 text-slate-500 whitespace-nowrap tabular-nums">{{ formatDate(l.created_at) }}</td>
            <td class="py-2.5 px-3 font-semibold text-[#0D2C54]">{{ l.actor_role || 'system' }}</td>
            <td class="py-2.5 px-3 font-semibold text-slate-900">{{ ACTION_LABELS[l.action] || l.action }}</td>
            <td class="py-2.5 px-3 text-slate-600">{{ l.entity_type }} <span class="font-mono text-[10px] text-slate-400">#{{ String(l.entity_id || '').slice(0, 8) }}</span></td>
            <td class="py-2.5 px-3 font-mono text-[10px] text-slate-600 max-w-[260px] truncate">{{ l.new_data ? JSON.stringify(l.new_data) : '—' }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="totalPages > 1" class="flex items-center justify-between pt-2">
      <span class="text-xs text-slate-500 tabular-nums">Trang {{ page }} / {{ totalPages }} ({{ total }} dòng)</span>
      <div class="flex gap-2">
        <button type="button" class="btn-outline text-xs px-3" :disabled="page <= 1" @click="page--; loadLogs()"><ChevronLeft class="w-4 h-4" /> Trước</button>
        <button type="button" class="btn-outline text-xs px-3" :disabled="page >= totalPages" @click="page++; loadLogs()">Sau <ChevronRight class="w-4 h-4" /></button>
      </div>
    </div>
  </div>
</template>
