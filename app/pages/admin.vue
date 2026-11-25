<script setup lang="ts">
import { ShieldCheck, Lock, UserCheck, UserPlus, RefreshCw, X, AlertTriangle, ChevronLeft, ChevronRight, Download, Eye } from 'lucide-vue-next';

definePageMeta({ middleware: 'auth-admin' });

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
const loadError = ref('');
const isLoading = ref(false);
const busyKey = ref<string | null>(null);

const overview = ref({
  total_orders: 0,
  direct_orders: 0,
  ctv_orders: 0,
  cancelled_orders: 0,
  revenue: 0,
  active_ctv: 0,
  pending_ctv: 0,
  comm_pending: 0,
  comm_holding: 0,
  comm_available: 0,
  comm_paid: 0
});

const ordersList = ref<any[]>([]);
const ordersTotal = ref(0);
const ordersPage = ref(1);
const pageSize = 25;

const allAffiliates = ref<any[]>([]);
const affiliatesTotal = ref(0);
const affiliatesPage = ref(1);
const settlementRows = ref<any[]>([]);
const allLeads = ref<any[]>([]);
const leadsTotal = ref(0);
const leadsPage = ref(1);
const leadStatusFilter = ref('');
const allPayouts = ref<any[]>([]);
const payoutsTotal = ref(0);
const payoutsPage = ref(1);
const payoutRequests = ref<any[]>([]);

const activeTab = ref<'orders' | 'affiliates' | 'settlement' | 'leads' | 'reports' | 'customers' | 'catalog' | 'audit'>('orders');
const orderSearch = ref('');
const sourceFilter = ref('');
const orderStatusFilter = ref('');
const orderFrom = ref('');
const orderTo = ref('');
const ctvStatusFilter = ref('');

const selectedOrderId = ref<string | null>(null);
const selectedAffiliateId = ref<string | null>(null);

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
  cancelled: 'Đã hủy',
  returned: 'Hoàn trả'
};

const VALID_TRANSITIONS: Record<string, string[]> = {
  new: ['new', 'confirmed', 'cancelled'],
  confirmed: ['confirmed', 'shipping', 'completed', 'cancelled'],
  shipping: ['shipping', 'completed', 'cancelled', 'returned'],
  completed: ['completed', 'returned'],
  cancelled: ['cancelled'],
  returned: ['returned']
};

const STATUS_BADGE: Record<string, string> = {
  new: 'bg-sky-50 text-sky-700 border-sky-200',
  confirmed: 'bg-[#EFF4FA] text-[#0D2C54] border-[#0D2C54]/20',
  shipping: 'bg-amber-50 text-amber-700 border-amber-200',
  completed: 'bg-green-50 text-[#15803D] border-green-200',
  cancelled: 'bg-[#FEF2F2] text-[#C81E2B] border-[#C81E2B]/25',
  returned: 'bg-purple-50 text-purple-700 border-purple-200'
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
  pending: 'Tạm tính',
  holding: 'Đang giữ',
  available: 'Khả dụng',
  approved: 'Khả dụng',
  paid: 'Đã trả',
  reversed: 'Đã thu hồi'
};

const isDevelop = computed(() => currentAdmin.value?.role === 'develop');
const totalOrderPages = computed(() => Math.max(1, Math.ceil(ordersTotal.value / pageSize)));

const formatDate = (iso: string) =>
  iso ? new Date(iso).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';

const pageCount = (total: number) => Math.max(1, Math.ceil(total / pageSize));
const totalAffiliatePages = computed(() => pageCount(affiliatesTotal.value));
const totalLeadPages = computed(() => pageCount(leadsTotal.value));
const totalPayoutPages = computed(() => pageCount(payoutsTotal.value));

const loadAllData = async () => {
  if (!supabase) return;
  isLoading.value = true;
  loadError.value = '';
  try {
    const [ovRes, ordRes, affRes, setRes, leadRes, payRes, reqRes] = await Promise.all([
      supabase.rpc('admin_overview', { p_from: null, p_to: null }),
      supabase.rpc('admin_list_orders', {
        p_search: orderSearch.value.trim() || null,
        p_source: sourceFilter.value || null,
        p_status: orderStatusFilter.value || null,
        p_from: orderFrom.value ? `${orderFrom.value}T00:00:00+07:00` : null,
        p_to: orderTo.value ? `${orderTo.value}T23:59:59+07:00` : null,
        p_page: ordersPage.value,
        p_page_size: pageSize
      }),
      supabase.rpc('admin_list_affiliates', {
        p_status: ctvStatusFilter.value || null,
        p_search: null,
        p_page: affiliatesPage.value,
        p_page_size: pageSize
      }),
      supabase.rpc('admin_settlement_summary'),
      supabase.rpc('admin_list_leads', {
        p_status: leadStatusFilter.value || null,
        p_search: null,
        p_page: leadsPage.value,
        p_page_size: pageSize
      }),
      supabase.rpc('admin_list_payouts', {
        p_search: null,
        p_from: null,
        p_to: null,
        p_page: payoutsPage.value,
        p_page_size: pageSize
      }),
      supabase.rpc('admin_list_payout_requests', { p_status: 'all', p_page: 1, p_page_size: 50 })
    ]);

    if (ovRes.error) throw ovRes.error;
    if (ordRes.error) throw ordRes.error;

    overview.value = { ...overview.value, ...(ovRes.data || {}) };
    ordersList.value = ordRes.data?.items || [];
    ordersTotal.value = Number(ordRes.data?.total || 0);
    allAffiliates.value = Array.isArray(affRes.data?.items) ? affRes.data.items : [];
    affiliatesTotal.value = Number(affRes.data?.total || 0);
    settlementRows.value = Array.isArray(setRes.data) ? setRes.data : [];
    allLeads.value = Array.isArray(leadRes.data?.items) ? leadRes.data.items : [];
    leadsTotal.value = Number(leadRes.data?.total || 0);
    allPayouts.value = Array.isArray(payRes.data?.items) ? payRes.data.items : [];
    payoutsTotal.value = Number(payRes.data?.total || 0);
    payoutRequests.value = Array.isArray(reqRes.data?.items) ? reqRes.data.items : [];
  } catch (err: any) {
    loadError.value = err?.message || 'Không thể tải dữ liệu quản trị. Kiểm tra kết nối hoặc migration Supabase.';
  } finally {
    isLoading.value = false;
  }
};

watch([orderSearch, sourceFilter, orderStatusFilter], () => {
  ordersPage.value = 1;
  if (viewState.value === 'dashboard') loadAllData();
});

watch(ctvStatusFilter, () => {
  affiliatesPage.value = 1;
  if (viewState.value === 'dashboard') loadAllData();
});

watch(leadStatusFilter, () => {
  leadsPage.value = 1;
  if (viewState.value === 'dashboard') loadAllData();
});

const changeListPage = (target: 'affiliates' | 'leads' | 'payouts', delta: number) => {
  const state = {
    affiliates: { page: affiliatesPage, pages: totalAffiliatePages },
    leads: { page: leadsPage, pages: totalLeadPages },
    payouts: { page: payoutsPage, pages: totalPayoutPages }
  }[target];
  const next = state.page.value + delta;
  if (next < 1 || next > state.pages.value) return;
  state.page.value = next;
  loadAllData();
};

const changeOrderPage = (delta: number) => {
  const next = ordersPage.value + delta;
  if (next < 1 || next > totalOrderPages.value) return;
  ordersPage.value = next;
  loadAllData();
};

const updateOrderStatus = async (order: any, nextStatus: string) => {
  if (!supabase || nextStatus === order.status) return;
  let reason: string | null = null;
  if (['cancelled', 'returned'].includes(nextStatus) && import.meta.client) {
    reason = window.prompt(`Nhập lý do ${STATUS_LABELS[nextStatus]} cho đơn #${order.order_code} (bắt buộc):`, '');
    if (!reason || reason.trim().length < 3) {
      showToast('Đã hủy thao tác: cần nhập lý do ít nhất 3 ký tự.', 'error');
      await loadAllData();
      return;
    }
  }
  busyKey.value = `order:${order.id}`;
  const { error } = await supabase.rpc('admin_set_order_status', {
    p_order_id: order.id,
    p_new_status: nextStatus,
    p_reason: reason
  });
  busyKey.value = null;
  if (error) {
    showToast(error.message || `Lỗi cập nhật đơn #${order.order_code}`, 'error');
    await loadAllData();
  } else {
    showToast(`Đã cập nhật đơn #${order.order_code} → ${STATUS_LABELS[nextStatus]}`);
    await loadAllData();
  }
};

const updateAffiliateStatus = async (aff: any, nextStatus: string) => {
  if (!supabase) return;
  let reason: string | null = null;
  if (['suspended', 'cancelled'].includes(nextStatus) && import.meta.client) {
    reason = window.prompt(`Nhập lý do chuyển ${aff.code} sang "${CTV_STATUS_LABELS[nextStatus]}":`, '') || null;
  }
  busyKey.value = `aff:${aff.id}`;
  const { error } = await supabase.rpc('admin_update_affiliate', {
    p_affiliate_id: aff.id,
    p_status: nextStatus,
    p_reject_reason: reason
  });
  busyKey.value = null;
  if (error) showToast(error.message || `Lỗi cập nhật trạng thái ${aff.code}`, 'error');
  else {
    showToast(`Đã đổi trạng thái ${aff.code} → ${CTV_STATUS_LABELS[nextStatus]}`);
    await loadAllData();
  }
};

const updateAffiliateRate = async (aff: any, rawRate: string) => {
  if (!supabase) return;
  const rate = Math.max(0, Math.min(50, Number(rawRate) || 0));
  if (import.meta.client && !window.confirm(`Xác nhận đổi hoa hồng của ${aff.code} từ ${aff.commission_rate}% sang ${rate}%?`)) {
    await loadAllData();
    return;
  }
  busyKey.value = `rate:${aff.id}`;
  const { error } = await supabase.rpc('admin_update_affiliate', {
    p_affiliate_id: aff.id,
    p_commission_rate: rate
  });
  busyKey.value = null;
  if (error) showToast(error.message || `Lỗi cập nhật hoa hồng ${aff.code}`, 'error');
  else {
    showToast(`Đã cập nhật hoa hồng ${aff.code} → ${rate}%`);
    await loadAllData();
  }
};

const updateAffiliateRole = async (aff: any, nextRole: string) => {
  if (!supabase) return;
  busyKey.value = `role:${aff.id}`;
  const { error } = await supabase.rpc('develop_set_account_role', {
    p_email: aff.email,
    p_role: nextRole,
    p_status: 'active'
  });
  busyKey.value = null;
  if (error) showToast(error.message || `Lỗi đổi vai trò ${aff.code}`, 'error');
  else {
    showToast(`Đã đổi vai trò ${aff.code} → ${nextRole.toUpperCase()}`);
    await loadAllData();
  }
};

const approveCommission = async (row: any) => {
  if (!supabase || !row.holding_ids?.length) return;
  busyKey.value = `approve:${row.affiliate_id}`;
  const { data, error } = await supabase.rpc('admin_approve_commissions', {
    p_commission_ids: row.holding_ids,
    p_reason: `Duyệt mở khóa hoa hồng cho ${row.code}`
  });
  busyKey.value = null;
  if (error) showToast(error.message || `Lỗi duyệt hoa hồng ${row.code}`, 'error');
  else {
    showToast(`Đã mở khóa hoa hồng ${data} đơn cho ${row.code}`);
    await loadAllData();
  }
};

const payCommission = async (row: any) => {
  if (!supabase || !row.available_ids?.length || !import.meta.client) return;
  const txRef = window.prompt(`Nhập MÃ GIAO DỊCH chuyển khoản ${formatCurrency(row.net_available_balance)} cho ${row.code} (bắt buộc):`, '');
  if (!txRef || txRef.trim().length < 3) {
    showToast('Cần nhập mã giao dịch chuyển khoản (ít nhất 3 ký tự).', 'error');
    return;
  }
  const note = window.prompt('Ghi chú thanh toán (tùy chọn):', `CK hoa hồng ${row.code} (${row.available_count} đơn)`) || '';

  busyKey.value = `pay:${row.affiliate_id}`;
  const idempKey = `pay:${row.affiliate_id}:${[...row.available_ids].sort().join(',')}`;
  const { data, error } = await supabase.rpc('admin_pay_commissions', {
    p_affiliate_id: row.affiliate_id,
    p_commission_ids: row.available_ids,
    p_transaction_ref: txRef.trim(),
    p_note: note.trim(),
    p_idempotency_key: idempKey
  });
  busyKey.value = null;

  if (error) showToast(error.message || `Lỗi thanh toán cho ${row.code}`, 'error');
  else {
    showToast(`Đã chi trả ${formatCurrency(data?.net_amount || row.net_available_balance)} cho ${row.code}`);
    await loadAllData();
  }
};

const runReleaseMatured = async () => {
  if (!supabase) return;
  busyKey.value = 'release';
  const { data, error } = await supabase.rpc('release_matured_commissions');
  busyKey.value = null;
  if (error) showToast(error.message, 'error');
  else {
    showToast(`Đã mở khóa ${data || 0} khoản hoa hồng hết hạn giữ (hold).`);
    await loadAllData();
  }
};

const updateLeadStatus = async (lead: any, nextStatus: string) => {
  if (!supabase) return;
  busyKey.value = `lead:${lead.id}`;
  const { error } = await supabase.rpc('admin_update_lead_status', {
    p_lead_id: lead.id,
    p_status: nextStatus,
    p_reason: null
  });
  busyKey.value = null;
  if (error) {
    showToast(error.message || 'Lỗi cập nhật trạng thái tư vấn', 'error');
    await loadAllData();
  } else {
    showToast('Đã cập nhật trạng thái yêu cầu tư vấn');
    await loadAllData(); // Fix V19
  }
};

const handleCreateAccount = async () => {
  createErr.value = '';
  const tempClient = createEphemeralClient();
  if (!supabase || !tempClient) return;
  if (newAcc.password.length < 8) {
    createErr.value = 'Mật khẩu phải có ít nhất 8 ký tự.';
    return;
  }
  isCreating.value = true;
  try {
    const createdRole = newAcc.role; // Fix V19: lưu trước khi reset form
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
          job_type: createdRole === 'admin' ? 'Quản trị viên' : 'Cộng tác viên'
        }
      }
    });
    if (signUpErr) throw signUpErr;

    const { error: rpcErr } = await supabase.rpc('develop_set_account_role', {
      p_email: cleanEmail,
      p_role: createdRole,
      p_status: 'active',
      p_commission_rate: Number(newAcc.rate) || 10
    });
    if (rpcErr) throw rpcErr;

    showCreateModal.value = false;
    Object.assign(newAcc, { role: 'admin', rate: 10, name: '', phone: '', code: '', email: '', password: '' });
    showToast(`Đã tạo tài khoản ${createdRole.toUpperCase()} (${cleanEmail}) thành công!`);
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
  if (!prof || !['staff', 'admin', 'develop'].includes(prof.role) || prof.status !== 'active') {
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

const reviewPayoutRequest = async (req: any, action: 'approve' | 'reject' | 'pay') => {
  if (!supabase) return;
  let txRef: string | null = null;
  let reason: string | null = null;
  if (action === 'reject') {
    const input = window.prompt('Nhập lý do từ chối yêu cầu rút tiền (bắt buộc):', '');
    if (!input || input.trim().length < 3) {
      showToast('Cần nhập lý do tối thiểu 3 ký tự.');
      return;
    }
    reason = input.trim();
  } else if (action === 'pay') {
    const input = window.prompt(`Nhập mã giao dịch chuyển khoản cho ${req.affiliate_code} (${formatCurrency(req.amount)}):`, '');
    if (!input || input.trim().length < 3) {
      showToast('Cần nhập mã giao dịch chuyển khoản.');
      return;
    }
    txRef = input.trim();
  }

  busyKey.value = `req:${req.id}`;
  const { error } = await supabase.rpc('admin_review_payout_request', {
    p_request_id: req.id,
    p_action: action,
    p_transaction_ref: txRef,
    p_reject_reason: reason,
    p_note: null
  });
  busyKey.value = null;
  if (error) {
    showToast(error.message || 'Không xử lý được yêu cầu rút tiền.');
    return;
  }
  showToast(action === 'approve' ? 'Đã duyệt yêu cầu rút tiền.' : action === 'reject' ? 'Đã từ chối yêu cầu.' : 'Đã xác nhận chi trả!');
  await loadAllData();
};

const exportAdminOrdersCsv = () => {
  if (!ordersList.value.length) { showToast('Không có đơn hàng để xuất.'); return; }
  exportToCsv(
    `admin-don-hang-${new Date().toISOString().slice(0, 10)}.csv`,
    ['Mã đơn', 'Ngày tạo', 'Khách hàng', 'SĐT', 'Địa chỉ', 'Thanh toán', 'Tổng tiền', 'CTV', 'Hoa hồng', 'Trạng thái'],
    ordersList.value.map((o) => [
      o.order_code,
      formatDate(o.created_at),
      o.customer_name,
      o.customer_phone || o.phone || '',
      o.customer_address || o.address || '',
      o.payment_method,
      o.total ?? o.total_amount ?? 0,
      o.affiliate_code || 'Khách lẻ',
      o.commission_amount || 0,
      STATUS_LABELS[o.status] || o.status
    ])
  );
};

const exportSettlementCsv = () => {
  if (!settlementRows.value.length) { showToast('Chưa có dữ liệu đối soát.'); return; }
  exportToCsv(
    `admin-doi-soat-${new Date().toISOString().slice(0, 10)}.csv`,
    ['Mã CTV', 'Họ tên', 'Đang giữ (Hold)', 'Khả dụng chờ trả', 'Đã thanh toán'],
    settlementRows.value.map((r) => [r.code, r.full_name, r.holding_amount, r.net_available_balance, r.paid_amount])
  );
};

const fetchAllPayoutsForExport = async (): Promise<any[]> => {
  if (!supabase) return [];
  const rows: any[] = [];
  const exportPageSize = 100;
  const maxPages = 50;
  for (let page = 1; page <= maxPages; page++) {
    const { data, error } = await supabase.rpc('admin_list_payouts', {
      p_search: null,
      p_from: null,
      p_to: null,
      p_page: page,
      p_page_size: exportPageSize
    });
    if (error) throw error;
    const items = Array.isArray(data?.items) ? data.items : [];
    rows.push(...items);
    if (items.length < exportPageSize) break;
  }
  return rows;
};

const exportPayoutsCsv = async () => {
  if (!payoutsTotal.value) { showToast('Chưa có lịch sử chi trả.'); return; }
  let rows: any[] = [];
  try {
    rows = await fetchAllPayoutsForExport();
  } catch (err: any) {
    showToast(err?.message || 'Không tải được toàn bộ lịch sử chi trả.', 'error');
    return;
  }
  exportToCsv(
    `admin-chi-tra-${new Date().toISOString().slice(0, 10)}.csv`,
    ['Ngày chi trả', 'Mã CTV', 'Số đơn', 'Trước thuế', 'Thuế TNCN', 'Thực nhận', 'Mã GD', 'Ghi chú'],
    rows.map((p) => [
      formatDate(p.paid_at), p.affiliate_code, p.order_count,
      p.gross_amount ?? p.amount, p.tax_amount ?? 0, p.net_amount ?? p.amount,
      p.transaction_ref || '', p.note || ''
    ])
  );
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
        <p class="text-xs text-slate-500 m-0">Dành riêng cho Admin, Nhân viên &amp; Develop quản lý hệ thống</p>
      </div>

      <p v-if="loginError" role="alert"
        class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3.5 py-2.5 m-0">
        {{ loginError }}
      </p>

      <form class="space-y-3.5" @submit.prevent="handleLogin">
        <div class="space-y-1">
          <label for="admin-email" class="text-xs font-semibold text-slate-700 block">Email quản trị</label>
          <input id="admin-email" v-model="loginEmail" type="email" required placeholder="admin@domain.com"
            class="field-input">
        </div>
        <div class="space-y-1">
          <label for="admin-password" class="text-xs font-semibold text-slate-700 block">Mật khẩu</label>
          <input id="admin-password" v-model="loginPassword" type="password" required placeholder="Nhập mật khẩu..."
            class="field-input">
        </div>
        <button type="submit" :disabled="isLoggingIn" class="btn-cta w-full text-xs">
          {{ isLoggingIn ? 'ĐANG ĐĂNG NHẬP...' : 'ĐĂNG NHẬP QUẢN TRỊ' }}
        </button>
      </form>

      <p class="text-xs text-slate-600 text-center m-0 pt-2 border-t border-slate-100">
        Bạn là Cộng tác viên? <NuxtLink to="/ctv" class="font-semibold text-[#0D2C54] underline">Vào Cổng CTV →
        </NuxtLink>
      </p>
    </section>

    <!-- Forbidden -->
    <section v-else-if="viewState === 'forbidden'" class="max-w-lg mx-auto card-surface p-6 text-center space-y-4">
      <div
        class="w-14 h-14 rounded-full bg-[#FEF2F2] border border-[#C81E2B]/30 text-[#C81E2B] flex items-center justify-center mx-auto">
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
            <span
              class="text-[11px] font-bold uppercase px-2.5 py-0.5 rounded-full bg-[#0D2C54] text-white whitespace-nowrap">
              {{ isDevelop ? 'DEVELOP · TOÀN QUYỀN' : (currentAdmin?.role === 'staff' ? 'NHÂN VIÊN' : 'ADMIN PORTAL') }}
            </span>
          </div>
          <p class="text-xs text-slate-500 m-0 truncate">{{ currentAdmin?.full_name }} ({{ currentAdmin?.email }})</p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <NuxtLink v-if="isDevelop" to="/ctv"
            class="inline-flex items-center justify-center gap-1.5 min-h-[44px] lg:min-h-[40px] px-3.5 rounded-lg bg-[#EFF4FA] hover:bg-slate-200 text-[#0D2C54] text-xs font-semibold no-underline transition whitespace-nowrap shrink-0">
            <UserCheck class="w-3.5 h-3.5" /> Xem Cổng CTV
          </NuxtLink>
          <button v-if="isDevelop" type="button"
            class="inline-flex items-center justify-center gap-1.5 min-h-[44px] lg:min-h-[40px] px-3.5 rounded-lg bg-[#0D2C54] hover:bg-[#133A6E] text-white text-xs font-semibold cursor-pointer transition whitespace-nowrap shrink-0"
            @click="showCreateModal = true">
            <UserPlus class="w-3.5 h-3.5" /> Tạo tài khoản
          </button>
          <button type="button" :disabled="isLoading"
            class="btn-outline text-xs px-3.5 min-h-[44px] lg:min-h-[40px] whitespace-nowrap shrink-0"
            @click="loadAllData().then(() => showToast('Đã làm mới dữ liệu hệ thống'))">
            <RefreshCw class="w-3.5 h-3.5" :class="{ 'animate-spin': isLoading }" /> Tải lại
          </button>
          <button type="button"
            class="btn-outline text-xs px-3.5 min-h-[44px] lg:min-h-[40px] text-[#C81E2B] border-[#C81E2B]/30 whitespace-nowrap shrink-0"
            @click="handleLogout">
            Đăng xuất
          </button>
        </div>
      </div>

      <!-- Error Banner -->
      <div v-if="loadError" role="alert"
        class="card-surface p-4 border-[#C81E2B]/40 bg-[#FEF2F2] flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 text-xs text-[#C81E2B]">
        <div class="flex items-center gap-2 font-semibold">
          <AlertTriangle class="w-4 h-4 shrink-0" />
          <span>{{ loadError }}</span>
        </div>
        <button type="button" class="btn-outline text-xs px-3.5 min-h-[38px] shrink-0" @click="loadAllData">Thử
          lại</button>
      </div>

      <!-- KPIs (100% tính ở DB qua admin_overview) -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Tổng đơn hệ thống</span>
          <span class="text-xl sm:text-2xl font-bold text-[#0D2C54] tabular-nums block">{{ overview.total_orders
          }}</span>
          <span class="text-[11px] text-slate-500 block tabular-nums">{{ overview.direct_orders }} lẻ · {{
            overview.ctv_orders }} CTV</span>
        </div>
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Tổng doanh số</span>
          <span class="text-xl sm:text-2xl font-bold text-[#15803D] tabular-nums block">{{
            formatCurrency(overview.revenue) }}</span>
          <span class="text-[11px] text-slate-500 block tabular-nums">Hủy/hoàn: {{ overview.cancelled_orders }}
            đơn</span>
        </div>
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Cộng tác viên</span>
          <span class="text-xl sm:text-2xl font-bold text-[#0D2C54] tabular-nums block">{{ overview.active_ctv }}</span>
          <span class="text-[11px] text-[#C81E2B] font-semibold block tabular-nums">{{ overview.pending_ctv }} chờ
            duyệt</span>
        </div>
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Hoa hồng khả dụng chờ trả</span>
          <span class="text-xl sm:text-2xl font-bold text-[#0D2C54] tabular-nums block">{{
            formatCurrency(overview.comm_available) }}</span>
          <span class="text-[11px] text-[#15803D] font-semibold block tabular-nums">Đã trả: {{
            formatCurrency(overview.comm_paid) }}</span>
        </div>
      </div>

      <!-- Tabs -->
      <div class="flex gap-2 overflow-x-auto no-scrollbar pb-1 border-b border-slate-200">
        <button v-for="tab in [
          { key: 'orders', label: '1. Đơn hàng' },
          { key: 'affiliates', label: '2. Cộng tác viên' },
          { key: 'settlement', label: '3. Đối soát & Rút tiền' },
          { key: 'leads', label: '4. Tư vấn' },
          { key: 'reports', label: '5. Báo cáo' },
          { key: 'customers', label: '6. Khách hàng' },
          { key: 'catalog', label: '7. Sản phẩm & KM' },
          { key: 'audit', label: '8. Nhật ký (Audit)' }
        ]" :key="tab.key" type="button"
          class="min-h-[44px] lg:min-h-[40px] px-3.5 py-2 rounded-lg text-xs font-semibold cursor-pointer whitespace-nowrap shrink-0"
          :class="activeTab === tab.key ? 'bg-[#0D2C54] text-white' : 'bg-white text-slate-700 border border-slate-200'"
          @click="activeTab = tab.key as any">
          {{ tab.label }}
        </button>
      </div>

      <!-- TAB 1: Orders (Server-side pagination & filtering) -->
      <div v-if="activeTab === 'orders'" class="card-surface p-4 sm:p-5 space-y-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-6 gap-2.5">
          <input v-model="orderSearch" type="search" placeholder="Tìm mã đơn, tên, SĐT, mã CTV..."
            class="field-input text-xs lg:col-span-2">
          <select v-model="sourceFilter" aria-label="Lọc nguồn đơn" class="ymm-select text-xs">
            <option value="">Tất cả nguồn</option>
            <option value="direct">Khách lẻ</option>
            <option value="ctv">Qua CTV</option>
          </select>
          <select v-model="orderStatusFilter" aria-label="Lọc trạng thái đơn" class="ymm-select text-xs">
            <option value="">Tất cả trạng thái</option>
            <option v-for="(label, key) in STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
          </select>
          <input v-model="orderFrom" type="date" aria-label="Từ ngày" class="field-input text-xs"
            @change="ordersPage = 1; loadAllData()">
          <div class="flex gap-2">
            <input v-model="orderTo" type="date" aria-label="Đến ngày" class="field-input text-xs flex-1 min-w-0"
              @change="ordersPage = 1; loadAllData()">
            <button type="button" class="btn-outline text-xs px-3 shrink-0" title="Xuất CSV đơn hàng"
              @click="exportAdminOrdersCsv">
              <Download class="w-4 h-4" />
            </button>
          </div>
        </div>

        <p v-if="isLoading" class="text-xs text-slate-500 text-center py-6 m-0">Đang tải danh sách đơn hàng...</p>
        <p v-else-if="ordersList.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">Không có đơn hàng phù
          hợp bộ lọc.</p>
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
                <tr v-for="o in ordersList" :key="o.id" class="align-top">
                  <td class="py-3.5 pr-4 whitespace-nowrap">
                    <strong class="text-[#0D2C54] tabular-nums block">#{{ o.order_code }}</strong>
                    <span class="text-[11px] text-slate-500 tabular-nums">{{ formatDate(o.created_at) }}</span>
                  </td>
                  <td class="py-3.5 pr-4 min-w-[170px]">
                    <strong class="text-slate-900 block">{{ o.customer_name }}</strong>
                    <a :href="`tel:${o.phone}`"
                      class="text-[#0D2C54] font-semibold tabular-nums no-underline hover:underline block">{{ o.phone
                      }}</a>
                    <span class="text-[11px] text-slate-500 block">{{ o.address }}</span>
                  </td>
                  <td class="py-3.5 pr-4 max-w-xs">
                    <p class="m-0 text-slate-700 whitespace-pre-line leading-snug">{{ o.items_summary }}</p>
                    <span
                      class="inline-block mt-1 px-2 py-0.5 rounded bg-slate-100 text-slate-600 text-[10px] font-semibold">{{
                        o.payment_method }} · {{ o.payment_status || 'unpaid' }}</span>
                  </td>
                  <td class="py-3.5 pr-4 whitespace-nowrap font-bold text-[#15803D] tabular-nums">{{
                    formatCurrency(o.total_amount) }}</td>
                  <td class="py-3.5 pr-4 whitespace-nowrap">
                    <template v-if="o.affiliate_code">
                      <span
                        class="inline-block px-2 py-0.5 rounded bg-[#FEF2F2] text-[#C81E2B] font-semibold text-[11px]">{{
                          o.affiliate_code }}</span>
                      <span class="block text-[#15803D] font-semibold tabular-nums mt-0.5">{{
                        formatCurrency(o.commission_amount) }} ({{ COMM_LABELS[o.ledger_commission_status ||
                          o.commission_status] }})</span>
                    </template>
                    <span v-else class="inline-block px-2 py-0.5 rounded bg-slate-100 text-slate-600 text-[11px]">Khách
                      lẻ</span>
                  </td>
                  <td class="py-3.5 whitespace-nowrap">
                    <div class="flex items-center gap-1.5">
                      <select :value="o.status"
                        :disabled="busyKey === `order:${o.id}` || (VALID_TRANSITIONS[o.status] || []).length <= 1"
                        class="min-h-[38px] w-32 border border-slate-300 rounded-lg px-2 text-xs font-semibold bg-white text-[#0D2C54]"
                        @change="updateOrderStatus(o, ($event.target as HTMLSelectElement).value)">
                        <option v-for="st in (VALID_TRANSITIONS[o.status] || [o.status])" :key="st" :value="st">{{
                          STATUS_LABELS[st] }}
                        </option>
                      </select>
                      <button type="button" aria-label="Xem chi tiết đơn"
                        class="btn-outline text-xs px-2.5 min-h-[38px]" @click="selectedOrderId = o.id">
                        <Eye class="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="lg:hidden space-y-3">
            <div v-for="o in ordersList" :key="o.id"
              class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-4 space-y-3 text-xs">
              <div class="flex items-start justify-between gap-2">
                <div>
                  <strong class="text-sm text-[#0D2C54] tabular-nums block">#{{ o.order_code }}</strong>
                  <span class="text-[11px] text-slate-500 tabular-nums">{{ formatDate(o.created_at) }}</span>
                </div>
                <span class="px-2.5 py-1 rounded-full border text-[11px] font-semibold whitespace-nowrap"
                  :class="STATUS_BADGE[o.status]">{{ STATUS_LABELS[o.status] }}</span>
              </div>
              <div class="bg-white rounded-lg p-3 border border-slate-200/80 space-y-1">
                <div class="flex justify-between gap-2">
                  <strong class="text-slate-900">{{ o.customer_name }}</strong>
                  <a :href="`tel:${o.phone}`" class="text-[#0D2C54] font-bold tabular-nums no-underline">{{ o.phone
                  }}</a>
                </div>
                <p class="text-[11px] text-slate-500 m-0">{{ o.address }}</p>
              </div>
              <p class="m-0 text-slate-700 whitespace-pre-line leading-relaxed">{{ o.items_summary }}</p>
              <div class="flex items-center justify-between gap-2 pt-2 border-t border-slate-200">
                <div>
                  <span class="text-[11px] text-slate-500 block">{{ o.payment_method }} · {{ o.affiliate_code ? `CTV
                    ${o.affiliate_code}` : 'Khách lẻ' }}</span>
                  <strong class="text-base text-[#15803D] tabular-nums">{{ formatCurrency(o.total_amount) }}</strong>
                </div>
                <select :value="o.status"
                  :disabled="busyKey === `order:${o.id}` || (VALID_TRANSITIONS[o.status] || []).length <= 1"
                  class="min-h-[44px] w-40 border border-slate-300 rounded-lg px-3 text-xs font-semibold bg-white text-[#0D2C54]"
                  @change="updateOrderStatus(o, ($event.target as HTMLSelectElement).value)">
                  <option v-for="st in (VALID_TRANSITIONS[o.status] || [o.status])" :key="st" :value="st">{{
                    STATUS_LABELS[st] }}
                  </option>
                </select>
              </div>
            </div>
          </div>

          <div v-if="totalOrderPages > 1"
            class="flex items-center justify-between pt-3 border-t border-slate-200 text-xs">
            <span class="text-slate-500 tabular-nums">Trang {{ ordersPage }} / {{ totalOrderPages }} ({{ ordersTotal }}
              đơn)</span>
            <div class="flex gap-2">
              <button type="button" :disabled="ordersPage <= 1" class="btn-outline text-xs px-3 min-h-[38px]"
                @click="changeOrderPage(-1)">
                <ChevronLeft class="w-4 h-4" /> Trước
              </button>
              <button type="button" :disabled="ordersPage >= totalOrderPages"
                class="btn-outline text-xs px-3 min-h-[38px]" @click="changeOrderPage(1)">
                Sau
                <ChevronRight class="w-4 h-4" />
              </button>
            </div>
          </div>
        </template>
      </div>

      <!-- TAB 2: Affiliates -->
      <div v-else-if="activeTab === 'affiliates'" class="card-surface p-4 sm:p-5 space-y-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Danh sách Cộng tác viên &amp; Tài khoản</h2>
            <p class="text-xs text-slate-500 mt-0.5 m-0">Mọi thao tác đi qua RPC bảo mật và được ghi vào Nhật ký hoạt
              động.
            </p>
          </div>
          <select v-model="ctvStatusFilter" aria-label="Lọc trạng thái CTV" class="ymm-select text-xs sm:w-52">
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
                <th class="py-2.5 pr-4 whitespace-nowrap">Hoa hồng (%)</th>
                <th class="py-2.5 whitespace-nowrap">Trạng thái</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="a in allAffiliates" :key="a.id" class="align-top">
                <td class="py-3.5 pr-4 whitespace-nowrap">
                  <strong class="text-[#0D2C54] block">{{ a.code }}</strong>
                  <select v-if="isDevelop && a.id !== currentAdmin?.id" :value="a.role"
                    :disabled="busyKey === `role:${a.id}`"
                    class="mt-1 border border-slate-300 rounded px-2 py-1 text-[11px] font-semibold bg-white text-[#0D2C54]"
                    @change="updateAffiliateRole(a, ($event.target as HTMLSelectElement).value)">
                    <option value="ctv">CTV</option>
                    <option value="staff">STAFF</option>
                    <option value="admin">ADMIN</option>
                    <option value="develop">DEVELOP</option>
                  </select>
                  <span v-else class="inline-block mt-1 text-[10px] font-bold uppercase px-2 py-0.5 rounded"
                    :class="a.role === 'develop' ? 'bg-[#C81E2B] text-white' : (a.role === 'admin' ? 'bg-[#0D2C54] text-white' : 'bg-slate-100 text-slate-600')">
                    {{ a.role }}
                  </span>
                </td>
                <td class="py-3.5 pr-4">
                  <strong class="text-slate-900 block">{{ a.full_name }}</strong>
                  <a :href="`tel:${a.phone}`" class="text-[#0D2C54] font-semibold tabular-nums no-underline block">{{
                    a.phone
                  }}</a>
                  <span class="text-[11px] text-slate-500 block">{{ a.email }}</span>
                </td>
                <td class="py-3.5 pr-4 whitespace-nowrap">
                  <span class="block">{{ a.job_type || '—' }}</span>
                  <span class="text-[11px] text-slate-500">{{ a.area || '—' }}</span>
                </td>
                <td class="py-3.5 pr-4 whitespace-nowrap">
                  <input :value="a.commission_rate" :disabled="busyKey === `rate:${a.id}`" type="number" min="0"
                    max="50" step="0.5"
                    class="w-20 min-h-[38px] border border-slate-300 rounded-lg px-2 text-xs font-semibold tabular-nums"
                    @change="updateAffiliateRate(a, ($event.target as HTMLInputElement).value)"> %
                </td>
                <td class="py-3.5 whitespace-nowrap">
                  <div class="flex items-center gap-1.5">
                    <select :value="a.status" :disabled="a.id === currentAdmin?.id || busyKey === `aff:${a.id}`"
                      class="min-h-[38px] w-32 border border-slate-300 rounded-lg px-2 text-xs font-semibold bg-white"
                      @change="updateAffiliateStatus(a, ($event.target as HTMLSelectElement).value)">
                      <option v-for="(label, key) in CTV_STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
                    </select>
                    <button type="button" class="btn-outline text-xs px-2.5 min-h-[38px]"
                      @click="selectedAffiliateId = a.id">Hồ sơ / Bank</button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="lg:hidden space-y-3">
          <div v-for="a in allAffiliates" :key="a.id"
            class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-4 space-y-3 text-xs">
            <div class="flex items-start justify-between gap-2">
              <div>
                <strong class="text-sm text-[#0D2C54] block">{{ a.full_name }}</strong>
                <span class="text-[11px] font-semibold text-slate-600">{{ a.code }} · {{ a.job_type || '—' }}</span>
              </div>
              <span class="px-2.5 py-1 rounded-full border text-[11px] font-semibold whitespace-nowrap"
                :class="CTV_STATUS_BADGE[a.status]">{{ CTV_STATUS_LABELS[a.status] }}</span>
            </div>
            <div class="bg-white rounded-lg p-3 border border-slate-200/80 space-y-1">
              <a :href="`tel:${a.phone}`" class="font-bold text-[#0D2C54] tabular-nums no-underline block">{{ a.phone
              }}</a>
              <p class="text-[11px] text-slate-500 m-0 truncate">{{ a.email }}</p>
            </div>
            <div class="grid grid-cols-2 gap-2.5">
              <div>
                <label class="text-[10px] text-slate-500 block mb-1">Hoa hồng (%)</label>
                <input :value="a.commission_rate" type="number" min="0" max="50" step="0.5"
                  class="w-full min-h-[44px] border border-slate-300 rounded-lg px-3 text-xs font-semibold tabular-nums bg-white"
                  @change="updateAffiliateRate(a, ($event.target as HTMLInputElement).value)">
              </div>
              <div>
                <label class="text-[10px] text-slate-500 block mb-1">Trạng thái</label>
                <select :value="a.status" :disabled="a.id === currentAdmin?.id"
                  class="w-full min-h-[44px] border border-slate-300 rounded-lg px-2.5 text-xs font-semibold bg-white"
                  @change="updateAffiliateStatus(a, ($event.target as HTMLSelectElement).value)">
                  <option v-for="(label, key) in CTV_STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
                </select>
              </div>
            </div>
          </div>
        </div>
        <div v-if="totalAffiliatePages > 1"
          class="flex items-center justify-between pt-3 border-t border-slate-200 text-xs">
          <span class="text-slate-500 tabular-nums">Trang {{ affiliatesPage }} / {{ totalAffiliatePages }} ({{
            affiliatesTotal }} CTV)</span>
          <div class="flex gap-2">
            <button type="button" :disabled="affiliatesPage <= 1" class="btn-outline text-xs px-3 min-h-[38px]"
              @click="changeListPage('affiliates', -1)">
              <ChevronLeft class="w-4 h-4" /> Trước
            </button>
            <button type="button" :disabled="affiliatesPage >= totalAffiliatePages"
              class="btn-outline text-xs px-3 min-h-[38px]" @click="changeListPage('affiliates', 1)">
              Sau
              <ChevronRight class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      <!-- TAB 3: Settlement (Atomic & Idempotent RPCs + Payout Requests Queue) -->
      <div v-else-if="activeTab === 'settlement'" class="space-y-5">
        <!-- Payout Requests Queue (P1-1) -->
        <div class="card-surface p-4 sm:p-5 space-y-4">
          <div>
            <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Yêu cầu rút tiền từ CTV ({{ payoutRequests.length
            }})
            </h2>
            <p class="text-xs text-slate-500 mt-0.5 m-0">Duyệt, từ chối hoặc xác nhận chuyển khoản (tự động ghi sổ cái
              &amp;
              biên nhận bất biến).</p>
          </div>
          <p v-if="payoutRequests.length === 0" class="text-xs text-slate-500 text-center py-4 m-0">Hiện chưa có yêu cầu
            rút
            tiền nào từ CTV.</p>
          <div v-else class="space-y-2.5">
            <div v-for="req in payoutRequests" :key="req.id"
              class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-3.5 text-xs flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3">
              <div class="space-y-1">
                <div class="flex flex-wrap items-center gap-2">
                  <strong class="text-[#0D2C54]">{{ req.affiliate_code }}</strong>
                  <span>{{ req.affiliate_name }}</span>
                  <strong class="text-[#15803D] tabular-nums">{{ formatCurrency(req.amount) }}</strong>
                  <span
                    class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-white border border-slate-200 uppercase">{{
                      req.status }}</span>
                </div>
                <p v-if="req.bank_snapshot?.bank_name" class="text-slate-600 m-0">
                  TK: {{ req.bank_snapshot.bank_name }} · <strong class="font-mono">{{ req.bank_snapshot.account_number
                  }}</strong> ({{ req.bank_snapshot.account_holder }})
                </p>
                <p class="text-[11px] text-slate-500 m-0">Gửi lúc: {{ formatDate(req.requested_at) }} <span
                    v-if="req.note">·
                    {{ req.note }}</span></p>
                <p v-if="req.reject_reason" class="text-[#C81E2B] font-semibold m-0">Lý do từ chối: {{ req.reject_reason
                }}
                </p>
              </div>
              <div v-if="req.status === 'requested' || req.status === 'approved'" class="flex flex-wrap gap-2 shrink-0">
                <button v-if="req.status === 'requested'" type="button" :disabled="busyKey === `req:${req.id}`"
                  class="min-h-[40px] px-3 rounded-lg bg-[#0D2C54] text-white text-xs font-semibold cursor-pointer"
                  @click="reviewPayoutRequest(req, 'approve')">Duyệt</button>
                <button type="button" :disabled="busyKey === `req:${req.id}`"
                  class="min-h-[40px] px-3 rounded-lg bg-[#15803D] text-white text-xs font-semibold cursor-pointer"
                  @click="reviewPayoutRequest(req, 'pay')">Chi trả ngay</button>
                <button type="button" :disabled="busyKey === `req:${req.id}`"
                  class="btn-outline min-h-[40px] px-3 text-xs text-[#C81E2B] border-[#C81E2B]/40"
                  @click="reviewPayoutRequest(req, 'reject')">Từ chối</button>
              </div>
            </div>
          </div>
        </div>

        <div class="card-surface p-4 sm:p-5 space-y-4">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div>
              <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Đối soát công nợ hoa hồng theo CTV</h2>
              <p class="text-xs text-slate-500 mt-0.5 m-0">Dữ liệu tính từ sổ cái DB. Chi trả nguyên tử có khóa
                idempotency
                &amp; mã giao dịch.</p>
            </div>
            <div class="flex flex-wrap gap-2 shrink-0">
              <button type="button" class="btn-outline text-xs px-3 min-h-[40px]" @click="exportSettlementCsv">
                <Download class="w-4 h-4" /> Xuất CSV
              </button>
              <button type="button" :disabled="busyKey === 'release'"
                class="btn-outline text-xs px-3.5 min-h-[40px] whitespace-nowrap" @click="runReleaseMatured">
                Mở khóa đơn hết hạn Hold
              </button>
            </div>
          </div>

          <p v-if="settlementRows.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">Chưa có phát sinh
            hoa hồng
            từ CTV.</p>
          <template v-else>
            <div class="hidden lg:block overflow-x-auto">
              <table class="w-full text-left border-collapse text-xs">
                <thead>
                  <tr class="border-b border-slate-200 text-slate-500 uppercase text-[11px]">
                    <th class="py-2.5 pr-4 whitespace-nowrap">CTV</th>
                    <th class="py-2.5 pr-4 whitespace-nowrap">Đang giữ (Hold)</th>
                    <th class="py-2.5 pr-4 whitespace-nowrap">Khả dụng — Chờ trả</th>
                    <th class="py-2.5 pr-4 whitespace-nowrap">Đã thanh toán</th>
                    <th class="py-2.5 whitespace-nowrap">Thao tác</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-100">
                  <tr v-for="r in settlementRows" :key="r.affiliate_id" class="align-top">
                    <td class="py-3.5 pr-4 whitespace-nowrap">
                      <strong class="text-[#0D2C54] block">{{ r.code }}</strong>
                      <span class="text-slate-600 block">{{ r.full_name }}</span>
                    </td>
                    <td class="py-3.5 pr-4 whitespace-nowrap tabular-nums">
                      <strong class="text-[#0D2C54] block">{{ formatCurrency(r.holding_amount) }}</strong>
                      <span class="text-[11px] text-slate-500">{{ r.holding_count }} đơn</span>
                    </td>
                    <td class="py-3.5 pr-4 whitespace-nowrap tabular-nums">
                      <strong class="block"
                        :class="r.net_available_balance < 0 ? 'text-[#C81E2B]' : 'text-[#0D2C54]'">{{
                          formatCurrency(r.net_available_balance) }}</strong>
                      <span class="text-[11px] text-slate-500">{{ r.available_count }} đơn</span>
                    </td>
                    <td class="py-3.5 pr-4 whitespace-nowrap font-bold text-[#15803D] tabular-nums">{{
                      formatCurrency(r.paid_amount) }}</td>
                    <td class="py-3.5 whitespace-nowrap">
                      <div class="flex items-center gap-2">
                        <button v-if="r.holding_count > 0" type="button"
                          :disabled="busyKey === `approve:${r.affiliate_id}`"
                          class="min-h-[36px] px-3 rounded-lg bg-[#0D2C54] text-white text-[11px] font-semibold cursor-pointer"
                          @click="approveCommission(r)">
                          Duyệt sớm
                        </button>
                        <button v-if="r.available_count > 0 && r.net_available_balance > 0" type="button"
                          :disabled="busyKey === `pay:${r.affiliate_id}`"
                          class="min-h-[36px] px-3 rounded-lg bg-[#15803D] text-white text-[11px] font-semibold cursor-pointer"
                          @click="payCommission(r)">
                          Xác nhận thanh toán
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="lg:hidden space-y-3">
              <div v-for="r in settlementRows" :key="r.affiliate_id"
                class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-4 space-y-3 text-xs">
                <div><strong class="text-sm text-[#0D2C54]">{{ r.code }}</strong> · <span class="font-semibold">{{
                  r.full_name }}</span></div>
                <div class="grid grid-cols-3 gap-2 text-center bg-white rounded-lg p-2.5 border border-slate-200/80">
                  <div><span class="text-[10px] text-slate-500 block">Đang giữ</span><strong
                      class="text-[#0D2C54] tabular-nums">{{ formatCurrency(r.holding_amount) }}</strong></div>
                  <div><span class="text-[10px] text-slate-500 block">Khả dụng</span><strong
                      class="text-[#C81E2B] tabular-nums">{{ formatCurrency(r.net_available_balance) }}</strong></div>
                  <div><span class="text-[10px] text-slate-500 block">Đã trả</span><strong
                      class="text-[#15803D] tabular-nums">{{ formatCurrency(r.paid_amount) }}</strong></div>
                </div>
                <div class="flex flex-col gap-2">
                  <button v-if="r.holding_count > 0" type="button" :disabled="busyKey === `approve:${r.affiliate_id}`"
                    class="min-h-[44px] w-full rounded-lg bg-[#0D2C54] text-white text-xs font-semibold"
                    @click="approveCommission(r)">Duyệt mở khóa ({{ r.holding_count }} đơn)</button>
                  <button v-if="r.available_count > 0 && r.net_available_balance > 0" type="button"
                    :disabled="busyKey === `pay:${r.affiliate_id}`"
                    class="min-h-[44px] w-full rounded-lg bg-[#15803D] text-white text-xs font-semibold"
                    @click="payCommission(r)">Xác nhận thanh toán {{ formatCurrency(r.net_available_balance) }}</button>
                </div>
              </div>
            </div>
          </template>
        </div>

        <div class="card-surface p-4 sm:p-5 space-y-4">
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Lịch sử đã thanh toán hoa hồng (bất biến)</h2>
            <button type="button" class="btn-outline text-xs px-3 min-h-[38px]" @click="exportPayoutsCsv">
              <Download class="w-4 h-4" /> Xuất CSV
            </button>
          </div>
          <p v-if="allPayouts.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">Chưa có giao dịch thanh
            toán
            hoa hồng nào.</p>
          <div v-else class="space-y-2.5">
            <div v-for="p in allPayouts" :key="p.id"
              class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-3.5 text-xs flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
              <div>
                <strong class="text-[#0D2C54]">{{ p.affiliate_code }}</strong> · <span>{{ p.order_count }} đơn</span> ·
                <span class="text-slate-500 tabular-nums">{{ formatDate(p.paid_at) }}</span>
                <p v-if="p.transaction_ref" class="text-[11px] text-slate-700 m-0">Mã GD: <strong>{{ p.transaction_ref
                }}</strong></p>
                <p class="text-slate-600 m-0 mt-0.5">{{ p.note || '—' }}</p>
              </div>
              <strong class="text-sm text-[#15803D] tabular-nums shrink-0">{{ formatCurrency(p.net_amount ?? p.amount)
              }}</strong>
            </div>
          </div>
          <div v-if="totalPayoutPages > 1"
            class="flex items-center justify-between pt-3 border-t border-slate-200 text-xs">
            <span class="text-slate-500 tabular-nums">Trang {{ payoutsPage }} / {{ totalPayoutPages }} ({{
              payoutsTotal }} giao dịch)</span>
            <div class="flex gap-2">
              <button type="button" :disabled="payoutsPage <= 1" class="btn-outline text-xs px-3 min-h-[38px]"
                @click="changeListPage('payouts', -1)">
                <ChevronLeft class="w-4 h-4" /> Trước
              </button>
              <button type="button" :disabled="payoutsPage >= totalPayoutPages"
                class="btn-outline text-xs px-3 min-h-[38px]" @click="changeListPage('payouts', 1)">
                Sau
                <ChevronRight class="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- TAB 4: Leads -->
      <div v-else-if="activeTab === 'leads'" class="card-surface p-4 sm:p-5 space-y-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Yêu cầu tư vấn &amp; đo phom xe</h2>
          <select v-model="leadStatusFilter" aria-label="Lọc theo trạng thái"
            class="min-h-[44px] sm:min-h-[38px] border border-slate-300 rounded-lg px-3 text-xs font-semibold bg-white">
            <option value="">Tất cả trạng thái</option>
            <option value="new">Chưa gọi</option>
            <option value="contacted">Đã tư vấn</option>
            <option value="closed">Đã chốt / Đóng</option>
          </select>
        </div>
        <p v-if="allLeads.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">Chưa có yêu cầu tư vấn nào.
        </p>
        <div v-else class="space-y-3">
          <div v-for="l in allLeads" :key="l.id"
            class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-4 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3 text-xs">
            <div class="space-y-1">
              <div class="flex flex-wrap items-center gap-2">
                <strong class="text-slate-900">{{ l.customer_name }}</strong>
                <a :href="`tel:${l.phone}`" class="font-bold text-[#0D2C54] tabular-nums no-underline">{{ l.phone }}</a>
                <span class="text-[11px] text-slate-500 tabular-nums">{{ formatDate(l.created_at) }}</span>
              </div>
              <p class="m-0"><strong class="text-[#0D2C54]">{{ l.vehicle || 'Chưa chọn xe' }}</strong> — {{ l.message ||
                '—'
              }}</p>
            </div>
            <select :value="l.status" :disabled="busyKey === `lead:${l.id}`"
              class="min-h-[44px] lg:min-h-[38px] lg:w-40 border border-slate-300 rounded-lg px-3 text-xs font-semibold bg-white shrink-0"
              @change="updateLeadStatus(l, ($event.target as HTMLSelectElement).value)">
              <option value="new">Chưa gọi</option>
              <option value="contacted">Đã tư vấn</option>
              <option value="closed">Đã chốt / Đóng</option>
            </select>
          </div>
        </div>
        <div v-if="totalLeadPages > 1" class="flex items-center justify-between pt-3 border-t border-slate-200 text-xs">
          <span class="text-slate-500 tabular-nums">Trang {{ leadsPage }} / {{ totalLeadPages }} ({{ leadsTotal }}
            yêu cầu)</span>
          <div class="flex gap-2">
            <button type="button" :disabled="leadsPage <= 1" class="btn-outline text-xs px-3 min-h-[38px]"
              @click="changeListPage('leads', -1)">
              <ChevronLeft class="w-4 h-4" /> Trước
            </button>
            <button type="button" :disabled="leadsPage >= totalLeadPages" class="btn-outline text-xs px-3 min-h-[38px]"
              @click="changeListPage('leads', 1)">
              Sau
              <ChevronRight class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      <!-- TAB 5: Reports (P2-3) -->
      <div v-else-if="activeTab === 'reports'" class="card-surface overflow-hidden">
        <AdminReportsTab />
      </div>

      <!-- TAB 6: Customers (P2-5) -->
      <div v-else-if="activeTab === 'customers'" class="card-surface overflow-hidden">
        <AdminCustomersTab />
      </div>

      <!-- TAB 7: Catalog, Coupons & Rules (P1-7) -->
      <div v-else-if="activeTab === 'catalog'" class="card-surface overflow-hidden">
        <AdminCatalogTab />
      </div>

      <!-- TAB 8: Audit Logs (P1-9) -->
      <div v-else class="card-surface overflow-hidden">
        <AdminAuditLogsTab />
      </div>
    </section>

    <AdminOrderDetailModal :order-id="selectedOrderId" @close="selectedOrderId = null" @updated="loadAllData" />
    <AdminAffiliateDetailModal :affiliate-id="selectedAffiliateId" @close="selectedAffiliateId = null"
      @updated="loadAllData" />

    <!-- Create Account Modal (Develop only) -->
    <Teleport to="body">
      <div v-if="showCreateModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-slate-900/60 backdrop-blur-[2px]" @click="showCreateModal = false" />
        <div
          class="bg-white border border-slate-200 rounded-2xl w-full max-w-md p-5 sm:p-6 relative z-10 shadow-2xl space-y-4 max-h-[90vh] overflow-y-auto">
          <div class="flex items-center justify-between border-b border-slate-200 pb-3">
            <h3 class="text-base font-bold uppercase text-[#0D2C54] m-0">Tạo tài khoản hệ thống</h3>
            <button type="button" class="icon-touch-btn text-slate-500" aria-label="Đóng"
              @click="showCreateModal = false">
              <X class="w-5 h-5" />
            </button>
          </div>
          <p v-if="createErr"
            class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3 py-2 m-0">
            {{
              createErr }}</p>
          <form class="space-y-3" @submit.prevent="handleCreateAccount">
            <div class="grid grid-cols-2 gap-3">
              <div class="space-y-1">
                <label class="text-xs font-semibold text-slate-700 block">Vai trò *</label>
                <select v-model="newAcc.role" class="ymm-select text-xs">
                  <option value="admin">Admin (Quản trị)</option>
                  <option value="staff">Staff (Nhân viên)</option>
                  <option value="ctv">CTV (Cộng tác viên)</option>
                  <option value="develop">Develop (Toàn quyền)</option>
                </select>
              </div>
              <div class="space-y-1">
                <label class="text-xs font-semibold text-slate-700 block">Hoa hồng (%)</label>
                <input v-model="newAcc.rate" type="number" min="0" max="50" step="0.5"
                  class="field-input text-xs tabular-nums">
              </div>
            </div>
            <div class="space-y-1">
              <label class="text-xs font-semibold text-slate-700 block">Họ và tên *</label>
              <input v-model="newAcc.name" type="text" required placeholder="VD: Nguyễn Văn Admin"
                class="field-input text-xs">
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div class="space-y-1">
                <label class="text-xs font-semibold text-slate-700 block">Số điện thoại *</label>
                <input v-model="newAcc.phone" type="tel" required placeholder="0963294492" class="field-input text-xs">
              </div>
              <div class="space-y-1">
                <label class="text-xs font-semibold text-slate-700 block">Mã định danh *</label>
                <input v-model="newAcc.code" type="text" required placeholder="VD: ADMIN02"
                  class="field-input text-xs uppercase">
              </div>
            </div>
            <div class="space-y-1">
              <label class="text-xs font-semibold text-slate-700 block">Email đăng nhập *</label>
              <input v-model="newAcc.email" type="email" required placeholder="email@domain.com"
                class="field-input text-xs">
            </div>
            <div class="space-y-1">
              <label class="text-xs font-semibold text-slate-700 block">Mật khẩu (≥ 8 ký tự) *</label>
              <input v-model="newAcc.password" type="password" required minlength="8" placeholder="Nhập mật khẩu..."
                class="field-input text-xs">
            </div>
            <button type="submit" :disabled="isCreating" class="btn-cta w-full text-xs">
              {{ isCreating ? 'ĐANG TẠO TÀI KHOẢN...' : 'TẠO &amp; KÍCH HOẠT NGAY' }}
            </button>
          </form>
        </div>
      </div>
    </Teleport>
  </main>
</template>
