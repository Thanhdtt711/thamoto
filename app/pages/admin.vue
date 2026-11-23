<script setup lang="ts">
import { ShieldCheck, Lock, UserCheck, UserPlus, RefreshCw, X } from 'lucide-vue-next';

useSeoMeta({
  title: 'Trang Quản Trị Hệ Thống (Admin Portal) | Trung Thành Auto',
  robots: 'noindex, nofollow'
});

const { supabase, isConfigured, createEphemeralClient } = useSupabase();
const { showToast } = useToast();

const viewState = ref<'loading' | 'login' | 'forbidden' | 'dashboard'>('loading');
const loginEmail = ref('');
const loginPassword = ref('');
const loginError = ref('');
const isLoggingIn = ref(false);

const currentAdmin = ref<any>(null);
const allOrders = ref<any[]>([]);
const allAffiliates = ref<any[]>([]);
const allLeads = ref<any[]>([]);
const allPayouts = ref<any[]>([]);

const activeTab = ref<'orders' | 'affiliates' | 'settlement' | 'leads'>('orders');
const orderSearch = ref('');
const sourceFilter = ref('');
const orderStatusFilter = ref('');
const ctvStatusFilter = ref('');

// Create account modal (develop only)
const showCreateModal = ref(false);
const createErr = ref('');
const isCreating = ref(false);
const newAcc = reactive({
  role: 'admin',
  rate: 10,
  name: '',
  phone: '',
  code: '',
  email: '',
  password: ''
});

const STATUS_LABELS: Record<string, string> = {
  new: 'Mới',
  confirmed: 'Đã xác nhận',
  shipping: 'Đang giao',
  completed: 'Hoàn thành',
  cancelled: 'Đã hủy'
};

const STATUS_BADGE: Record<string, string> = {
  new: 'bg-sky-50 text-sky-700 border-sky-200',
  confirmed: 'bg-[#EFF4FA] text-[#0D2C54] border-[#0D2C54]/20',
  shipping: 'bg-amber-50 text-amber-700 border-amber-200',
  completed: 'bg-green-50 text-[#15803D] border-green-200',
  cancelled: 'bg-[#FEF2F2] text-[#C81E2B] border-[#C81E2B]/25'
};

const CTV_STATUS_LABELS: Record<string, string> = {
  pending: 'Chờ duyệt',
  active: 'Đang hoạt động',
  suspended: 'Tạm khóa',
  cancelled: 'Đã hủy'
};

const CTV_STATUS_BADGE: Record<string, string> = {
  pending: 'bg-amber-50 text-amber-700 border-amber-200',
  active: 'bg-green-50 text-[#15803D] border-green-200',
  suspended: 'bg-slate-100 text-slate-700 border-slate-300',
  cancelled: 'bg-[#FEF2F2] text-[#C81E2B] border-[#C81E2B]/25'
};

const COMM_LABELS: Record<string, string> = {
  pending: 'Chờ duyệt',
  approved: 'Đã duyệt',
  paid: 'Đã trả'
};

const isDevelop = computed(() => currentAdmin.value?.role === 'develop');

const formatDate = (iso: string) =>
  iso ? new Date(iso).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';

const kpis = computed(() => {
  const direct = allOrders.value.filter((o) => !o.affiliate_code).length;
  const ctv = allOrders.value.length - direct;
  const valid = allOrders.value.filter((o) => o.status !== 'cancelled');
  const revenue = valid.reduce((s, o) => s + Number(o.total_amount || 0), 0);
  const ctvOnly = allAffiliates.value.filter((a) => a.role === 'ctv');
  const activeCtv = ctvOnly.filter((a) => a.status === 'active').length;
  const pendingCtv = ctvOnly.filter((a) => a.status === 'pending').length;
  const commDue = valid.filter((o) => o.affiliate_code && o.commission_status !== 'paid').reduce((s, o) => s + Number(o.commission_amount || 0), 0);
  const commPaid = valid.filter((o) => o.affiliate_code && o.commission_status === 'paid').reduce((s, o) => s + Number(o.commission_amount || 0), 0);
  return { totalOrders: allOrders.value.length, direct, ctv, revenue, activeCtv, pendingCtv, commDue, commPaid };
});

const filteredOrders = computed(() => {
  const q = orderSearch.value.trim().toLowerCase();
  return allOrders.value.filter((o) => {
    if (sourceFilter.value === 'direct' && o.affiliate_code) return false;
    if (sourceFilter.value === 'ctv' && !o.affiliate_code) return false;
    if (orderStatusFilter.value && o.status !== orderStatusFilter.value) return false;
    if (q) {
      const hay = `${o.order_code} ${o.customer_name} ${o.phone} ${o.affiliate_code || ''} ${o.items_summary}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  });
});

const filteredAffiliates = computed(() =>
  ctvStatusFilter.value ? allAffiliates.value.filter((a) => a.status === ctvStatusFilter.value) : allAffiliates.value
);

const affiliateStats = (code: string) => {
  const target = String(code || '').toUpperCase();
  const list = allOrders.value.filter((o) => String(o.affiliate_code || '').toUpperCase() === target && o.status !== 'cancelled');
  return {
    count: list.length,
    rev: list.reduce((s, o) => s + Number(o.total_amount || 0), 0)
  };
};

const settlementRows = computed(() => {
  const map = new Map<string, any>();
  allAffiliates.value.forEach((a) => {
    const code = String(a.code || '').toUpperCase();
    map.set(code, { code, name: a.full_name, phone: a.phone, completedPending: [], approved: [], paidAmt: 0 });
  });
  allOrders.value.forEach((o) => {
    if (!o.affiliate_code || o.status === 'cancelled') return;
    const code = String(o.affiliate_code).toUpperCase();
    if (!map.has(code)) {
      map.set(code, { code, name: code, phone: '', completedPending: [], approved: [], paidAmt: 0 });
    }
    const row = map.get(code);
    if (o.commission_status === 'paid') row.paidAmt += Number(o.commission_amount || 0);
    else if (o.commission_status === 'approved') row.approved.push(o);
    else if (o.status === 'completed' && o.commission_status === 'pending') row.completedPending.push(o);
  });
  return Array.from(map.values())
    .map((r) => ({
      ...r,
      pendingAmt: r.completedPending.reduce((s: number, o: any) => s + Number(o.commission_amount || 0), 0),
      approvedAmt: r.approved.reduce((s: number, o: any) => s + Number(o.commission_amount || 0), 0)
    }))
    .filter((r) => r.completedPending.length > 0 || r.approved.length > 0 || r.paidAmt > 0);
});

const loadAllData = async () => {
  if (!supabase) return;
  const [{ data: orders }, { data: affiliates }, { data: leads }, { data: payouts }] = await Promise.all([
    supabase.from('orders').select('*').order('created_at', { ascending: false }).limit(300),
    supabase.from('affiliates').select('*').order('created_at', { ascending: false }),
    supabase.from('leads').select('*').order('created_at', { ascending: false }).limit(150),
    supabase.from('commission_payouts').select('*').order('paid_at', { ascending: false }).limit(150)
  ]);
  allOrders.value = orders || [];
  allAffiliates.value = affiliates || [];
  allLeads.value = leads || [];
  allPayouts.value = payouts || [];
};

const updateOrderStatus = async (order: any, nextStatus: string) => {
  if (!supabase) return;
  const { error } = await supabase.from('orders').update({ status: nextStatus }).eq('id', order.id);
  if (error) showToast(`Lỗi cập nhật đơn #${order.order_code}`, 'error');
  else {
    showToast(`Đã cập nhật đơn #${order.order_code} → ${STATUS_LABELS[nextStatus]}`);
    await loadAllData();
  }
};

const updateAffiliateStatus = async (aff: any, nextStatus: string) => {
  if (!supabase) return;
  const { error } = await supabase.from('affiliates').update({ status: nextStatus }).eq('id', aff.id);
  if (error) showToast(`Lỗi cập nhật trạng thái ${aff.code}`, 'error');
  else {
    showToast(`Đã đổi trạng thái ${aff.code} → ${CTV_STATUS_LABELS[nextStatus]}`);
    await loadAllData();
  }
};

const updateAffiliateRate = async (aff: any, rawRate: string) => {
  if (!supabase) return;
  const rate = Math.max(0, Math.min(50, Number(rawRate) || 0));
  const { error } = await supabase.from('affiliates').update({ commission_rate: rate }).eq('id', aff.id);
  if (error) showToast(`Lỗi cập nhật hoa hồng ${aff.code}`, 'error');
  else {
    showToast(`Đã cập nhật hoa hồng ${aff.code} → ${rate}%`);
    await loadAllData();
  }
};

const updateAffiliateRole = async (aff: any, nextRole: string) => {
  if (!supabase) return;
  const { error } = await supabase.rpc('develop_set_account_role', {
    p_email: aff.email,
    p_role: nextRole,
    p_status: 'active'
  });
  if (error) showToast(`Lỗi đổi vai trò ${aff.code}: ${error.message}`, 'error');
  else {
    showToast(`Đã đổi vai trò ${aff.code} → ${nextRole.toUpperCase()}`);
    await loadAllData();
  }
};

const approveCommission = async (row: any) => {
  if (!supabase || row.completedPending.length === 0) return;
  const ids = row.completedPending.map((o: any) => o.id);
  const { error } = await supabase.from('orders').update({ commission_status: 'approved' }).in('id', ids);
  if (error) showToast(`Lỗi duyệt hoa hồng ${row.code}`, 'error');
  else {
    showToast(`Đã duyệt hoa hồng ${ids.length} đơn cho ${row.code}`);
    await loadAllData();
  }
};

const payCommission = async (row: any) => {
  if (!supabase || row.approved.length === 0 || !import.meta.client) return;
  const note = window.prompt(
    `Nhập ghi chú / mã giao dịch chuyển khoản ${formatCurrency(row.approvedAmt)} cho ${row.code}:`,
    `CK hoa hồng ${row.code} (${row.approved.length} đơn)`
  );
  if (note === null) return;
  const ids = row.approved.map((o: any) => o.id);
  const { error: upErr } = await supabase.from('orders').update({ commission_status: 'paid' }).in('id', ids);
  const { error: insErr } = await supabase.from('commission_payouts').insert({
    affiliate_code: row.code,
    amount: row.approvedAmt,
    order_count: row.approved.length,
    note: note.trim() || `Thanh toán hoa hồng ${row.code}`,
    created_by: currentAdmin.value?.user_id || null
  });
  if (upErr || insErr) showToast(`Lỗi ghi nhận thanh toán cho ${row.code}`, 'error');
  else {
    showToast(`Đã thanh toán ${formatCurrency(row.approvedAmt)} cho ${row.code}`);
    await loadAllData();
  }
};

const updateLeadStatus = async (lead: any, nextStatus: string) => {
  if (!supabase) return;
  const { error } = await supabase.from('leads').update({ status: nextStatus }).eq('id', lead.id);
  if (error) showToast('Lỗi cập nhật trạng thái tư vấn', 'error');
  else showToast('Đã cập nhật trạng thái yêu cầu tư vấn');
};

const handleCreateAccount = async () => {
  createErr.value = '';
  const tempClient = createEphemeralClient();
  if (!supabase || !tempClient) return;
  isCreating.value = true;
  try {
    const cleanEmail = newAcc.email.trim().toLowerCase();
    const cleanCode = newAcc.code.trim().toUpperCase().replace(/[^A-Z0-9_-]/g, '');
    const { error: signUpErr } = await tempClient.auth.signUp({
      email: cleanEmail,
      password: newAcc.password,
      options: {
        data: {
          full_name: newAcc.name.trim(),
          phone: newAcc.phone.replace(/\s+/g, ''),
          code: cleanCode,
          job_type: newAcc.role === 'admin' ? 'Quản trị viên' : 'Cộng tác viên'
        }
      }
    });
    if (signUpErr) throw signUpErr;

    const { error: rpcErr } = await supabase.rpc('develop_set_account_role', {
      p_email: cleanEmail,
      p_role: newAcc.role,
      p_status: 'active',
      p_commission_rate: Number(newAcc.rate) || 10
    });
    if (rpcErr) throw rpcErr;

    showCreateModal.value = false;
    Object.assign(newAcc, { role: 'admin', rate: 10, name: '', phone: '', code: '', email: '', password: '' });
    showToast(`Đã tạo tài khoản ${newAcc.role.toUpperCase()} (${cleanEmail}) thành công!`);
    await loadAllData();
  } catch (err: any) {
    createErr.value = err?.message || 'Không thể tạo tài khoản.';
  } finally {
    isCreating.value = false;
  }
};

const checkAdminSession = async () => {
  if (!isConfigured || !supabase) {
    viewState.value = 'login';
    return;
  }
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    viewState.value = 'login';
    return;
  }
  const { data: prof } = await supabase.from('affiliates').select('*').eq('user_id', session.user.id).maybeSingle();
  if (!prof || !['admin', 'develop'].includes(prof.role) || prof.status !== 'active') {
    viewState.value = 'forbidden';
    return;
  }
  currentAdmin.value = prof;
  viewState.value = 'dashboard';
  await loadAllData();
};

const handleLogin = async () => {
  loginError.value = '';
  if (!supabase) return;
  isLoggingIn.value = true;
  try {
    const { error } = await supabase.auth.signInWithPassword({
      email: loginEmail.value.trim(),
      password: loginPassword.value
    });
    if (error) throw error;
    await checkAdminSession();
  } catch (err: any) {
    loginError.value = err?.message === 'Invalid login credentials' ? 'Email hoặc mật khẩu không đúng.' : (err?.message || 'Đăng nhập thất bại.');
  } finally {
    isLoggingIn.value = false;
  }
};

const handleLogout = async () => {
  if (supabase) await supabase.auth.signOut();
  currentAdmin.value = null;
  viewState.value = 'login';
};

onMounted(() => {
  checkAdminSession();
});
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-5">
    <div v-if="viewState === 'loading'" class="card-surface p-8 text-center text-xs text-slate-500">
      Đang kiểm tra quyền quản trị...
    </div>

    <!-- Login -->
    <section v-else-if="viewState === 'login'" class="max-w-md mx-auto card-surface p-6 space-y-4">
      <div class="text-center space-y-1.5">
        <div class="w-12 h-12 rounded-2xl bg-[#0D2C54] text-white flex items-center justify-center mx-auto">
          <ShieldCheck class="w-6 h-6" />
        </div>
        <h1 class="text-lg font-bold uppercase text-[#0D2C54] m-0">Đăng Nhập Quản Trị</h1>
        <p class="text-xs text-slate-500 m-0">Dành riêng cho Admin &amp; Develop quản lý toàn bộ hệ thống</p>
      </div>

      <p v-if="loginError" role="alert" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3.5 py-2.5 m-0">
        {{ loginError }}
      </p>

      <form class="space-y-3.5" @submit.prevent="handleLogin">
        <div class="space-y-1">
          <label for="admin-email" class="text-xs font-semibold text-slate-700 block">Email quản trị</label>
          <input id="admin-email" v-model="loginEmail" type="email" required placeholder="admin@domain.com" class="field-input">
        </div>
        <div class="space-y-1">
          <label for="admin-password" class="text-xs font-semibold text-slate-700 block">Mật khẩu</label>
          <input id="admin-password" v-model="loginPassword" type="password" required placeholder="Nhập mật khẩu..." class="field-input">
        </div>
        <button type="submit" :disabled="isLoggingIn" class="btn-cta w-full text-xs">
          {{ isLoggingIn ? 'ĐANG ĐĂNG NHẬP...' : 'ĐĂNG NHẬP QUẢN TRỊ' }}
        </button>
      </form>

      <p class="text-xs text-slate-600 text-center m-0 pt-2 border-t border-slate-100">
        Bạn là Cộng tác viên? <NuxtLink to="/ctv" class="font-semibold text-[#0D2C54] underline">Vào Cổng CTV →</NuxtLink>
      </p>
    </section>

    <!-- Forbidden -->
    <section v-else-if="viewState === 'forbidden'" class="max-w-lg mx-auto card-surface p-6 text-center space-y-4">
      <div class="w-14 h-14 rounded-full bg-[#FEF2F2] border border-[#C81E2B]/30 text-[#C81E2B] flex items-center justify-center mx-auto">
        <Lock class="w-7 h-7" />
      </div>
      <h2 class="text-lg font-bold text-[#0D2C54] m-0">Không có quyền truy cập trang Admin</h2>
      <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
        Tài khoản hiện tại không có quyền quản trị hệ thống. Vui lòng sử dụng <strong>Cổng CTV</strong>.
      </p>
      <div class="flex flex-wrap justify-center gap-3">
        <NuxtLink to="/ctv" class="btn-cta text-xs px-5">VÀO CỔNG CTV</NuxtLink>
        <button type="button" class="btn-outline text-xs px-5" @click="handleLogout">Đăng xuất</button>
      </div>
    </section>

    <!-- Dashboard -->
    <section v-else class="space-y-5">
      <div class="card-surface p-4 sm:p-5 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
        <div class="space-y-1 min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h1 class="text-base sm:text-lg font-bold text-[#0D2C54] m-0">QUẢN TRỊ HỆ THỐNG</h1>
            <span class="text-[11px] font-bold uppercase px-2.5 py-0.5 rounded-full bg-[#0D2C54] text-white whitespace-nowrap">
              {{ isDevelop ? 'DEVELOP · TOÀN QUYỀN' : 'ADMIN PORTAL' }}
            </span>
          </div>
          <p class="text-xs text-slate-500 m-0 truncate">{{ currentAdmin?.full_name }} ({{ currentAdmin?.email }})</p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <NuxtLink
            v-if="isDevelop"
            to="/ctv"
            class="inline-flex items-center justify-center gap-1.5 min-h-[44px] lg:min-h-[40px] px-3.5 rounded-lg bg-[#EFF4FA] hover:bg-slate-200 text-[#0D2C54] text-xs font-semibold no-underline transition whitespace-nowrap shrink-0"
          >
            <UserCheck class="w-3.5 h-3.5" /> Xem Cổng CTV
          </NuxtLink>
          <button
            v-if="isDevelop"
            type="button"
            class="inline-flex items-center justify-center gap-1.5 min-h-[44px] lg:min-h-[40px] px-3.5 rounded-lg bg-[#0D2C54] hover:bg-[#133A6E] text-white text-xs font-semibold cursor-pointer transition whitespace-nowrap shrink-0"
            @click="showCreateModal = true"
          >
            <UserPlus class="w-3.5 h-3.5" /> Tạo tài khoản
          </button>
          <button type="button" class="btn-outline text-xs px-3.5 min-h-[44px] lg:min-h-[40px] whitespace-nowrap shrink-0" @click="loadAllData().then(() => showToast('Đã làm mới dữ liệu hệ thống'))">
            <RefreshCw class="w-3.5 h-3.5" /> Tải lại
          </button>
          <button type="button" class="btn-outline text-xs px-3.5 min-h-[44px] lg:min-h-[40px] text-[#C81E2B] border-[#C81E2B]/30 whitespace-nowrap shrink-0" @click="handleLogout">
            Đăng xuất
          </button>
        </div>
      </div>

      <!-- KPIs -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Tổng đơn hệ thống</span>
          <span class="text-xl sm:text-2xl font-bold text-[#0D2C54] tabular-nums block">{{ kpis.totalOrders }}</span>
          <span class="text-[11px] text-slate-500 block tabular-nums">{{ kpis.direct }} lẻ · {{ kpis.ctv }} CTV</span>
        </div>
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Tổng doanh số</span>
          <span class="text-xl sm:text-2xl font-bold text-[#15803D] tabular-nums block">{{ formatCurrency(kpis.revenue) }}</span>
          <span class="text-[11px] text-slate-500 block">Đã trừ đơn hủy</span>
        </div>
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Cộng tác viên</span>
          <span class="text-xl sm:text-2xl font-bold text-[#0D2C54] tabular-nums block">{{ kpis.activeCtv }}</span>
          <span class="text-[11px] text-[#C81E2B] font-semibold block tabular-nums">{{ kpis.pendingCtv }} chờ duyệt</span>
        </div>
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Hoa hồng chờ trả</span>
          <span class="text-xl sm:text-2xl font-bold text-[#0D2C54] tabular-nums block">{{ formatCurrency(kpis.commDue) }}</span>
          <span class="text-[11px] text-[#15803D] font-semibold block tabular-nums">Đã trả: {{ formatCurrency(kpis.commPaid) }}</span>
        </div>
      </div>

      <!-- Tabs -->
      <div class="flex gap-2 overflow-x-auto no-scrollbar pb-1 border-b border-slate-200">
        <button
          v-for="tab in [
            { key: 'orders', label: '1. Quản lý đơn hàng' },
            { key: 'affiliates', label: '2. Quản lý CTV' },
            { key: 'settlement', label: '3. Đối soát & Thanh toán' },
            { key: 'leads', label: '4. Yêu cầu tư vấn' }
          ]"
          :key="tab.key"
          type="button"
          class="min-h-[42px] px-4 py-2 rounded-lg text-xs font-semibold cursor-pointer whitespace-nowrap shrink-0"
          :class="activeTab === tab.key ? 'bg-[#0D2C54] text-white' : 'bg-white text-slate-700 border border-slate-200'"
          @click="activeTab = tab.key as any"
        >
          {{ tab.label }}
        </button>
      </div>

      <!-- TAB 1: Orders -->
      <div v-if="activeTab === 'orders'" class="card-surface p-4 sm:p-5 space-y-4">
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <input v-model="orderSearch" type="search" placeholder="Tìm mã đơn, tên khách, SĐT, mã CTV..." class="field-input text-xs">
          <select v-model="sourceFilter" class="ymm-select text-xs">
            <option value="">Tất cả nguồn đơn (Lẻ + CTV)</option>
            <option value="direct">Chỉ đơn khách lẻ</option>
            <option value="ctv">Chỉ đơn qua CTV</option>
          </select>
          <select v-model="orderStatusFilter" class="ymm-select text-xs">
            <option value="">Tất cả trạng thái đơn</option>
            <option v-for="(label, key) in STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
          </select>
        </div>

        <p v-if="filteredOrders.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">Không có đơn hàng phù hợp bộ lọc.</p>
        <template v-else>
          <div class="hidden lg:block overflow-x-auto">
            <table class="w-full text-left border-collapse text-xs">
              <thead>
                <tr class="border-b border-slate-200 text-slate-500 uppercase text-[11px]">
                  <th class="py-2.5 pr-4 whitespace-nowrap">Mã đơn</th>
                  <th class="py-2.5 pr-4 whitespace-nowrap">Khách hàng &amp; Địa chỉ</th>
                  <th class="py-2.5 pr-4">Sản phẩm &amp; Xe</th>
                  <th class="py-2.5 pr-4 whitespace-nowrap">Tổng tiền</th>
                  <th class="py-2.5 pr-4 whitespace-nowrap">Nguồn / CTV</th>
                  <th class="py-2.5 whitespace-nowrap">Xử lý đơn</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100">
                <tr v-for="o in filteredOrders" :key="o.id" class="align-top">
                  <td class="py-3.5 pr-4 whitespace-nowrap">
                    <strong class="text-[#0D2C54] tabular-nums block">#{{ o.order_code }}</strong>
                    <span class="text-[11px] text-slate-500 tabular-nums">{{ formatDate(o.created_at) }}</span>
                  </td>
                  <td class="py-3.5 pr-4 min-w-[170px]">
                    <strong class="text-slate-900 block">{{ o.customer_name }}</strong>
                    <a :href="`tel:${o.phone}`" class="text-[#0D2C54] font-semibold tabular-nums no-underline hover:underline block">{{ o.phone }}</a>
                    <span class="text-[11px] text-slate-500 block">{{ o.address }}</span>
                  </td>
                  <td class="py-3.5 pr-4 max-w-xs">
                    <p class="m-0 text-slate-700 whitespace-pre-line leading-snug">{{ o.items_summary }}</p>
                    <span class="inline-block mt-1 px-2 py-0.5 rounded bg-slate-100 text-slate-600 text-[10px] font-semibold">{{ o.payment_method }}</span>
                  </td>
                  <td class="py-3.5 pr-4 whitespace-nowrap font-bold text-[#15803D] tabular-nums">{{ formatCurrency(o.total_amount) }}</td>
                  <td class="py-3.5 pr-4 whitespace-nowrap">
                    <template v-if="o.affiliate_code">
                      <span class="inline-block px-2 py-0.5 rounded bg-[#FEF2F2] text-[#C81E2B] font-semibold text-[11px]">{{ o.affiliate_code }}</span>
                      <span class="block text-[#15803D] font-semibold tabular-nums mt-0.5">{{ formatCurrency(o.commission_amount) }} ({{ COMM_LABELS[o.commission_status] }})</span>
                    </template>
                    <span v-else class="inline-block px-2 py-0.5 rounded bg-slate-100 text-slate-600 text-[11px]">Khách lẻ</span>
                  </td>
                  <td class="py-3.5 whitespace-nowrap">
                    <select :value="o.status" class="min-h-[38px] w-36 border border-slate-300 rounded-lg px-2.5 text-xs font-semibold bg-white text-[#0D2C54]" @change="updateOrderStatus(o, ($event.target as HTMLSelectElement).value)">
                      <option v-for="(label, key) in STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
                    </select>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="lg:hidden space-y-3">
            <div v-for="o in filteredOrders" :key="o.id" class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-4 space-y-3 text-xs">
              <div class="flex items-start justify-between gap-2">
                <div>
                  <strong class="text-sm text-[#0D2C54] tabular-nums block">#{{ o.order_code }}</strong>
                  <span class="text-[11px] text-slate-500 tabular-nums">{{ formatDate(o.created_at) }}</span>
                </div>
                <span class="px-2.5 py-1 rounded-full border text-[11px] font-semibold whitespace-nowrap" :class="STATUS_BADGE[o.status]">{{ STATUS_LABELS[o.status] }}</span>
              </div>
              <div class="bg-white rounded-lg p-3 border border-slate-200/80 space-y-1">
                <div class="flex justify-between gap-2">
                  <strong class="text-slate-900">{{ o.customer_name }}</strong>
                  <a :href="`tel:${o.phone}`" class="text-[#0D2C54] font-bold tabular-nums no-underline">{{ o.phone }}</a>
                </div>
                <p class="text-[11px] text-slate-500 m-0">{{ o.address }}</p>
              </div>
              <p class="m-0 text-slate-700 whitespace-pre-line leading-relaxed">{{ o.items_summary }}</p>
              <div class="flex items-center justify-between gap-2 pt-2 border-t border-slate-200">
                <div>
                  <span class="text-[11px] text-slate-500 block">{{ o.payment_method }} · {{ o.affiliate_code ? `CTV ${o.affiliate_code}` : 'Khách lẻ' }}</span>
                  <strong class="text-base text-[#15803D] tabular-nums">{{ formatCurrency(o.total_amount) }}</strong>
                </div>
                <select :value="o.status" class="min-h-[44px] w-40 border border-slate-300 rounded-lg px-3 text-xs font-semibold bg-white text-[#0D2C54]" @change="updateOrderStatus(o, ($event.target as HTMLSelectElement).value)">
                  <option v-for="(label, key) in STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
                </select>
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- TAB 2: Affiliates -->
      <div v-else-if="activeTab === 'affiliates'" class="card-surface p-4 sm:p-5 space-y-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Danh sách Cộng tác viên &amp; Tài khoản</h2>
            <p class="text-xs text-slate-500 mt-0.5 m-0">Duyệt, tạm khóa, hủy CTV và cấu hình mức hoa hồng riêng.</p>
          </div>
          <select v-model="ctvStatusFilter" class="ymm-select text-xs sm:w-52">
            <option value="">Tất cả trạng thái</option>
            <option v-for="(label, key) in CTV_STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
          </select>
        </div>

        <div class="hidden lg:block overflow-x-auto">
          <table class="w-full text-left border-collapse text-xs">
            <thead>
              <tr class="border-b border-slate-200 text-slate-500 uppercase text-[11px]">
                <th class="py-2.5 pr-4 whitespace-nowrap">Mã &amp; Vai trò</th>
                <th class="py-2.5 pr-4 whitespace-nowrap">Họ tên &amp; Liên hệ</th>
                <th class="py-2.5 pr-4 whitespace-nowrap">Nghề / Khu vực</th>
                <th class="py-2.5 pr-4 whitespace-nowrap">Hiệu suất</th>
                <th class="py-2.5 pr-4 whitespace-nowrap">Hoa hồng (%)</th>
                <th class="py-2.5 whitespace-nowrap">Trạng thái</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="a in filteredAffiliates" :key="a.id" class="align-top">
                <td class="py-3.5 pr-4 whitespace-nowrap">
                  <strong class="text-[#0D2C54] block">{{ a.code }}</strong>
                  <select
                    v-if="isDevelop && a.id !== currentAdmin?.id"
                    :value="a.role"
                    class="mt-1 border border-slate-300 rounded px-2 py-1 text-[11px] font-semibold bg-white text-[#0D2C54]"
                    @change="updateAffiliateRole(a, ($event.target as HTMLSelectElement).value)"
                  >
                    <option value="ctv">CTV</option>
                    <option value="admin">ADMIN</option>
                    <option value="develop">DEVELOP</option>
                  </select>
                  <span v-else class="inline-block mt-1 text-[10px] font-bold uppercase px-2 py-0.5 rounded" :class="a.role === 'develop' ? 'bg-[#C81E2B] text-white' : (a.role === 'admin' ? 'bg-[#0D2C54] text-white' : 'bg-slate-100 text-slate-600')">
                    {{ a.role }}
                  </span>
                </td>
                <td class="py-3.5 pr-4">
                  <strong class="text-slate-900 block">{{ a.full_name }}</strong>
                  <a :href="`tel:${a.phone}`" class="text-[#0D2C54] font-semibold tabular-nums no-underline block">{{ a.phone }}</a>
                  <span class="text-[11px] text-slate-500 block">{{ a.email }}</span>
                </td>
                <td class="py-3.5 pr-4 whitespace-nowrap">
                  <span class="block">{{ a.job_type || '—' }}</span>
                  <span class="text-[11px] text-slate-500">{{ a.area || '—' }}</span>
                </td>
                <td class="py-3.5 pr-4 whitespace-nowrap tabular-nums">
                  <strong class="text-[#0D2C54] block">{{ affiliateStats(a.code).count }} đơn</strong>
                  <span class="text-[11px] text-[#15803D] font-semibold">{{ formatCurrency(affiliateStats(a.code).rev) }}</span>
                </td>
                <td class="py-3.5 pr-4 whitespace-nowrap">
                  <input :value="a.commission_rate" type="number" min="0" max="50" step="0.5" class="w-20 min-h-[38px] border border-slate-300 rounded-lg px-2 text-xs font-semibold tabular-nums" @change="updateAffiliateRate(a, ($event.target as HTMLInputElement).value)"> %
                </td>
                <td class="py-3.5 whitespace-nowrap">
                  <select :value="a.status" :disabled="a.id === currentAdmin?.id" class="min-h-[38px] w-36 border border-slate-300 rounded-lg px-2.5 text-xs font-semibold bg-white" @change="updateAffiliateStatus(a, ($event.target as HTMLSelectElement).value)">
                    <option v-for="(label, key) in CTV_STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
                  </select>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="lg:hidden space-y-3">
          <div v-for="a in filteredAffiliates" :key="a.id" class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-4 space-y-3 text-xs">
            <div class="flex items-start justify-between gap-2">
              <div>
                <strong class="text-sm text-[#0D2C54] block">{{ a.full_name }}</strong>
                <span class="text-[11px] font-semibold text-slate-600">{{ a.code }} · {{ a.job_type || '—' }}</span>
              </div>
              <span class="px-2.5 py-1 rounded-full border text-[11px] font-semibold whitespace-nowrap" :class="CTV_STATUS_BADGE[a.status]">{{ CTV_STATUS_LABELS[a.status] }}</span>
            </div>
            <div class="bg-white rounded-lg p-3 border border-slate-200/80 space-y-1">
              <div class="flex justify-between">
                <a :href="`tel:${a.phone}`" class="font-bold text-[#0D2C54] tabular-nums no-underline">{{ a.phone }}</a>
                <span class="text-slate-500">{{ a.area || '—' }}</span>
              </div>
              <p class="text-[11px] text-slate-500 m-0 truncate">{{ a.email }}</p>
              <p class="text-[11px] text-[#15803D] font-semibold m-0 tabular-nums">{{ affiliateStats(a.code).count }} đơn · {{ formatCurrency(affiliateStats(a.code).rev) }}</p>
            </div>
            <div class="grid grid-cols-2 gap-2.5">
              <div>
                <label class="text-[10px] text-slate-500 block mb-1">Hoa hồng (%)</label>
                <input :value="a.commission_rate" type="number" min="0" max="50" step="0.5" class="w-full min-h-[44px] border border-slate-300 rounded-lg px-3 text-xs font-semibold tabular-nums bg-white" @change="updateAffiliateRate(a, ($event.target as HTMLInputElement).value)">
              </div>
              <div>
                <label class="text-[10px] text-slate-500 block mb-1">Trạng thái</label>
                <select :value="a.status" :disabled="a.id === currentAdmin?.id" class="w-full min-h-[44px] border border-slate-300 rounded-lg px-2.5 text-xs font-semibold bg-white" @change="updateAffiliateStatus(a, ($event.target as HTMLSelectElement).value)">
                  <option v-for="(label, key) in CTV_STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
                </select>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- TAB 3: Settlement -->
      <div v-else-if="activeTab === 'settlement'" class="space-y-5">
        <div class="card-surface p-4 sm:p-5 space-y-4">
          <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Đối soát công nợ hoa hồng theo CTV</h2>
          <p v-if="settlementRows.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">Chưa có phát sinh hoa hồng từ CTV.</p>
          <template v-else>
            <div class="hidden lg:block overflow-x-auto">
              <table class="w-full text-left border-collapse text-xs">
                <thead>
                  <tr class="border-b border-slate-200 text-slate-500 uppercase text-[11px]">
                    <th class="py-2.5 pr-4 whitespace-nowrap">CTV</th>
                    <th class="py-2.5 pr-4 whitespace-nowrap">Chờ duyệt</th>
                    <th class="py-2.5 pr-4 whitespace-nowrap">Đã duyệt — Chờ trả</th>
                    <th class="py-2.5 pr-4 whitespace-nowrap">Đã thanh toán</th>
                    <th class="py-2.5 whitespace-nowrap">Thao tác</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-100">
                  <tr v-for="r in settlementRows" :key="r.code" class="align-top">
                    <td class="py-3.5 pr-4 whitespace-nowrap">
                      <strong class="text-[#0D2C54] block">{{ r.code }}</strong>
                      <span class="text-slate-600 block">{{ r.name }}</span>
                    </td>
                    <td class="py-3.5 pr-4 whitespace-nowrap tabular-nums">
                      <strong class="text-[#0D2C54] block">{{ formatCurrency(r.pendingAmt) }}</strong>
                      <span class="text-[11px] text-slate-500">{{ r.completedPending.length }} đơn hoàn thành</span>
                    </td>
                    <td class="py-3.5 pr-4 whitespace-nowrap tabular-nums">
                      <strong class="text-[#C81E2B] block">{{ formatCurrency(r.approvedAmt) }}</strong>
                      <span class="text-[11px] text-slate-500">{{ r.approved.length }} đơn chờ trả</span>
                    </td>
                    <td class="py-3.5 pr-4 whitespace-nowrap font-bold text-[#15803D] tabular-nums">{{ formatCurrency(r.paidAmt) }}</td>
                    <td class="py-3.5 whitespace-nowrap">
                      <div class="flex items-center gap-2">
                        <button v-if="r.completedPending.length > 0" type="button" class="min-h-[36px] px-3 rounded-lg bg-[#0D2C54] text-white text-[11px] font-semibold cursor-pointer" @click="approveCommission(r)">Duyệt hoa hồng</button>
                        <button v-if="r.approved.length > 0" type="button" class="min-h-[36px] px-3 rounded-lg bg-[#15803D] text-white text-[11px] font-semibold cursor-pointer" @click="payCommission(r)">Xác nhận thanh toán</button>
                        <span v-if="r.completedPending.length === 0 && r.approved.length === 0" class="text-[11px] text-slate-400">Đã đối soát xong</span>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="lg:hidden space-y-3">
              <div v-for="r in settlementRows" :key="r.code" class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-4 space-y-3 text-xs">
                <div><strong class="text-sm text-[#0D2C54]">{{ r.code }}</strong> · <span class="font-semibold">{{ r.name }}</span></div>
                <div class="grid grid-cols-3 gap-2 text-center bg-white rounded-lg p-2.5 border border-slate-200/80">
                  <div><span class="text-[10px] text-slate-500 block">Chờ duyệt</span><strong class="text-[#0D2C54] tabular-nums">{{ formatCurrency(r.pendingAmt) }}</strong></div>
                  <div><span class="text-[10px] text-slate-500 block">Chờ trả</span><strong class="text-[#C81E2B] tabular-nums">{{ formatCurrency(r.approvedAmt) }}</strong></div>
                  <div><span class="text-[10px] text-slate-500 block">Đã trả</span><strong class="text-[#15803D] tabular-nums">{{ formatCurrency(r.paidAmt) }}</strong></div>
                </div>
                <div class="flex flex-col gap-2">
                  <button v-if="r.completedPending.length > 0" type="button" class="min-h-[44px] w-full rounded-lg bg-[#0D2C54] text-white text-xs font-semibold" @click="approveCommission(r)">Duyệt hoa hồng ({{ r.completedPending.length }} đơn)</button>
                  <button v-if="r.approved.length > 0" type="button" class="min-h-[44px] w-full rounded-lg bg-[#15803D] text-white text-xs font-semibold" @click="payCommission(r)">Xác nhận thanh toán {{ formatCurrency(r.approvedAmt) }}</button>
                </div>
              </div>
            </div>
          </template>
        </div>

        <div class="card-surface p-4 sm:p-5 space-y-4">
          <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Lịch sử đã thanh toán hoa hồng</h2>
          <p v-if="allPayouts.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">Chưa có giao dịch thanh toán hoa hồng nào.</p>
          <div v-else class="space-y-2.5">
            <div v-for="p in allPayouts" :key="p.id" class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-3.5 text-xs flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
              <div>
                <strong class="text-[#0D2C54]">{{ p.affiliate_code }}</strong> · <span>{{ p.order_count }} đơn</span> · <span class="text-slate-500 tabular-nums">{{ formatDate(p.paid_at) }}</span>
                <p class="text-slate-600 m-0 mt-0.5">{{ p.note || '—' }}</p>
              </div>
              <strong class="text-sm text-[#15803D] tabular-nums shrink-0">{{ formatCurrency(p.amount) }}</strong>
            </div>
          </div>
        </div>
      </div>

      <!-- TAB 4: Leads -->
      <div v-else class="card-surface p-4 sm:p-5 space-y-4">
        <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Yêu cầu tư vấn &amp; đo phom xe</h2>
        <p v-if="allLeads.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">Chưa có yêu cầu tư vấn nào.</p>
        <div v-else class="space-y-3">
          <div v-for="l in allLeads" :key="l.id" class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-4 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3 text-xs">
            <div class="space-y-1">
              <div class="flex flex-wrap items-center gap-2">
                <strong class="text-slate-900">{{ l.customer_name }}</strong>
                <a :href="`tel:${l.phone}`" class="font-bold text-[#0D2C54] tabular-nums no-underline">{{ l.phone }}</a>
                <span class="text-[11px] text-slate-500 tabular-nums">{{ formatDate(l.created_at) }}</span>
              </div>
              <p class="m-0"><strong class="text-[#0D2C54]">{{ l.vehicle || 'Chưa chọn xe' }}</strong> — {{ l.message || '—' }}</p>
            </div>
            <select :value="l.status" class="min-h-[44px] lg:min-h-[38px] lg:w-40 border border-slate-300 rounded-lg px-3 text-xs font-semibold bg-white shrink-0" @change="updateLeadStatus(l, ($event.target as HTMLSelectElement).value)">
              <option value="new">Chưa gọi</option>
              <option value="contacted">Đã tư vấn</option>
              <option value="closed">Đã chốt / Đóng</option>
            </select>
          </div>
        </div>
      </div>
    </section>

    <!-- Create Account Modal (Develop only) -->
    <Teleport to="body">
      <div v-if="showCreateModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-slate-900/60 backdrop-blur-[2px]" @click="showCreateModal = false" />
        <div class="bg-white border border-slate-200 rounded-2xl w-full max-w-md p-5 sm:p-6 relative z-10 shadow-2xl space-y-4 max-h-[90vh] overflow-y-auto">
          <div class="flex items-center justify-between border-b border-slate-200 pb-3">
            <h3 class="text-base font-bold uppercase text-[#0D2C54] m-0">Tạo tài khoản hệ thống</h3>
            <button type="button" class="icon-touch-btn text-slate-500" aria-label="Đóng" @click="showCreateModal = false">
              <X class="w-5 h-5" />
            </button>
          </div>
          <p v-if="createErr" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3 py-2 m-0">{{ createErr }}</p>
          <form class="space-y-3" @submit.prevent="handleCreateAccount">
            <div class="grid grid-cols-2 gap-3">
              <div class="space-y-1">
                <label class="text-xs font-semibold text-slate-700 block">Vai trò *</label>
                <select v-model="newAcc.role" class="ymm-select text-xs">
                  <option value="admin">Admin (Quản trị)</option>
                  <option value="ctv">CTV (Cộng tác viên)</option>
                  <option value="develop">Develop (Toàn quyền)</option>
                </select>
              </div>
              <div class="space-y-1">
                <label class="text-xs font-semibold text-slate-700 block">Hoa hồng (%)</label>
                <input v-model="newAcc.rate" type="number" min="0" max="50" step="0.5" class="field-input text-xs tabular-nums">
              </div>
            </div>
            <div class="space-y-1">
              <label class="text-xs font-semibold text-slate-700 block">Họ và tên *</label>
              <input v-model="newAcc.name" type="text" required placeholder="VD: Nguyễn Văn Admin" class="field-input text-xs">
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div class="space-y-1">
                <label class="text-xs font-semibold text-slate-700 block">Số điện thoại *</label>
                <input v-model="newAcc.phone" type="tel" required placeholder="0963294492" class="field-input text-xs">
              </div>
              <div class="space-y-1">
                <label class="text-xs font-semibold text-slate-700 block">Mã định danh *</label>
                <input v-model="newAcc.code" type="text" required placeholder="VD: ADMIN02" class="field-input text-xs uppercase">
              </div>
            </div>
            <div class="space-y-1">
              <label class="text-xs font-semibold text-slate-700 block">Email đăng nhập *</label>
              <input v-model="newAcc.email" type="email" required placeholder="email@domain.com" class="field-input text-xs">
            </div>
            <div class="space-y-1">
              <label class="text-xs font-semibold text-slate-700 block">Mật khẩu (≥ 6 ký tự) *</label>
              <input v-model="newAcc.password" type="password" required minlength="6" placeholder="Nhập mật khẩu..." class="field-input text-xs">
            </div>
            <button type="submit" :disabled="isCreating" class="btn-cta w-full text-xs">
              {{ isCreating ? 'ĐANG TẠO TÀI KHOẢN...' : 'TẠO & KÍCH HOẠT NGAY' }}
            </button>
          </form>
        </div>
      </div>
    </Teleport>
  </main>
</template>
