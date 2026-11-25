<script setup lang="ts">
import { Plus, Save } from 'lucide-vue-next';

const { supabase } = useSupabase();
const { showToast } = useToast();

const subTab = ref<'products' | 'coupons' | 'rules' | 'settings'>('products');
const loading = ref(false);
const products = ref<any[]>([]);
const coupons = ref<any[]>([]);
const rules = ref<any[]>([]);
const appSettings = ref<any[]>([]);

const newProduct = ref({ sku: '', name: '', base_price: 1500000, stock_qty: 100 });
const newCoupon = ref({ code: '', discount_type: 'percent', discount_value: 5, min_order_amount: 0, max_discount_amount: 0 });
const newRule = ref({ product_id: '', rate: 12 });

const loadAll = async () => {
  if (!supabase) return;
  loading.value = true;
  const [pRes, cRes, rRes, sRes] = await Promise.all([
    supabase.from('products').select('*').order('created_at', { ascending: false }).limit(100),
    supabase.from('coupons').select('*').order('created_at', { ascending: false }).limit(100),
    supabase.from('commission_rules').select('*').order('created_at', { ascending: false }).limit(100),
    supabase.from('app_settings').select('*').order('key', { ascending: true })
  ]);
  products.value = pRes.data || [];
  coupons.value = cRes.data || [];
  rules.value = rRes.data || [];
  appSettings.value = (sRes.data || []).map((s: any) => ({ ...s, value: typeof s.value === 'string' ? s.value : String(s.value) }));
  loading.value = false;
};

onMounted(loadAll);

// Mọi thay đổi catalog/coupon/quy tắc/cài đặt đều đi qua RPC security definer (có kiểm tra quyền + ghi audit_logs)
const callRpc = async (fn: string, params: Record<string, any>) => {
  if (!supabase) return false;
  const { error } = await supabase.rpc(fn, params);
  if (error) { showToast(error.message); return false; }
  return true;
};

const askReason = (label: string): string | null => {
  if (typeof window === 'undefined') return null;
  const reason = window.prompt(`${label}\nNhập lý do thay đổi (sẽ lưu vào nhật ký):`, '');
  return reason === null ? undefined as any : (reason.trim() || null);
};

const addProduct = async () => {
  if (!newProduct.value.sku.trim() || !newProduct.value.name.trim()) return;
  const ok = await callRpc('admin_save_product', {
    p_id: null,
    p_sku: newProduct.value.sku.trim(),
    p_name: newProduct.value.name.trim(),
    p_base_price: Math.round(Number(newProduct.value.base_price || 0)),
    p_stock_qty: Number.isFinite(Number(newProduct.value.stock_qty)) ? Number(newProduct.value.stock_qty) : null,
    p_is_active: true,
    p_reason: null
  });
  if (!ok) return;
  newProduct.value = { sku: '', name: '', base_price: 1500000, stock_qty: 100 };
  showToast('Đã thêm sản phẩm mới.');
  await loadAll();
};

const saveProduct = async (p: any) => {
  const reason = askReason(`Lưu sản phẩm ${p.sku}`);
  if (reason === undefined) return;
  const ok = await callRpc('admin_save_product', {
    p_id: p.id,
    p_sku: p.sku,
    p_name: p.name,
    p_base_price: Math.round(Number(p.base_price || 0)),
    p_stock_qty: p.stock_qty === null || p.stock_qty === '' ? null : Number(p.stock_qty),
    p_is_active: !!p.is_active,
    p_reason: reason
  });
  if (ok) showToast(`Đã lưu ${p.sku}`);
};

const couponParams = (c: any, overrides: Record<string, any> = {}) => ({
  p_id: c.id ?? null,
  p_code: c.code,
  p_discount_type: c.discount_type,
  p_discount_value: Number(c.discount_value || 0),
  p_min_order_amount: Math.round(Number(c.min_order_amount || 0)),
  p_max_discount_amount: Number(c.max_discount_amount || 0) > 0 ? Math.round(Number(c.max_discount_amount)) : null,
  p_usage_limit: c.usage_limit ?? null,
  p_expires_at: c.expires_at ?? null,
  p_is_active: c.is_active ?? true,
  p_reason: null,
  ...overrides
});

const addCoupon = async () => {
  if (!newCoupon.value.code.trim()) return;
  const ok = await callRpc('admin_save_coupon', couponParams({ ...newCoupon.value, id: null, is_active: true }));
  if (!ok) return;
  newCoupon.value = { code: '', discount_type: 'percent', discount_value: 5, min_order_amount: 0, max_discount_amount: 0 };
  showToast('Đã tạo mã giảm giá.');
  await loadAll();
};

const toggleCoupon = async (c: any) => {
  const reason = askReason(`${c.is_active ? 'Tắt' : 'Bật'} mã ${c.code}`);
  if (reason === undefined) return;
  const ok = await callRpc('admin_save_coupon', couponParams(c, { p_is_active: !c.is_active, p_reason: reason }));
  if (ok) await loadAll();
};

const ruleParams = (r: any, overrides: Record<string, any> = {}) => ({
  p_id: r.id ?? null,
  p_product_id: r.product_id || null,
  p_affiliate_id: r.affiliate_id || null,
  p_rate: Number(r.rate || 0),
  p_is_active: r.is_active ?? true,
  p_valid_from: r.valid_from ?? null,
  p_valid_to: r.valid_to ?? null,
  p_reason: null,
  ...overrides
});

const addRule = async () => {
  const ok = await callRpc('admin_save_commission_rule', ruleParams({ ...newRule.value, id: null, is_active: true }));
  if (!ok) return;
  showToast('Đã thêm quy tắc hoa hồng.');
  await loadAll();
};

// Không xóa cứng: chỉ vô hiệu hóa để giữ lịch sử đối soát hoa hồng
const toggleRule = async (r: any) => {
  const reason = askReason(`${r.is_active ? 'Vô hiệu hóa' : 'Kích hoạt lại'} quy tắc ${r.rate}%`);
  if (reason === undefined) return;
  const ok = await callRpc('admin_save_commission_rule', ruleParams(r, { p_is_active: !r.is_active, p_reason: reason }));
  if (ok) await loadAll();
};

const saveSetting = async (s: any) => {
  const raw = String(s.value ?? '').trim();
  const parsed: any = raw !== '' && !Number.isNaN(Number(raw)) ? Number(raw) : raw;
  const reason = askReason(`Đổi cấu hình ${s.key}`);
  if (reason === undefined) return;
  const ok = await callRpc('admin_update_setting', { p_key: s.key, p_value: parsed, p_reason: reason });
  if (ok) showToast(`Đã lưu cấu hình ${s.key}`);
};
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4">
    <div class="flex flex-wrap gap-2">
      <button type="button" class="text-xs px-3.5 rounded-lg min-h-[44px] font-bold border cursor-pointer"
        :class="subTab === 'products' ? 'bg-[#0D2C54] text-white border-[#0D2C54]' : 'bg-white text-slate-700 border-slate-200'"
        @click="subTab = 'products'">Sản phẩm &amp; Tồn kho ({{ products.length }})</button>
      <button type="button" class="text-xs px-3.5 rounded-lg min-h-[44px] font-bold border cursor-pointer"
        :class="subTab === 'coupons' ? 'bg-[#0D2C54] text-white border-[#0D2C54]' : 'bg-white text-slate-700 border-slate-200'"
        @click="subTab = 'coupons'">Mã giảm giá ({{ coupons.length }})</button>
      <button type="button" class="text-xs px-3.5 rounded-lg min-h-[44px] font-bold border cursor-pointer"
        :class="subTab === 'rules' ? 'bg-[#0D2C54] text-white border-[#0D2C54]' : 'bg-white text-slate-700 border-slate-200'"
        @click="subTab = 'rules'">Quy tắc hoa hồng ({{ rules.length }})</button>
      <button type="button" class="text-xs px-3.5 rounded-lg min-h-[44px] font-bold border cursor-pointer"
        :class="subTab === 'settings' ? 'bg-[#0D2C54] text-white border-[#0D2C54]' : 'bg-white text-slate-700 border-slate-200'"
        @click="subTab = 'settings'">Cài đặt hệ thống</button>
    </div>

    <div v-if="loading" class="py-8 text-center text-sm text-slate-500">Đang tải dữ liệu...</div>

    <!-- Products -->
    <div v-else-if="subTab === 'products'" class="space-y-4">
      <p class="text-xs text-slate-500 m-0">
        Đây là <strong>bảng giá chuẩn trên server</strong> để hệ thống tự tính tiền đơn hàng (chống sửa giá ở trình
        duyệt). Bạn có thể sửa trực tiếp Tên / Giá / Tồn kho (để trống = không giới hạn) rồi bấm <strong>Lưu</strong>,
        hoặc thêm SKU mới ở thanh phía trên.
      </p>
      <form class="grid grid-cols-1 sm:grid-cols-5 gap-2.5 bg-slate-50 p-3.5 rounded-xl border border-slate-200"
        @submit.prevent="addProduct">
        <input v-model="newProduct.sku" type="text" required placeholder="SKU (vd: tpe-suv)"
          class="field-input text-xs">
        <input v-model="newProduct.name" type="text" required placeholder="Tên sản phẩm / chất liệu"
          class="field-input text-xs sm:col-span-2">
        <input v-model.number="newProduct.base_price" type="number" min="0" step="50000" required
          placeholder="Giá niêm yết" class="field-input text-xs tabular-nums">
        <button type="submit" class="btn-cta text-xs">
          <Plus class="w-4 h-4" /> Thêm SP
        </button>
      </form>

      <div class="overflow-x-auto">
        <table class="w-full text-left text-xs border-collapse min-w-[680px]">
          <thead class="bg-slate-50 border-b border-slate-200 text-[11px] uppercase text-slate-500">
            <tr>
              <th class="py-2.5 px-3">SKU</th>
              <th class="py-2.5 px-3">Tên sản phẩm</th>
              <th class="py-2.5 px-3">Giá (VNĐ)</th>
              <th class="py-2.5 px-3">Tồn kho</th>
              <th class="py-2.5 px-3">Đang bán</th>
              <th class="py-2.5 px-3">Lưu</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in products" :key="p.id" class="border-b border-slate-100">
              <td class="py-2 px-3 font-mono font-bold text-[#0D2C54]">{{ p.sku }}</td>
              <td class="py-2 px-3"><input v-model="p.name" type="text" class="field-input py-1 text-xs min-h-[38px]">
              </td>
              <td class="py-2 px-3"><input v-model.number="p.base_price" type="number" step="50000"
                  class="field-input py-1 text-xs w-32 tabular-nums min-h-[38px]"></td>
              <td class="py-2 px-3"><input v-model.number="p.stock_qty" type="number" min="0"
                  class="field-input py-1 text-xs w-20 tabular-nums min-h-[38px]"></td>
              <td class="py-2 px-3"><input v-model="p.is_active" type="checkbox" class="w-4 h-4 accent-[#0D2C54]"></td>
              <td class="py-2 px-3">
                <button type="button" class="btn-outline text-xs px-3 min-h-[38px]" @click="saveProduct(p)">
                  <Save class="w-3.5 h-3.5" /> Lưu
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Coupons -->
    <div v-else-if="subTab === 'coupons'" class="space-y-4">
      <form class="grid grid-cols-1 sm:grid-cols-6 gap-2.5 bg-slate-50 p-3.5 rounded-xl border border-slate-200"
        @submit.prevent="addCoupon">
        <input v-model="newCoupon.code" type="text" required placeholder="Mã (VD: SALE10)"
          class="field-input text-xs uppercase">
        <select v-model="newCoupon.discount_type" class="field-input text-xs">
          <option value="percent">Giảm %</option>
          <option value="fixed">Giảm VNĐ</option>
        </select>
        <input v-model.number="newCoupon.discount_value" type="number" min="1" required placeholder="Giá trị"
          class="field-input text-xs tabular-nums">
        <input v-model.number="newCoupon.min_order_amount" type="number" min="0" placeholder="Đơn tối thiểu"
          class="field-input text-xs tabular-nums">
        <input v-model.number="newCoupon.max_discount_amount" type="number" min="0" placeholder="Giảm tối đa"
          class="field-input text-xs tabular-nums">
        <button type="submit" class="btn-cta text-xs">
          <Plus class="w-4 h-4" /> Tạo mã
        </button>
      </form>

      <div class="overflow-x-auto">
        <table class="w-full text-left text-xs border-collapse min-w-[600px]">
          <thead class="bg-slate-50 border-b border-slate-200 text-[11px] uppercase text-slate-500">
            <tr>
              <th class="py-2.5 px-3">Mã giảm giá</th>
              <th class="py-2.5 px-3">Mức giảm</th>
              <th class="py-2.5 px-3">Đơn tối thiểu</th>
              <th class="py-2.5 px-3">Đã dùng</th>
              <th class="py-2.5 px-3">Trạng thái</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in coupons" :key="c.id" class="border-b border-slate-100">
              <td class="py-2.5 px-3 font-mono font-extrabold text-[#0D2C54]">{{ c.code }}</td>
              <td class="py-2.5 px-3 font-bold text-[#15803D] tabular-nums">
                {{ c.discount_type === 'percent' ? `${c.discount_value}%` : formatCurrency(c.discount_value) }}
              </td>
              <td class="py-2.5 px-3 tabular-nums">{{ formatCurrency(c.min_order_amount || 0) }}</td>
              <td class="py-2.5 px-3 tabular-nums">{{ c.used_count || 0 }} / {{ c.usage_limit || '∞' }}</td>
              <td class="py-2.5 px-3">
                <button type="button" class="btn-outline text-xs px-3 min-h-[36px]" @click="toggleCoupon(c)">
                  {{ c.is_active ? 'Đang bật (Tắt)' : 'Đang tắt (Bật)' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Commission Rules -->
    <div v-else-if="subTab === 'rules'" class="space-y-4">
      <form class="grid grid-cols-1 sm:grid-cols-3 gap-2.5 bg-slate-50 p-3.5 rounded-xl border border-slate-200"
        @submit.prevent="addRule">
        <select v-model="newRule.product_id" class="field-input text-xs">
          <option value="">Tất cả sản phẩm</option>
          <option v-for="p in products" :key="p.id" :value="p.id">{{ p.name }} ({{ p.sku }})</option>
        </select>
        <input v-model.number="newRule.rate" type="number" min="0" max="50" step="0.5" required
          placeholder="Tỷ lệ HH (%)" class="field-input text-xs tabular-nums">
        <button type="submit" class="btn-cta text-xs">
          <Plus class="w-4 h-4" /> Thêm quy tắc
        </button>
      </form>

      <div v-if="!rules.length" class="py-6 text-center text-xs text-slate-500">Chưa có quy tắc riêng. Hệ thống đang
        dùng % mặc định theo từng CTV.</div>
      <div v-else class="overflow-x-auto">
        <table class="w-full text-left text-xs border-collapse min-w-[520px]">
          <thead class="bg-slate-50 border-b border-slate-200 text-[11px] uppercase text-slate-500">
            <tr>
              <th class="py-2.5 px-3">Sản phẩm áp dụng</th>
              <th class="py-2.5 px-3">Tỷ lệ HH</th>
              <th class="py-2.5 px-3">Trạng thái</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in rules" :key="r.id" class="border-b border-slate-100"
              :class="{ 'opacity-60': !r.is_active }">
              <td class="py-2.5 px-3">{{products.find(p => p.id === r.product_id)?.name || 'Tất cả sản phẩm'}}</td>
              <td class="py-2.5 px-3 font-bold text-[#15803D] tabular-nums">{{ r.rate }}%</td>
              <td class="py-2.5 px-3">
                <button type="button" class="btn-outline text-xs px-3 min-h-[36px]" @click="toggleRule(r)">
                  {{ r.is_active ? 'Đang bật (Vô hiệu hóa)' : 'Đang tắt (Bật lại)' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- App Settings -->
    <div v-else class="space-y-3">
      <p class="text-xs text-slate-500 m-0">Cấu hình chung của hệ thống đối soát &amp; hoa hồng (lưu trong bảng
        <code>app_settings</code>).</p>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div v-for="s in appSettings" :key="s.key"
          class="border border-slate-200 rounded-xl p-3.5 flex items-center justify-between gap-3">
          <div class="min-w-0">
            <p class="font-mono text-xs font-bold text-[#0D2C54] m-0">{{ s.key }}</p>
            <p class="text-[11px] text-slate-500 m-0 mt-0.5">{{ s.description || '' }}</p>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <input v-model="s.value" type="text" class="field-input py-1 text-xs w-28 tabular-nums min-h-[38px]">
            <button type="button" class="btn-outline text-xs px-3 min-h-[38px]" @click="saveSetting(s)">Lưu</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
