<script setup lang="ts">
import {
  UserCheck, Clock, Shield, RefreshCw, Link2, Copy, AlertTriangle,
  ChevronLeft, ChevronRight, Download, Wallet, UserCog, KeyRound, MessageSquare
} from 'lucide-vue-next';

definePageMeta({ middleware: 'auth-ctv' });

useSeoMeta({
  title: 'Cổng Cộng Tác Viên (CTV Portal) | Trung Thành Auto',
  robots: 'noindex, nofollow'
});

const router = useRouter();
const { supabase, isConfigured } = useSupabase();
const { buildShareUrl } = useAffiliate();
const { showToast } = useToast();

const viewState = ref<'loading' | 'login' | 'pending' | 'dashboard'>('loading');
const loginEmail = ref('');
const loginPassword = ref('');
const loginError = ref('');
const isLoggingIn = ref(false);
const isResettingPw = ref(false);
const resetMessage = ref('');

const profile = ref<any>(null);
const bankAccount = ref<any>(null);
const settings = ref<Record<string, any>>({ min_payout_amount: 200000, commission_hold_days: 7 });
const loadError = ref('');
const isLoadingData = ref(false);
const busyKey = ref('');

const overview = ref({
  total_orders: 0,
  clicks_count: 0,
  conversion_rate: 0,
  pending_commission: 0,
  holding_commission: 0,
  available_commission: 0,
  locked_payout_amount: 0,
  withdrawable_commission: 0,
  paid_commission: 0,
  bank_status: 'none'
});

const myOrders = ref<any[]>([]);
const ordersTotal = ref(0);
const ordersPage = ref(1);
const pageSize = 20;
const myPayouts = ref<any[]>([]);
const myPayoutRequests = ref<any[]>([]);
const myLeads = ref<any[]>([]);

const activeTab = ref<'orders' | 'payouts' | 'withdraw' | 'leads' | 'profile'>('orders');
const statusFilter = ref('');
const searchOrder = ref('');

// Withdraw form
const withdrawAmount = ref<number | ''>('');
const withdrawNote = ref('');

// Profile & bank forms
const profileForm = ref({ full_name: '', phone: '', zalo: '', area: '', job_type: '' });
const bankForm = ref({ bank_name: '', account_number: '', account_holder: '', branch: '' });
const passwordForm = ref({ currentPassword: '', newPassword: '', confirmPassword: '' });

// Link generator
const shareBrand = ref('');
const shareModel = ref('');
const shareModels = computed(() => (shareBrand.value ? getModelsWithMeta(shareBrand.value) : []));
watch(shareBrand, () => { shareModel.value = ''; });

const shareUrl = computed(() => {
  const code = profile.value?.code || '';
  let path = '/';
  if (shareBrand.value && shareModel.value) {
    path = `/chi-tiet?hang=${shareBrand.value}&xe=${shareModel.value}`;
  } else if (shareBrand.value) {
    path = `/san-pham?hang=${shareBrand.value}`;
  }
  return buildShareUrl(path, code);
});

const STATUS_LABELS: Record<string, string> = {
  new: 'Mới',
  confirmed: 'Đã xác nhận',
  shipping: 'Đang giao',
  completed: 'Hoàn thành',
  cancelled: 'Đã hủy',
  returned: 'Hoàn trả'
};

const STATUS_BADGE: Record<string, string> = {
  new: 'bg-sky-50 text-sky-700 border-sky-200',
  confirmed: 'bg-[#EFF4FA] text-[#0D2C54] border-[#0D2C54]/20',
  shipping: 'bg-amber-50 text-amber-700 border-amber-200',
  completed: 'bg-green-50 text-[#15803D] border-green-200',
  cancelled: 'bg-[#FEF2F2] text-[#C81E2B] border-[#C81E2B]/25',
  returned: 'bg-purple-50 text-purple-700 border-purple-200'
};

const COMM_LABELS: Record<string, string> = {
  pending: 'Tạm tính',
  holding: 'Đang giữ (hold)',
  available: 'Khả dụng (rút được)',
  approved: 'Khả dụng (rút được)',
  paid: 'Đã thanh toán',
  reversed: 'Đã thu hồi'
};

const REQ_LABELS: Record<string, string> = {
  requested: 'Chờ duyệt',
  approved: 'Đã duyệt (chờ CK)',
  rejected: 'Từ chối',
  paid: 'Đã chi trả'
};

const REQ_BADGE: Record<string, string> = {
  requested: 'bg-amber-50 text-amber-700 border-amber-200',
  approved: 'bg-sky-50 text-sky-700 border-sky-200',
  rejected: 'bg-[#FEF2F2] text-[#C81E2B] border-[#C81E2B]/25',
  paid: 'bg-green-50 text-[#15803D] border-green-200'
};

const BANK_STATUS_TEXT: Record<string, string> = {
  none: 'Chưa cập nhật',
  pending: 'Đang chờ Admin xác minh',
  verified: 'Đã xác minh',
  rejected: 'Bị từ chối — cần cập nhật lại'
};

const minPayoutAmount = computed(() => Number(settings.value?.min_payout_amount || 200000));
const hasOpenPayoutRequest = computed(() =>
  myPayoutRequests.value.some((r) => r.status === 'requested' || r.status === 'approved')
);
const totalPages = computed(() => Math.max(1, Math.ceil(ordersTotal.value / pageSize)));

const formatDate = (iso: string) =>
  iso ? new Date(iso).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';

const pendingTitle = computed(() => {
  const map: Record<string, string> = {
    pending: 'Tài khoản đang chờ duyệt',
    suspended: 'Tài khoản đang tạm khóa',
    cancelled: 'Tài khoản CTV đã bị hủy'
  };
  return profile.value ? (map[profile.value.status] || 'Tài khoản chưa kích hoạt') : 'Chưa có hồ sơ CTV';
});

const loadProfileAndBank = async () => {
  if (!supabase) return;
  const { data, error } = await supabase.rpc('ctv_get_profile');
  if (error || !data) return;
  if (data.affiliate) {
    profile.value = { ...profile.value, ...data.affiliate };
    profileForm.value = {
      full_name: data.affiliate.full_name || '',
      phone: data.affiliate.phone || '',
      zalo: data.affiliate.zalo || '',
      area: data.affiliate.area || '',
      job_type: data.affiliate.job_type || ''
    };
  }
  bankAccount.value = data.bank || null;
  if (data.bank) {
    bankForm.value = {
      bank_name: data.bank.bank_name || '',
      account_number: data.bank.account_number || '',
      account_holder: data.bank.account_holder || '',
      branch: data.bank.branch || ''
    };
  }
  if (data.settings) {
    settings.value = data.settings;
  }
};

const loadMyData = async () => {
  if (!supabase || !profile.value) return;
  isLoadingData.value = true;
  loadError.value = '';
  try {
    const code = String(profile.value.code || '').toUpperCase();
    const [ovRes, ordRes, payRes, reqRes, leadRes] = await Promise.all([
      supabase.rpc('ctv_overview'),
      supabase.rpc('ctv_list_orders', {
        p_status: statusFilter.value || null,
        p_search: searchOrder.value.trim() || null,
        p_page: ordersPage.value,
        p_page_size: pageSize
      }),
      supabase
        .from('commission_payouts')
        .select('id, order_count, amount, gross_amount, tax_amount, net_amount, transaction_ref, note, paid_at')
        .eq('affiliate_code', code)
        .order('paid_at', { ascending: false })
        .limit(100),
      supabase.rpc('ctv_list_payout_requests'),
      supabase.rpc('ctv_list_leads', { p_page: 1, p_page_size: 50 }),
      loadProfileAndBank()
    ]);

    if (ovRes.error) throw ovRes.error;
    if (ordRes.error) throw ordRes.error;
    if (payRes.error) throw payRes.error;

    if (ovRes.data) {
      overview.value = { ...overview.value, ...ovRes.data };
    }
    myOrders.value = Array.isArray(ordRes.data?.items) ? ordRes.data.items : [];
    ordersTotal.value = Number(ordRes.data?.total || 0);
    myPayouts.value = payRes.data || [];
    myPayoutRequests.value = Array.isArray(reqRes.data) ? reqRes.data : [];
    myLeads.value = Array.isArray(leadRes.data?.items) ? leadRes.data.items : [];
  } catch (err: any) {
    loadError.value = err?.message || 'Không thể tải dữ liệu CTV. Vui lòng thử lại.';
  } finally {
    isLoadingData.value = false;
  }
};

let searchTimer: ReturnType<typeof setTimeout> | null = null;
watch([statusFilter, searchOrder], () => {
  ordersPage.value = 1;
  if (searchTimer) clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    if (viewState.value === 'dashboard') loadMyData();
  }, 250);
});

const goToPage = (p: number) => {
  if (p < 1 || p > totalPages.value) return;
  ordersPage.value = p;
  loadMyData();
};

const checkSession = async () => {
  if (!isConfigured || !supabase) {
    viewState.value = 'login';
    loginError.value = 'Chưa cấu hình kết nối Supabase.';
    return;
  }
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    viewState.value = 'login';
    return;
  }

  const { data: aff } = await supabase
    .from('affiliates')
    .select('*')
    .eq('user_id', session.user.id)
    .maybeSingle();

  profile.value = aff;
  if (!aff || aff.status !== 'active') {
    viewState.value = 'pending';
    return;
  }

  viewState.value = 'dashboard';
  await loadMyData();
};

const handleLogin = async () => {
  if (!supabase) return;
  loginError.value = '';
  resetMessage.value = '';
  isLoggingIn.value = true;
  const { error } = await supabase.auth.signInWithPassword({
    email: loginEmail.value.trim(),
    password: loginPassword.value
  });
  isLoggingIn.value = false;
  if (error) {
    loginError.value = 'Email hoặc mật khẩu không đúng.';
    return;
  }
  await checkSession();
};

const handleForgotPassword = async () => {
  if (!supabase) return;
  loginError.value = '';
  resetMessage.value = '';
  const email = loginEmail.value.trim();
  if (!email) {
    loginError.value = 'Vui lòng nhập Email tài khoản trước khi nhấn Quên mật khẩu.';
    return;
  }
  isResettingPw.value = true;
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}/ctv`
  });
  isResettingPw.value = false;
  if (error) {
    loginError.value = error.message || 'Không gửi được email khôi phục mật khẩu.';
    return;
  }
  resetMessage.value = 'Đã gửi liên kết đặt lại mật khẩu tới email của bạn. Vui lòng kiểm tra hộp thư.';
};

const handleLogout = async () => {
  if (!supabase) return;
  await supabase.auth.signOut();
  profile.value = null;
  viewState.value = 'login';
};

const copyShareLink = async () => {
  try {
    await navigator.clipboard.writeText(shareUrl.value);
    showToast('Đã sao chép link giới thiệu!');
  } catch {
    showToast('Không thể sao chép tự động, vui lòng copy thủ công.');
  }
};

const submitWithdrawRequest = async () => {
  if (!supabase) return;
  const amt = Number(withdrawAmount.value || 0);
  if (amt < minPayoutAmount.value) {
    showToast(`Số tiền rút tối thiểu là ${formatCurrency(minPayoutAmount.value)}.`);
    return;
  }
  if (amt > overview.value.withdrawable_commission) {
    showToast('Số tiền vượt quá số dư khả dụng.');
    return;
  }
  busyKey.value = 'withdraw';
  const { error } = await supabase.rpc('ctv_request_payout', {
    p_amount: amt,
    p_note: withdrawNote.value.trim() || null
  });
  busyKey.value = '';
  if (error) {
    showToast(error.message || 'Không gửi được yêu cầu rút tiền.');
    return;
  }
  withdrawAmount.value = '';
  withdrawNote.value = '';
  showToast('Đã gửi yêu cầu rút tiền thành công!');
  await loadMyData();
};

const saveProfile = async () => {
  if (!supabase) return;
  busyKey.value = 'profile';
  const { error } = await supabase.rpc('ctv_update_profile', {
    p_full_name: profileForm.value.full_name,
    p_phone: profileForm.value.phone,
    p_zalo: profileForm.value.zalo,
    p_area: profileForm.value.area,
    p_job_type: profileForm.value.job_type
  });
  busyKey.value = '';
  if (error) {
    showToast(error.message || 'Không cập nhật được hồ sơ.');
    return;
  }
  showToast('Đã cập nhật hồ sơ cá nhân.');
  await loadProfileAndBank();
};

const saveBank = async () => {
  if (!supabase) return;
  busyKey.value = 'bank';
  const { error } = await supabase.rpc('ctv_update_bank_account', {
    p_bank_name: bankForm.value.bank_name,
    p_account_number: bankForm.value.account_number,
    p_account_holder: bankForm.value.account_holder,
    p_branch: bankForm.value.branch
  });
  busyKey.value = '';
  if (error) {
    showToast(error.message || 'Không cập nhật được tài khoản ngân hàng.');
    return;
  }
  showToast('Đã lưu tài khoản ngân hàng. Chờ Admin xác minh trước khi rút tiền.');
  await loadMyData();
};

const changePassword = async () => {
  if (!supabase || !profile.value?.email) return;
  if (!passwordForm.value.currentPassword) {
    showToast('Vui lòng nhập mật khẩu hiện tại.');
    return;
  }
  if (passwordForm.value.newPassword.length < 8) {
    showToast('Mật khẩu mới phải có ít nhất 8 ký tự.');
    return;
  }
  if (passwordForm.value.newPassword !== passwordForm.value.confirmPassword) {
    showToast('Xác nhận mật khẩu chưa khớp.');
    return;
  }
  if (passwordForm.value.newPassword === passwordForm.value.currentPassword) {
    showToast('Mật khẩu mới phải khác mật khẩu hiện tại.');
    return;
  }
  busyKey.value = 'password';
  const { error: verifyErr } = await supabase.auth.signInWithPassword({
    email: profile.value.email,
    password: passwordForm.value.currentPassword
  });
  if (verifyErr) {
    busyKey.value = '';
    showToast('Mật khẩu hiện tại không đúng.');
    return;
  }
  const { error } = await supabase.auth.updateUser({
    password: passwordForm.value.newPassword
  });
  busyKey.value = '';
  if (error) {
    showToast(error.message || 'Không đổi được mật khẩu.');
    return;
  }
  passwordForm.value = { currentPassword: '', newPassword: '', confirmPassword: '' };
  showToast('Đã đổi mật khẩu thành công!');
};

const exportOrdersCsv = () => {
  if (!myOrders.value.length) {
    showToast('Không có dữ liệu đơn hàng để xuất.');
    return;
  }
  exportToCsv(
    `ctv-don-hang-${profile.value?.code || 'export'}.csv`,
    ['Mã đơn', 'Khách hàng (đã ẩn)', 'Trạng thái đơn', 'Giá trị đơn', 'Tỷ lệ HH (%)', 'Hoa hồng', 'Trạng thái HH', 'Ngày tạo'],
    myOrders.value.map((o) => [
      o.order_code,
      o.customer_name_masked || '',
      STATUS_LABELS[o.status] || o.status,
      o.total,
      o.commission_rate,
      o.commission_amount,
      COMM_LABELS[o.commission_status] || o.commission_status,
      formatDate(o.created_at)
    ])
  );
};

const exportPayoutsCsv = () => {
  if (!myPayouts.value.length) {
    showToast('Chưa có dữ liệu chi trả để xuất.');
    return;
  }
  exportToCsv(
    `ctv-chi-tra-${profile.value?.code || 'export'}.csv`,
    ['Ngày chi trả', 'Số đơn', 'Tổng trước thuế', 'Thuế TNCN', 'Thực nhận', 'Mã giao dịch', 'Ghi chú'],
    myPayouts.value.map((p) => [
      formatDate(p.paid_at),
      p.order_count,
      p.gross_amount ?? p.amount,
      p.tax_amount ?? 0,
      p.net_amount ?? p.amount,
      p.transaction_ref || '',
      p.note || ''
    ])
  );
};

onMounted(() => {
  checkSession();
});
</script>

<template>
  <main id="main-content" class="container-app py-6 md:py-10 min-h-[70vh]">
    <!-- Loading -->
    <div v-if="viewState === 'loading'" class="card-surface p-10 text-center max-w-md mx-auto">
      <div class="w-10 h-10 rounded-full border-4 border-[#0D2C54]/20 border-t-[#0D2C54] animate-spin mx-auto mb-3" />
      <p class="text-sm text-slate-600 m-0">Đang kiểm tra phiên đăng nhập CTV...</p>
    </div>

    <!-- Login View -->
    <section v-else-if="viewState === 'login'" class="max-w-md mx-auto">
      <div class="card-surface p-6 md:p-8 space-y-5">
        <div class="text-center space-y-1.5">
          <div class="w-12 h-12 rounded-xl bg-[#0D2C54] text-white flex items-center justify-center mx-auto">
            <UserCheck class="w-6 h-6" />
          </div>
          <h1 class="text-xl font-extrabold text-[#0D2C54] uppercase tracking-tight m-0">Đăng Nhập CTV</h1>
          <p class="text-xs text-slate-500 m-0">Theo dõi đơn hàng, lượt click, hoa hồng và rút tiền.</p>
        </div>

        <p v-if="loginError" role="alert" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3.5 py-2.5 m-0">
          {{ loginError }}
        </p>
        <p v-if="resetMessage" role="status" class="text-xs font-semibold text-[#15803D] bg-green-50 border border-green-200 rounded-lg px-3.5 py-2.5 m-0">
          {{ resetMessage }}
        </p>

        <form class="space-y-4" @submit.prevent="handleLogin">
          <div class="space-y-1.5">
            <label for="ctv-login-email" class="text-xs font-semibold text-slate-700 block">Email tài khoản</label>
            <input id="ctv-login-email" v-model="loginEmail" type="email" required placeholder="ctv@example.com" class="field-input">
          </div>
          <div class="space-y-1.5">
            <div class="flex items-center justify-between">
              <label for="ctv-login-password" class="text-xs font-semibold text-slate-700 block">Mật khẩu</label>
              <button
                type="button"
                :disabled="isResettingPw"
                class="text-xs font-semibold text-[#0D2C54] hover:underline bg-transparent border-0 cursor-pointer p-0 min-h-[32px]"
                @click="handleForgotPassword"
              >
                {{ isResettingPw ? 'Đang gửi...' : 'Quên mật khẩu?' }}
              </button>
            </div>
            <input id="ctv-login-password" v-model="loginPassword" type="password" required placeholder="••••••••" class="field-input">
          </div>
          <button type="submit" :disabled="isLoggingIn" class="btn-cta w-full text-sm">
            {{ isLoggingIn ? 'ĐANG ĐĂNG NHẬP...' : 'ĐĂNG NHẬP CỔNG CTV' }}
          </button>
        </form>

        <div class="pt-3 border-t border-slate-100 text-center space-y-2">
          <p class="text-xs text-slate-600 m-0">
            Chưa có tài khoản CTV? <NuxtLink to="/cong-tac-vien" class="font-bold text-[#C81E2B] hover:underline">Đăng ký miễn phí ngay</NuxtLink>
          </p>
        </div>
      </div>
    </section>

    <!-- Pending / Suspended View -->
    <section v-else-if="viewState === 'pending'" class="max-w-lg mx-auto">
      <div class="card-surface p-6 md:p-8 text-center space-y-4">
        <div class="w-14 h-14 rounded-full bg-amber-50 border border-amber-200 text-amber-600 flex items-center justify-center mx-auto">
          <Clock class="w-7 h-7" />
        </div>
        <h2 class="text-lg font-extrabold text-[#0D2C54] uppercase m-0">{{ pendingTitle }}</h2>
        <p class="text-sm text-slate-600 leading-relaxed m-0">
          <template v-if="profile?.status === 'pending'">
            Hồ sơ đăng ký CTV (mã <strong class="text-[#0D2C54]">{{ profile.code }}</strong>) đang chờ Admin xét duyệt. Vui lòng liên hệ Zalo 0963 294 492 để được duyệt nhanh trong ngày.
          </template>
          <template v-else-if="profile?.status === 'suspended' || profile?.status === 'cancelled'">
            Tài khoản CTV (mã <strong>{{ profile.code }}</strong>) hiện đang tạm ngưng.
            <span v-if="profile.reject_reason" class="block mt-2 text-xs font-semibold text-[#C81E2B]">Lý do: {{ profile.reject_reason }}</span>
          </template>
          <template v-else>
            Tài khoản đăng nhập hiện chưa liên kết với hồ sơ CTV nào.
          </template>
        </p>
        <div class="flex flex-wrap justify-center gap-3 pt-2">
          <a href="https://zalo.me/0963294492" target="_blank" rel="noopener" class="btn-cta text-xs px-5 no-underline">NHẮN ZALO HỖ TRỢ</a>
          <button type="button" class="btn-outline text-xs px-5" @click="handleLogout">Đăng xuất</button>
        </div>
      </div>
    </section>

    <!-- Active CTV Dashboard -->
    <section v-else class="space-y-6">
      <!-- Top Bar -->
      <div class="card-surface p-5 flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div class="space-y-1">
          <div class="flex flex-wrap items-center gap-2">
            <span class="px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-green-50 text-[#15803D] border border-green-200">CTV Đang hoạt động</span>
            <span class="px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-[#0D2C54] text-white tabular-nums">Mã: {{ profile?.code }}</span>
            <span class="px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-[#FEF2F2] text-[#C81E2B] border border-[#C81E2B]/20 tabular-nums">Hoa hồng: {{ profile?.commission_rate || 10 }}%</span>
          </div>
          <h1 class="text-lg md:text-xl font-extrabold text-[#0D2C54] m-0">Xin chào, {{ profile?.full_name || profile?.email }}</h1>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <button v-if="['admin', 'develop', 'staff'].includes(profile?.role)" type="button" class="btn-outline text-xs px-3.5" @click="router.push('/admin')">
            <Shield class="w-4 h-4" /> Vào trang Quản trị
          </button>
          <button type="button" class="btn-outline text-xs px-3.5" :disabled="isLoadingData" @click="loadMyData">
            <RefreshCw class="w-4 h-4" :class="isLoadingData ? 'animate-spin' : ''" /> Làm mới
          </button>
          <button type="button" class="btn-outline text-xs px-3.5 text-[#C81E2B] border-[#C81E2B]/40 hover:bg-[#FEF2F2]" @click="handleLogout">
            Đăng xuất
          </button>
        </div>
      </div>

      <!-- Error Banner -->
      <div v-if="loadError" role="alert" class="card-surface p-4 border-[#C81E2B]/40 bg-[#FEF2F2] flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div class="flex items-center gap-2 text-xs font-semibold text-[#C81E2B]">
          <AlertTriangle class="w-4 h-4 shrink-0" />
          <span>{{ loadError }}</span>
        </div>
        <button type="button" class="btn-outline text-xs px-3.5 shrink-0" @click="loadMyData">Thử lại</button>
      </div>

      <!-- KPI Cards -->
      <div class="grid grid-cols-2 lg:grid-cols-6 gap-3 md:gap-4">
        <div class="card-surface p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Lượt click</p>
          <p class="text-xl font-extrabold text-[#0D2C54] mt-1 mb-0 tabular-nums">{{ overview.clicks_count }}</p>
          <p class="text-[11px] text-slate-400 m-0 mt-0.5 tabular-nums">Chuyển đổi: {{ overview.conversion_rate }}%</p>
        </div>
        <div class="card-surface p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Tổng đơn hàng</p>
          <p class="text-xl font-extrabold text-[#0D2C54] mt-1 mb-0 tabular-nums">{{ overview.total_orders }}</p>
          <p class="text-[11px] text-slate-400 m-0 mt-0.5">Không tính đơn hủy</p>
        </div>
        <div class="card-surface p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Tạm tính</p>
          <p class="text-xl font-extrabold text-amber-600 mt-1 mb-0 tabular-nums">{{ formatCurrency(overview.pending_commission) }}</p>
          <p class="text-[11px] text-slate-400 m-0 mt-0.5">Đơn chưa hoàn tất</p>
        </div>
        <div class="card-surface p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Đang giữ (Hold)</p>
          <p class="text-xl font-extrabold text-sky-700 mt-1 mb-0 tabular-nums">{{ formatCurrency(overview.holding_commission) }}</p>
          <p class="text-[11px] text-slate-400 m-0 mt-0.5">Chờ hết hạn đối soát</p>
        </div>
        <div class="card-surface p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Khả dụng</p>
          <p class="text-xl font-extrabold text-[#0D2C54] mt-1 mb-0 tabular-nums">{{ formatCurrency(overview.available_commission) }}</p>
          <p class="text-[11px] text-slate-400 m-0 mt-0.5">Rút được: {{ formatCurrency(overview.withdrawable_commission) }}</p>
        </div>
        <div class="card-surface p-4">
          <p class="text-[11px] font-bold uppercase text-slate-500 m-0">Đã chi trả</p>
          <p class="text-xl font-extrabold text-[#15803D] mt-1 mb-0 tabular-nums">{{ formatCurrency(overview.paid_commission) }}</p>
          <p class="text-[11px] text-slate-400 m-0 mt-0.5">Thực nhận vào TK</p>
        </div>
      </div>

      <!-- Share Link Builder -->
      <div class="card-surface p-5 space-y-4">
        <div class="flex items-center justify-between flex-wrap gap-2">
          <h2 class="text-sm font-extrabold uppercase text-[#0D2C54] m-0 flex items-center gap-2">
            <Link2 class="w-4 h-4 text-[#C81E2B]" /> Tạo Link Giới Thiệu Của Bạn
          </h2>
          <span class="text-xs text-slate-500">Khách vào link này được lưu mã CTV trong 30 ngày</span>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div class="space-y-1">
            <label for="ctv-share-brand" class="text-xs font-semibold text-slate-600 block">Chọn hãng xe (tuỳ chọn)</label>
            <select id="ctv-share-brand" v-model="shareBrand" class="field-input">
              <option value="">Trang chủ (tất cả xe)</option>
              <option v-for="b in BRANDS" :key="b.id" :value="b.id">{{ b.name }}</option>
            </select>
          </div>
          <div class="space-y-1">
            <label for="ctv-share-model" class="text-xs font-semibold text-slate-600 block">Chọn dòng xe (tuỳ chọn)</label>
            <select id="ctv-share-model" v-model="shareModel" :disabled="!shareBrand" class="field-input disabled:bg-slate-100">
              <option value="">Tất cả dòng xe của hãng</option>
              <option v-for="m in shareModels" :key="m.id" :value="m.id">{{ m.name }}</option>
            </select>
          </div>
          <div class="space-y-1">
            <label for="ctv-share-url" class="text-xs font-semibold text-slate-600 block">Link giới thiệu sẵn sàng chia sẻ</label>
            <div class="flex gap-2">
              <input id="ctv-share-url" :value="shareUrl" type="text" readonly class="field-input text-xs font-mono bg-slate-50">
              <button type="button" class="btn-cta text-xs px-4 shrink-0" @click="copyShareLink">
                <Copy class="w-4 h-4" /> Copy
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Tabs Container -->
      <div class="card-surface overflow-hidden">
        <div class="border-b border-slate-200 px-3 sm:px-5 flex items-center gap-1 overflow-x-auto no-scrollbar">
          <button
            type="button"
            class="px-3.5 py-3.5 text-xs sm:text-sm font-bold border-b-2 transition bg-transparent cursor-pointer whitespace-nowrap min-h-[44px]"
            :class="activeTab === 'orders' ? 'border-[#0D2C54] text-[#0D2C54]' : 'border-transparent text-slate-500 hover:text-slate-800'"
            @click="activeTab = 'orders'"
          >
            Đơn hàng ({{ ordersTotal }})
          </button>
          <button
            type="button"
            class="px-3.5 py-3.5 text-xs sm:text-sm font-bold border-b-2 transition bg-transparent cursor-pointer whitespace-nowrap min-h-[44px] flex items-center gap-1.5"
            :class="activeTab === 'withdraw' ? 'border-[#0D2C54] text-[#0D2C54]' : 'border-transparent text-slate-500 hover:text-slate-800'"
            @click="activeTab = 'withdraw'"
          >
            <Wallet class="w-4 h-4" /> Rút tiền ({{ myPayoutRequests.length }})
          </button>
          <button
            type="button"
            class="px-3.5 py-3.5 text-xs sm:text-sm font-bold border-b-2 transition bg-transparent cursor-pointer whitespace-nowrap min-h-[44px]"
            :class="activeTab === 'payouts' ? 'border-[#0D2C54] text-[#0D2C54]' : 'border-transparent text-slate-500 hover:text-slate-800'"
            @click="activeTab = 'payouts'"
          >
            Lịch sử chi trả ({{ myPayouts.length }})
          </button>
          <button
            type="button"
            class="px-3.5 py-3.5 text-xs sm:text-sm font-bold border-b-2 transition bg-transparent cursor-pointer whitespace-nowrap min-h-[44px] flex items-center gap-1.5"
            :class="activeTab === 'leads' ? 'border-[#0D2C54] text-[#0D2C54]' : 'border-transparent text-slate-500 hover:text-slate-800'"
            @click="activeTab = 'leads'"
          >
            <MessageSquare class="w-4 h-4" /> Khách tư vấn ({{ myLeads.length }})
          </button>
          <button
            type="button"
            class="px-3.5 py-3.5 text-xs sm:text-sm font-bold border-b-2 transition bg-transparent cursor-pointer whitespace-nowrap min-h-[44px] flex items-center gap-1.5"
            :class="activeTab === 'profile' ? 'border-[#0D2C54] text-[#0D2C54]' : 'border-transparent text-slate-500 hover:text-slate-800'"
            @click="activeTab = 'profile'"
          >
            <UserCog class="w-4 h-4" /> Hồ sơ &amp; Ngân hàng
          </button>
        </div>

        <!-- Tab 1: Orders -->
        <div v-if="activeTab === 'orders'" class="p-4 sm:p-5 space-y-4">
          <div class="flex flex-col sm:flex-row gap-3">
            <input v-model="searchOrder" type="text" placeholder="Tìm theo mã đơn hàng..." class="field-input flex-1">
            <select v-model="statusFilter" class="field-input sm:w-52">
              <option value="">Tất cả trạng thái</option>
              <option value="new">Mới</option>
              <option value="confirmed">Đã xác nhận</option>
              <option value="shipping">Đang giao</option>
              <option value="completed">Hoàn thành</option>
              <option value="cancelled">Đã hủy</option>
              <option value="returned">Hoàn trả</option>
            </select>
            <button type="button" class="btn-outline text-xs px-4 shrink-0" @click="exportOrdersCsv">
              <Download class="w-4 h-4" /> Xuất CSV
            </button>
          </div>

          <p class="text-[11px] text-slate-500 m-0">
            Vì chính sách bảo mật thông tin khách hàng, tên và số điện thoại khách được ẩn bớt ở hệ thống.
          </p>

          <div v-if="isLoadingData" class="py-10 text-center text-sm text-slate-500">Đang tải danh sách đơn hàng...</div>
          <div v-else-if="!myOrders.length" class="py-10 text-center text-sm text-slate-500">Chưa có đơn hàng nào từ mã giới thiệu của bạn.</div>
          <div v-else class="overflow-x-auto">
            <table class="w-full text-left border-collapse text-xs sm:text-sm min-w-[680px]">
              <thead>
                <tr class="border-b border-slate-200 text-[11px] uppercase text-slate-500 bg-slate-50">
                  <th class="py-2.5 px-3 font-bold">Mã đơn / Ngày</th>
                  <th class="py-2.5 px-3 font-bold">Khách hàng</th>
                  <th class="py-2.5 px-3 font-bold">Giá trị đơn</th>
                  <th class="py-2.5 px-3 font-bold">Hoa hồng</th>
                  <th class="py-2.5 px-3 font-bold">Trạng thái</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="o in myOrders" :key="o.id" class="border-b border-slate-100 hover:bg-slate-50/70">
                  <td class="py-3 px-3">
                    <span class="font-bold text-[#0D2C54] tabular-nums block">#{{ o.order_code }}</span>
                    <span class="text-[11px] text-slate-500">{{ formatDate(o.created_at) }}</span>
                  </td>
                  <td class="py-3 px-3">
                    <span class="font-semibold text-slate-800 block">{{ o.customer_name_masked || 'Khách hàng' }}</span>
                    <span class="text-[11px] text-slate-500">{{ o.item_count || 1 }} sản phẩm</span>
                  </td>
                  <td class="py-3 px-3 font-bold text-slate-900 tabular-nums">{{ formatCurrency(o.total) }}</td>
                  <td class="py-3 px-3">
                    <span class="font-bold text-[#15803D] tabular-nums block">{{ formatCurrency(o.commission_amount) }}</span>
                    <span class="text-[11px] text-slate-500">{{ o.commission_rate }}% · {{ COMM_LABELS[o.commission_status] || o.commission_status }}</span>
                  </td>
                  <td class="py-3 px-3">
                    <span class="inline-flex px-2.5 py-1 rounded-full text-[11px] font-bold border" :class="STATUS_BADGE[o.status] || 'bg-slate-100 text-slate-700 border-slate-200'">
                      {{ STATUS_LABELS[o.status] || o.status }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div v-if="totalPages > 1" class="flex items-center justify-between pt-2">
            <span class="text-xs text-slate-500 tabular-nums">Trang {{ ordersPage }} / {{ totalPages }} ({{ ordersTotal }} đơn)</span>
            <div class="flex items-center gap-2">
              <button type="button" class="btn-outline text-xs px-3" :disabled="ordersPage <= 1" @click="goToPage(ordersPage - 1)">
                <ChevronLeft class="w-4 h-4" /> Trước
              </button>
              <button type="button" class="btn-outline text-xs px-3" :disabled="ordersPage >= totalPages" @click="goToPage(ordersPage + 1)">
                Sau <ChevronRight class="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>

        <!-- Tab 2: Withdraw Requests (P1-1) -->
        <div v-else-if="activeTab === 'withdraw'" class="p-4 sm:p-5 space-y-5">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
            <div class="border border-slate-200 rounded-xl p-4 sm:p-5 space-y-4 bg-slate-50/50">
              <h3 class="text-sm font-extrabold uppercase text-[#0D2C54] m-0">Tạo yêu cầu rút tiền</h3>
              <div class="text-xs space-y-1.5 text-slate-600">
                <p class="m-0">Số dư có thể rút ngay: <strong class="text-[#15803D] tabular-nums text-sm">{{ formatCurrency(overview.withdrawable_commission) }}</strong></p>
                <p class="m-0">Mức rút tối thiểu: <strong class="tabular-nums">{{ formatCurrency(minPayoutAmount) }}</strong> · Lịch đối soát: Thứ 2 hàng tuần</p>
                <p class="m-0">
                  Ngân hàng nhận tiền:
                  <strong :class="overview.bank_status === 'verified' ? 'text-[#15803D]' : 'text-[#C81E2B]'">
                    {{ BANK_STATUS_TEXT[overview.bank_status] || overview.bank_status }}
                  </strong>
                </p>
              </div>

              <div v-if="overview.bank_status !== 'verified'" class="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-lg p-3">
                Bạn cần cập nhật tài khoản ngân hàng ở tab <strong>Hồ sơ &amp; Ngân hàng</strong> và chờ Admin xác minh trước khi rút tiền.
              </div>
              <div v-else-if="hasOpenPayoutRequest" class="text-xs text-sky-800 bg-sky-50 border border-sky-200 rounded-lg p-3">
                Bạn đang có một yêu cầu rút tiền chưa hoàn tất. Vui lòng chờ Admin xử lý xong trước khi tạo yêu cầu mới.
              </div>
              <form v-else class="space-y-3" @submit.prevent="submitWithdrawRequest">
                <div class="space-y-1">
                  <label for="withdraw-amount" class="text-xs font-semibold text-slate-700 block">Số tiền muốn rút (VNĐ) *</label>
                  <input
                    id="withdraw-amount"
                    v-model.number="withdrawAmount"
                    type="number"
                    :min="minPayoutAmount"
                    :max="overview.withdrawable_commission"
                    step="10000"
                    required
                    :placeholder="`Tối thiểu ${minPayoutAmount.toLocaleString('vi-VN')} đ`"
                    class="field-input tabular-nums"
                  >
                </div>
                <div class="space-y-1">
                  <label for="withdraw-note" class="text-xs font-semibold text-slate-700 block">Ghi chú (tuỳ chọn)</label>
                  <input id="withdraw-note" v-model="withdrawNote" type="text" placeholder="VD: Rút hoa hồng tuần này..." class="field-input">
                </div>
                <button
                  type="submit"
                  :disabled="busyKey === 'withdraw' || overview.withdrawable_commission < minPayoutAmount"
                  class="btn-cta w-full text-xs"
                >
                  {{ busyKey === 'withdraw' ? 'ĐANG GỬI YÊU CẦU...' : 'GỬI YÊU CẦU RÚT TIỀN' }}
                </button>
              </form>
            </div>

            <div class="space-y-3">
              <h3 class="text-sm font-extrabold uppercase text-[#0D2C54] m-0">Danh sách yêu cầu rút tiền</h3>
              <div v-if="!myPayoutRequests.length" class="py-8 text-center text-xs text-slate-500 border border-dashed border-slate-200 rounded-xl">
                Bạn chưa có yêu cầu rút tiền nào.
              </div>
              <div v-else class="space-y-2.5">
                <div v-for="r in myPayoutRequests" :key="r.id" class="border border-slate-200 rounded-xl p-3.5 text-xs space-y-1.5 bg-white">
                  <div class="flex items-center justify-between gap-2">
                    <span class="font-extrabold text-[#0D2C54] text-sm tabular-nums">{{ formatCurrency(r.amount) }}</span>
                    <span class="px-2.5 py-0.5 rounded-full text-[11px] font-bold border" :class="REQ_BADGE[r.status] || 'bg-slate-100'">
                      {{ REQ_LABELS[r.status] || r.status }}
                    </span>
                  </div>
                  <p class="text-slate-500 m-0">Gửi lúc: {{ formatDate(r.requested_at) }}</p>
                  <p v-if="r.bank_snapshot?.bank_name" class="text-slate-600 m-0">
                    TK: {{ r.bank_snapshot.bank_name }} · {{ r.bank_snapshot.account_number }} ({{ r.bank_snapshot.account_holder }})
                  </p>
                  <p v-if="r.reject_reason" class="text-[#C81E2B] font-semibold m-0">Lý do từ chối: {{ r.reject_reason }}</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Tab 3: Payout History -->
        <div v-else-if="activeTab === 'payouts'" class="p-4 sm:p-5 space-y-4">
          <div class="flex justify-end">
            <button type="button" class="btn-outline text-xs px-4" @click="exportPayoutsCsv">
              <Download class="w-4 h-4" /> Xuất CSV lịch sử chi trả
            </button>
          </div>
          <div v-if="!myPayouts.length" class="py-10 text-center text-sm text-slate-500">Chưa có đợt chi trả hoa hồng nào.</div>
          <div v-else class="overflow-x-auto">
            <table class="w-full text-left border-collapse text-xs sm:text-sm min-w-[600px]">
              <thead>
                <tr class="border-b border-slate-200 text-[11px] uppercase text-slate-500 bg-slate-50">
                  <th class="py-2.5 px-3 font-bold">Ngày chi trả</th>
                  <th class="py-2.5 px-3 font-bold">Số đơn</th>
                  <th class="py-2.5 px-3 font-bold">Thực nhận</th>
                  <th class="py-2.5 px-3 font-bold">Mã giao dịch</th>
                  <th class="py-2.5 px-3 font-bold">Ghi chú</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="p in myPayouts" :key="p.id" class="border-b border-slate-100">
                  <td class="py-3 px-3 text-slate-700">{{ formatDate(p.paid_at) }}</td>
                  <td class="py-3 px-3 font-semibold text-slate-900 tabular-nums">{{ p.order_count }} đơn</td>
                  <td class="py-3 px-3">
                    <span class="font-bold text-[#15803D] tabular-nums block">{{ formatCurrency(p.net_amount ?? p.amount) }}</span>
                    <span v-if="Number(p.tax_amount || 0) > 0" class="text-[11px] text-slate-500 tabular-nums">
                      Trước thuế: {{ formatCurrency(p.gross_amount ?? p.amount) }} · Thuế: -{{ formatCurrency(p.tax_amount) }}
                    </span>
                  </td>
                  <td class="py-3 px-3 font-mono text-xs text-slate-700">{{ p.transaction_ref || '—' }}</td>
                  <td class="py-3 px-3 text-slate-600">{{ p.note || '—' }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Tab 4: Leads (V20) -->
        <div v-else-if="activeTab === 'leads'" class="p-4 sm:p-5 space-y-3">
          <p class="text-xs text-slate-500 m-0">Khách hàng để lại yêu cầu tư vấn qua link giới thiệu của bạn (đã ẩn thông tin nhạy cảm).</p>
          <div v-if="!myLeads.length" class="py-10 text-center text-sm text-slate-500">Chưa có yêu cầu tư vấn nào từ link của bạn.</div>
          <div v-else class="overflow-x-auto">
            <table class="w-full text-left border-collapse text-xs sm:text-sm min-w-[540px]">
              <thead>
                <tr class="border-b border-slate-200 text-[11px] uppercase text-slate-500 bg-slate-50">
                  <th class="py-2.5 px-3 font-bold">Ngày gửi</th>
                  <th class="py-2.5 px-3 font-bold">Khách hàng</th>
                  <th class="py-2.5 px-3 font-bold">Dòng xe quan tâm</th>
                  <th class="py-2.5 px-3 font-bold">Trạng thái</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="l in myLeads" :key="l.id" class="border-b border-slate-100">
                  <td class="py-3 px-3 text-slate-600">{{ formatDate(l.created_at) }}</td>
                  <td class="py-3 px-3 font-semibold text-slate-800">{{ l.customer_name_masked || 'Khách hàng' }}</td>
                  <td class="py-3 px-3 text-slate-700">{{ l.car_info || '—' }}</td>
                  <td class="py-3 px-3">
                    <span class="px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-slate-100 text-slate-700">{{ l.status }}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Tab 5: Profile, Bank & Password (P1-2) -->
        <div v-else class="p-4 sm:p-5 grid grid-cols-1 lg:grid-cols-3 gap-5">
          <!-- Profile -->
          <form class="border border-slate-200 rounded-xl p-4 space-y-3" @submit.prevent="saveProfile">
            <h3 class="text-sm font-extrabold uppercase text-[#0D2C54] m-0">Thông tin cá nhân</h3>
            <div class="space-y-1">
              <label for="pf-name" class="text-xs font-semibold text-slate-700 block">Họ và tên *</label>
              <input id="pf-name" v-model="profileForm.full_name" type="text" required class="field-input">
            </div>
            <div class="space-y-1">
              <label for="pf-phone" class="text-xs font-semibold text-slate-700 block">Số điện thoại</label>
              <input id="pf-phone" v-model="profileForm.phone" type="tel" class="field-input">
            </div>
            <div class="space-y-1">
              <label for="pf-zalo" class="text-xs font-semibold text-slate-700 block">Zalo</label>
              <input id="pf-zalo" v-model="profileForm.zalo" type="text" class="field-input">
            </div>
            <div class="space-y-1">
              <label for="pf-area" class="text-xs font-semibold text-slate-700 block">Khu vực hoạt động</label>
              <input id="pf-area" v-model="profileForm.area" type="text" class="field-input">
            </div>
            <div class="space-y-1">
              <label for="pf-job" class="text-xs font-semibold text-slate-700 block">Công việc / Gara</label>
              <input id="pf-job" v-model="profileForm.job_type" type="text" class="field-input">
            </div>
            <button type="submit" :disabled="busyKey === 'profile'" class="btn-cta w-full text-xs">
              {{ busyKey === 'profile' ? 'ĐANG LƯU...' : 'LƯU HỒ SƠ' }}
            </button>
          </form>

          <!-- Bank Account -->
          <form class="border border-slate-200 rounded-xl p-4 space-y-3" @submit.prevent="saveBank">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-sm font-extrabold uppercase text-[#0D2C54] m-0">Tài khoản ngân hàng</h3>
              <span
                class="px-2 py-0.5 rounded-full text-[10px] font-bold border"
                :class="bankAccount?.status === 'verified' ? 'bg-green-50 text-[#15803D] border-green-200' : bankAccount?.status === 'rejected' ? 'bg-[#FEF2F2] text-[#C81E2B] border-[#C81E2B]/30' : 'bg-amber-50 text-amber-700 border-amber-200'"
              >
                {{ BANK_STATUS_TEXT[bankAccount?.status || 'none'] }}
              </span>
            </div>
            <p v-if="bankAccount?.reject_reason" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] rounded-lg p-2.5 m-0">
              Lý do từ chối: {{ bankAccount.reject_reason }}
            </p>
            <div class="space-y-1">
              <label for="bk-name" class="text-xs font-semibold text-slate-700 block">Tên ngân hàng *</label>
              <input id="bk-name" v-model="bankForm.bank_name" type="text" required placeholder="VD: Vietcombank, Techcombank..." class="field-input">
            </div>
            <div class="space-y-1">
              <label for="bk-num" class="text-xs font-semibold text-slate-700 block">Số tài khoản *</label>
              <input id="bk-num" v-model="bankForm.account_number" type="text" required placeholder="Nhập chính xác số tài khoản" class="field-input tabular-nums">
            </div>
            <div class="space-y-1">
              <label for="bk-holder" class="text-xs font-semibold text-slate-700 block">Tên chủ tài khoản (IN HOA) *</label>
              <input id="bk-holder" v-model="bankForm.account_holder" type="text" required placeholder="NGUYEN VAN A" class="field-input uppercase">
            </div>
            <div class="space-y-1">
              <label for="bk-branch" class="text-xs font-semibold text-slate-700 block">Chi nhánh (tuỳ chọn)</label>
              <input id="bk-branch" v-model="bankForm.branch" type="text" class="field-input">
            </div>
            <p class="text-[11px] text-slate-500 m-0">Lưu ý: Mỗi khi thay đổi thông tin ngân hàng, tài khoản sẽ cần Admin xác minh lại.</p>
            <button type="submit" :disabled="busyKey === 'bank'" class="btn-cta w-full text-xs">
              {{ busyKey === 'bank' ? 'ĐANG LƯU...' : 'CẬP NHẬT NGÂN HÀNG' }}
            </button>
          </form>

          <!-- Change Password -->
          <form class="border border-slate-200 rounded-xl p-4 space-y-3" @submit.prevent="changePassword">
            <h3 class="text-sm font-extrabold uppercase text-[#0D2C54] m-0 flex items-center gap-1.5">
              <KeyRound class="w-4 h-4" /> Đổi mật khẩu
            </h3>
            <div class="space-y-1">
              <label for="pw-current" class="text-xs font-semibold text-slate-700 block">Mật khẩu hiện tại *</label>
              <input id="pw-current" v-model="passwordForm.currentPassword" type="password" required autocomplete="current-password" class="field-input">
            </div>
            <div class="space-y-1">
              <label for="pw-new" class="text-xs font-semibold text-slate-700 block">Mật khẩu mới (≥ 8 ký tự) *</label>
              <input id="pw-new" v-model="passwordForm.newPassword" type="password" minlength="8" required autocomplete="new-password" class="field-input">
            </div>
            <div class="space-y-1">
              <label for="pw-confirm" class="text-xs font-semibold text-slate-700 block">Nhập lại mật khẩu mới *</label>
              <input id="pw-confirm" v-model="passwordForm.confirmPassword" type="password" minlength="8" required autocomplete="new-password" class="field-input">
            </div>
            <button type="submit" :disabled="busyKey === 'password'" class="btn-outline w-full text-xs">
              {{ busyKey === 'password' ? 'ĐANG CẬP NHẬT...' : 'ĐỔI MẬT KHẨU' }}
            </button>
          </form>
        </div>
      </div>
    </section>
  </main>
</template>
