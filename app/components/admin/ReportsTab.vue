<script setup lang="ts">
import { BarChart3, RefreshCw } from 'lucide-vue-next';

const { supabase } = useSupabase();
const { showToast } = useToast();

const todayStr = new Date().toISOString().slice(0, 10);
const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

const fromDate = ref(thirtyDaysAgo);
const toDate = ref(todayStr);
const loading = ref(false);
const report = ref<any>(null);

const maxDailyRev = computed(() => {
  const arr = report.value?.daily || [];
  return Math.max(1, ...arr.map((d: any) => Number(d.revenue || 0)));
});

const loadReports = async () => {
  if (!supabase) return;
  loading.value = true;
  const { data, error } = await supabase.rpc('admin_reports', {
    p_from: fromDate.value ? `${fromDate.value}T00:00:00+07:00` : null,
    p_to: toDate.value ? `${toDate.value}T23:59:59+07:00` : null
  });
  loading.value = false;
  if (error) {
    showToast(error.message || 'Không tải được báo cáo.');
    return;
  }
  report.value = data;
};

onMounted(loadReports);
</script>

<template>
  <div class="p-4 sm:p-5 space-y-5">
    <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-3">
      <div class="flex flex-wrap items-end gap-3">
        <div class="space-y-1">
          <label for="rep-from" class="text-xs font-semibold text-slate-600 block">Từ ngày</label>
          <input id="rep-from" v-model="fromDate" type="date" class="field-input text-xs">
        </div>
        <div class="space-y-1">
          <label for="rep-to" class="text-xs font-semibold text-slate-600 block">Đến ngày</label>
          <input id="rep-to" v-model="toDate" type="date" class="field-input text-xs">
        </div>
        <button type="button" :disabled="loading" class="btn-cta text-xs px-4" @click="loadReports">
          <RefreshCw class="w-4 h-4" :class="loading ? 'animate-spin' : ''" /> Xem báo cáo
        </button>
      </div>
    </div>

    <div v-if="loading" class="py-10 text-center text-sm text-slate-500">Đang tổng hợp báo cáo...</div>
    <template v-else-if="report?.summary">
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div class="border border-slate-200 rounded-xl p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Doanh thu hoàn thành</p>
          <p class="text-lg font-extrabold text-[#15803D] m-0 mt-1 tabular-nums">{{ formatCurrency(report.summary.completed_revenue) }}</p>
        </div>
        <div class="border border-slate-200 rounded-xl p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Tổng đơn / Hoàn thành</p>
          <p class="text-lg font-extrabold text-[#0D2C54] m-0 mt-1 tabular-nums">{{ report.summary.total_orders }} / {{ report.summary.completed_orders }}</p>
        </div>
        <div class="border border-slate-200 rounded-xl p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Tỷ lệ hủy / hoàn</p>
          <p class="text-lg font-extrabold text-[#C81E2B] m-0 mt-1 tabular-nums">{{ report.summary.cancel_rate }}%</p>
        </div>
        <div class="border border-slate-200 rounded-xl p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Tổng hoa hồng phát sinh</p>
          <p class="text-lg font-extrabold text-amber-600 m-0 mt-1 tabular-nums">{{ formatCurrency(report.summary.total_commission) }}</p>
        </div>
      </div>

      <!-- Daily Revenue Bar Chart -->
      <div class="border border-slate-200 rounded-xl p-4 space-y-3">
        <h3 class="text-xs font-extrabold uppercase text-[#0D2C54] m-0 flex items-center gap-1.5">
          <BarChart3 class="w-4 h-4" /> Biểu đồ doanh thu theo ngày
        </h3>
        <div v-if="!report.daily?.length" class="py-6 text-center text-xs text-slate-500">Chưa có dữ liệu đơn hàng trong khoảng ngày này.</div>
        <div v-else class="space-y-2 max-h-64 overflow-y-auto pr-1">
          <div v-for="d in report.daily" :key="d.day" class="flex items-center gap-3 text-xs">
            <span class="w-24 shrink-0 font-mono text-slate-600 tabular-nums">{{ d.day }}</span>
            <div class="flex-1 h-5 bg-slate-100 rounded-md overflow-hidden">
              <div class="h-full bg-[#0D2C54] rounded-md transition-all" :style="{ width: `${Math.max(4, Math.round((Number(d.revenue || 0) / maxDailyRev) * 100))}%` }" />
            </div>
            <span class="w-32 shrink-0 text-right font-semibold text-slate-800 tabular-nums">{{ formatCurrency(d.revenue) }} ({{ d.orders }})</span>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="border border-slate-200 rounded-xl p-4 space-y-2.5">
          <h3 class="text-xs font-extrabold uppercase text-[#0D2C54] m-0">Top CTV doanh thu cao</h3>
          <div v-if="!report.top_affiliates?.length" class="text-xs text-slate-500 py-4 text-center">Chưa có dữ liệu CTV.</div>
          <table v-else class="w-full text-left text-xs border-collapse">
            <thead class="text-[11px] uppercase text-slate-500 border-b border-slate-200">
              <tr><th class="py-1.5">CTV</th><th class="py-1.5 text-right">Đơn</th><th class="py-1.5 text-right">Doanh thu</th></tr>
            </thead>
            <tbody>
              <tr v-for="a in report.top_affiliates" :key="a.code" class="border-b border-slate-100 last:border-0">
                <td class="py-2"><strong class="text-[#0D2C54]">{{ a.code }}</strong> · {{ a.full_name }}</td>
                <td class="py-2 text-right tabular-nums">{{ a.orders }}</td>
                <td class="py-2 text-right font-bold text-[#15803D] tabular-nums">{{ formatCurrency(a.completed_revenue) }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="border border-slate-200 rounded-xl p-4 space-y-2.5">
          <h3 class="text-xs font-extrabold uppercase text-[#0D2C54] m-0">Top sản phẩm bán chạy</h3>
          <div v-if="!report.top_products?.length" class="text-xs text-slate-500 py-4 text-center">Chưa có dữ liệu chi tiết sản phẩm.</div>
          <table v-else class="w-full text-left text-xs border-collapse">
            <thead class="text-[11px] uppercase text-slate-500 border-b border-slate-200">
              <tr><th class="py-1.5">Sản phẩm</th><th class="py-1.5 text-right">SL</th><th class="py-1.5 text-right">Doanh thu</th></tr>
            </thead>
            <tbody>
              <tr v-for="p in report.top_products" :key="p.product_name" class="border-b border-slate-100 last:border-0">
                <td class="py-2 font-semibold text-slate-800">{{ p.product_name }}</td>
                <td class="py-2 text-right tabular-nums">{{ p.qty }}</td>
                <td class="py-2 text-right font-bold text-[#0D2C54] tabular-nums">{{ formatCurrency(p.revenue) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </div>
</template>
