<script setup lang="ts">
import { Save, ChevronLeft, ChevronRight } from 'lucide-vue-next';

const { supabase } = useSupabase();
const { showToast } = useToast();

const search = ref('');
const page = ref(1);
const pageSize = 20;
const total = ref(0);
const items = ref<any[]>([]);
const loading = ref(false);

const totalPages = computed(() => Math.max(1, Math.ceil(total.value / pageSize)));

const loadCustomers = async () => {
  if (!supabase) return;
  loading.value = true;
  const { data, error } = await supabase.rpc('admin_list_customers', {
    p_search: search.value.trim() || null,
    p_page: page.value,
    p_page_size: pageSize
  });
  loading.value = false;
  if (error) {
    showToast(error.message || 'Không tải được danh sách khách hàng.');
    return;
  }
  items.value = Array.isArray(data?.items) ? data.items : [];
  total.value = Number(data?.total || 0);
};

let timer: ReturnType<typeof setTimeout> | null = null;
watch(search, () => {
  page.value = 1;
  if (timer) clearTimeout(timer);
  timer = setTimeout(loadCustomers, 250);
});

onMounted(loadCustomers);

const saveNote = async (c: any) => {
  if (!supabase) return;
  const { error } = await supabase.rpc('admin_update_customer_note', {
    p_customer_id: c.id,
    p_note: c.note || ''
  });
  if (error) { showToast(error.message); return; }
  showToast('Đã lưu ghi chú khách hàng.');
};
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4">
    <div class="flex flex-col sm:flex-row gap-3">
      <input v-model="search" type="text" placeholder="Tìm khách theo tên, số điện thoại, địa chỉ..." class="field-input flex-1">
    </div>

    <div v-if="loading" class="py-10 text-center text-sm text-slate-500">Đang tải danh sách khách hàng...</div>
    <div v-else-if="!items.length" class="py-10 text-center text-sm text-slate-500">Chưa có dữ liệu khách hàng.</div>
    <div v-else class="overflow-x-auto">
      <table class="w-full text-left text-xs border-collapse min-w-[680px]">
        <thead class="bg-slate-50 border-b border-slate-200 text-[11px] uppercase text-slate-500">
          <tr>
            <th class="py-2.5 px-3">Khách hàng</th>
            <th class="py-2.5 px-3">Địa chỉ</th>
            <th class="py-2.5 px-3 text-right">Số đơn</th>
            <th class="py-2.5 px-3 text-right">Tổng chi tiêu</th>
            <th class="py-2.5 px-3">Ghi chú chăm sóc</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="c in items" :key="c.id" class="border-b border-slate-100">
            <td class="py-2.5 px-3">
              <span class="font-bold text-slate-900 block">{{ c.full_name }}</span>
              <span class="text-slate-500 tabular-nums">{{ c.phone }}</span>
            </td>
            <td class="py-2.5 px-3 text-slate-600 max-w-[200px] truncate">{{ c.address || '—' }}</td>
            <td class="py-2.5 px-3 text-right font-bold tabular-nums">{{ c.total_orders }}</td>
            <td class="py-2.5 px-3 text-right font-bold text-[#15803D] tabular-nums">{{ formatCurrency(c.total_spent) }}</td>
            <td class="py-2.5 px-3">
              <div class="flex items-center gap-1.5">
                <input v-model="c.note" type="text" placeholder="Thêm ghi chú..." class="field-input py-1 text-xs min-h-[38px]">
                <button type="button" aria-label="Lưu ghi chú" class="btn-outline text-xs px-2.5 min-h-[38px]" @click="saveNote(c)">
                  <Save class="w-3.5 h-3.5" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="totalPages > 1" class="flex items-center justify-between pt-2">
      <span class="text-xs text-slate-500 tabular-nums">Trang {{ page }} / {{ totalPages }} ({{ total }} khách)</span>
      <div class="flex gap-2">
        <button type="button" class="btn-outline text-xs px-3" :disabled="page <= 1" @click="page--; loadCustomers()"><ChevronLeft class="w-4 h-4" /> Trước</button>
        <button type="button" class="btn-outline text-xs px-3" :disabled="page >= totalPages" @click="page++; loadCustomers()">Sau <ChevronRight class="w-4 h-4" /></button>
      </div>
    </div>
  </div>
</template>
