<script setup lang="ts">
import { UserCheck, Clock, Shield, RefreshCw, Link2, Copy } from 'lucide-vue-next';

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

const profile = ref<any>(null);
const myOrders = ref<any[]>([]);
const myPayouts = ref<any[]>([]);
const activeTab = ref<'orders' | 'payouts'>('orders');
const statusFilter = ref('');

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
  cancelled: 'Đã hủy'
};

const STATUS_BADGE: Record<string, string> = {
  new: 'bg-sky-50 text-sky-700 border-sky-200',
  confirmed: 'bg-[#EFF4FA] text-[#0D2C54] border-[#0D2C54]/20',
  shipping: 'bg-amber-50 text-amber-700 border-amber-200',
  completed: 'bg-green-50 text-[#15803D] border-green-200',
  cancelled: 'bg-[#FEF2F2] text-[#C81E2B] border-[#C81E2B]/25'
};

const COMM_LABELS: Record<string, string> = {
  pending: 'Chờ duyệt',
  approved: 'Đã duyệt (chờ rút)',
  paid: 'Đã thanh toán'
};

const maskPhone = (p: string) => (p && p.length >= 7 ? `${p.slice(0, 4)}***${p.slice(-3)}` : p || '');
const formatDate = (iso: string) =>
  iso ? new Date(iso).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';

const filteredOrders = computed(() =>
  statusFilter.value ? myOrders.value.filter((o) => o.status === statusFilter.value) : myOrders.value
);

const kpis = computed(() => {
  const valid = myOrders.value.filter((o) => o.status !== 'cancelled');
  const rev = valid.reduce((s, o) => s + Number(o.total_amount || 0), 0);
  const pending = valid.filter((o) => o.commission_status === 'pending').reduce((s, o) => s + Number(o.commission_amount || 0), 0);
  const approved = valid.filter((o) => o.commission_status === 'approved').reduce((s, o) => s + Number(o.commission_amount || 0), 0);
  const paid = valid.filter((o) => o.commission_status === 'paid').reduce((s, o) => s + Number(o.commission_amount || 0), 0);
  return { count: myOrders.value.length, rev, pending, approved, paid };
});

const pendingTitle = computed(() => {
  const map: Record<string, string> = {
    pending: 'Tài khoản đang chờ duyệt',
    suspended: 'Tài khoản đang tạm khóa',
    cancelled: 'Tài khoản CTV đã bị hủy'
  };
  return profile.value ? (map[profile.value.status] || 'Tài khoản chưa kích hoạt') : 'Chưa có hồ sơ CTV';
});

const loadMyData = async () => {
  if (!supabase || !profile.value) return;
  const code = String(profile.value.code || '').toUpperCase();
  const [{ data: orders }, { data: payouts }] = await Promise.all([
    supabase.from('orders').select('*').eq('affiliate_code', code).order('created_at', { ascending: false }).limit(200),
    supabase.from('commission_payouts').select('*').eq('affiliate_code', code).order('paid_at', { ascending: false }).limit(100)
  ]);
  myOrders.value = orders || [];
  myPayouts.value = payouts || [];
};

const checkSession = async () => {
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
  if (!prof) {
    profile.value = null;
    viewState.value = 'pending';
    return;
  }
  if (prof.role === 'admin' && prof.status === 'active') {
    router.replace('/admin');
    return;
  }
  profile.value = prof;
  if (prof.status !== 'active') {
    viewState.value = 'pending';
    return;
  }
  viewState.value = 'dashboard';
  await loadMyData();
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
    await checkSession();
  } catch (err: any) {
    loginError.value = err?.message === 'Invalid login credentials' ? 'Email hoặc mật khẩu không đúng.' : (err?.message || 'Đăng nhập thất bại.');
  } finally {
    isLoggingIn.value = false;
  }
};

const handleLogout = async () => {
  if (supabase) await supabase.auth.signOut();
  profile.value = null;
  myOrders.value = [];
  myPayouts.value = [];
  viewState.value = 'login';
};

const copyShareLink = async () => {
  if (!import.meta.client) return;
  try {
    await navigator.clipboard.writeText(shareUrl.value);
    showToast('Đã sao chép link bán hàng!');
  } catch {
    showToast('Không thể tự sao chép, vui lòng copy trực tiếp ở ô link.', 'error');
  }
};

onMounted(() => {
  checkSession();
});
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-5">
    <div v-if="viewState === 'loading'" class="card-surface p-8 text-center text-xs text-slate-500">
      Đang tải Cổng CTV...
    </div>

    <!-- Login -->
    <section v-else-if="viewState === 'login'" class="max-w-md mx-auto card-surface p-6 space-y-4">
      <div class="text-center space-y-1.5">
        <div class="w-12 h-12 rounded-2xl bg-[#EFF4FA] text-[#0D2C54] flex items-center justify-center mx-auto">
          <UserCheck class="w-6 h-6" />
        </div>
        <h1 class="text-lg font-bold uppercase text-[#0D2C54] m-0">Đăng Nhập Cổng CTV</h1>
        <p class="text-xs text-slate-500 m-0">Xem đơn hàng bạn đã giới thiệu, tạo link bán hàng và theo dõi hoa hồng</p>
      </div>

      <p v-if="loginError" role="alert" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3.5 py-2.5 m-0">
        {{ loginError }}
      </p>

      <form class="space-y-3.5" @submit.prevent="handleLogin">
        <div class="space-y-1">
          <label for="login-email" class="text-xs font-semibold text-slate-700 block">Email</label>
          <input id="login-email" v-model="loginEmail" type="email" required placeholder="email@domain.com" class="field-input">
        </div>
        <div class="space-y-1">
          <label for="login-password" class="text-xs font-semibold text-slate-700 block">Mật khẩu</label>
          <input id="login-password" v-model="loginPassword" type="password" required placeholder="Nhập mật khẩu..." class="field-input">
        </div>
        <button type="submit" :disabled="isLoggingIn" class="btn-cta w-full text-xs">
          {{ isLoggingIn ? 'ĐANG ĐĂNG NHẬP...' : 'ĐĂNG NHẬP CTV' }}
        </button>
      </form>

      <p class="text-xs text-slate-600 text-center m-0 pt-2 border-t border-slate-100">
        Chưa có tài khoản CTV? <NuxtLink to="/cong-tac-vien" class="font-semibold text-[#C81E2B] underline">Đăng ký ngay</NuxtLink>
      </p>
    </section>

    <!-- Pending / Suspended -->
    <section v-else-if="viewState === 'pending'" class="max-w-lg mx-auto card-surface p-6 text-center space-y-4">
      <div class="w-14 h-14 rounded-full bg-amber-50 border border-amber-200 text-amber-600 flex items-center justify-center mx-auto">
        <Clock class="w-7 h-7" />
      </div>
      <h2 class="text-lg font-bold text-[#0D2C54] m-0">{{ pendingTitle }}</h2>
      <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
        {{ profile ? `Mã CTV của bạn là ${profile.code}. Vui lòng nhắn Zalo 0963 294 492 để được hỗ trợ kích hoạt.` : 'Tài khoản này chưa có thông tin CTV trong hệ thống.' }}
      </p>
      <div class="flex flex-wrap justify-center gap-3">
        <a href="https://zalo.me/0963294492" target="_blank" rel="noopener" class="btn-cta text-xs px-5 no-underline">NHẮN ZALO HỖ TRỢ</a>
        <button type="button" class="btn-outline text-xs px-5" @click="handleLogout">Đăng xuất</button>
      </div>
    </section>

    <!-- Dashboard -->
    <section v-else class="space-y-5">
      <div class="card-surface p-4 sm:p-5 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
        <div class="space-y-1 min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h1 class="text-base sm:text-lg font-bold text-[#0D2C54] m-0">{{ profile?.full_name }}</h1>
            <span class="text-[11px] font-semibold uppercase px-2.5 py-0.5 rounded-full bg-[#EFF4FA] text-[#0D2C54] whitespace-nowrap">CTV Portal</span>
            <span class="text-[11px] font-bold uppercase px-2.5 py-0.5 rounded-full bg-[#FEF2F2] text-[#C81E2B] tabular-nums whitespace-nowrap">{{ profile?.code }}</span>
          </div>
          <p class="text-xs text-slate-500 m-0">Mức hoa hồng của bạn: {{ profile?.commission_rate }}% trên tổng giá trị đơn hàng thành công.</p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <NuxtLink
            v-if="profile?.role === 'develop'"
            to="/admin"
            class="inline-flex items-center justify-center gap-1.5 min-h-[44px] lg:min-h-[40px] px-3.5 rounded-lg bg-[#0D2C54] hover:bg-[#133A6E] text-white text-xs font-semibold no-underline transition whitespace-nowrap shrink-0"
          >
            <Shield class="w-3.5 h-3.5" /> Mở Trang Admin →
          </NuxtLink>
          <button type="button" class="btn-outline text-xs px-3.5 min-h-[44px] lg:min-h-[40px] whitespace-nowrap shrink-0" @click="loadMyData().then(() => showToast('Đã làm mới dữ liệu'))">
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
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Đơn đã giới thiệu</span>
          <span class="text-xl sm:text-2xl font-bold text-[#0D2C54] tabular-nums block">{{ kpis.count }}</span>
        </div>
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Tổng doanh số</span>
          <span class="text-xl sm:text-2xl font-bold text-[#0D2C54] tabular-nums block">{{ formatCurrency(kpis.rev) }}</span>
        </div>
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Hoa hồng chờ duyệt / rút</span>
          <span class="text-xl sm:text-2xl font-bold text-[#0D2C54] tabular-nums block">{{ formatCurrency(kpis.pending + kpis.approved) }}</span>
        </div>
        <div class="card-surface p-4 space-y-1">
          <span class="text-[11px] font-semibold uppercase text-slate-500 block">Hoa hồng đã nhận</span>
          <span class="text-xl sm:text-2xl font-bold text-[#15803D] tabular-nums block">{{ formatCurrency(kpis.paid) }}</span>
        </div>
      </div>

      <!-- Share Link Generator -->
      <div class="card-surface p-4 sm:p-5 space-y-3.5">
        <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0 flex items-center gap-2">
          <Link2 class="w-4 h-4 shrink-0" /> Tạo link bán hàng nhanh (tự gắn mã giới thiệu)
        </h2>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <select v-model="shareBrand" class="ymm-select text-xs">
            <option value="">Trang chủ (tất cả xe)</option>
            <option v-for="b in BRAND_CATALOG" :key="b.slug" :value="b.slug">Hãng {{ b.name }}</option>
          </select>
          <select v-model="shareModel" :disabled="!shareBrand" class="ymm-select text-xs">
            <option value="">Tất cả dòng xe của hãng</option>
            <option v-for="m in shareModels" :key="m.slug" :value="m.slug">{{ m.name }}</option>
          </select>
          <button type="button" class="btn-cta text-xs min-h-[44px] whitespace-nowrap" @click="copyShareLink">
            <Copy class="w-4 h-4" /> SAO CHÉP LINK
          </button>
        </div>
        <div class="bg-[#F4F6F9] border border-slate-200 rounded-lg px-3 py-2.5">
          <input :value="shareUrl" type="text" readonly class="w-full bg-transparent border-0 text-xs text-[#0D2C54] font-medium focus:outline-none">
        </div>
      </div>

      <!-- Tabs -->
      <div class="flex gap-2 overflow-x-auto no-scrollbar pb-1 border-b border-slate-200">
        <button
          type="button"
          class="min-h-[42px] px-4 py-2 rounded-lg text-xs font-semibold cursor-pointer whitespace-nowrap shrink-0"
          :class="activeTab === 'orders' ? 'bg-[#0D2C54] text-white' : 'bg-white text-slate-700 border border-slate-200'"
          @click="activeTab = 'orders'"
        >
          Danh sách đơn hàng của tôi
        </button>
        <button
          type="button"
          class="min-h-[42px] px-4 py-2 rounded-lg text-xs font-semibold cursor-pointer whitespace-nowrap shrink-0"
          :class="activeTab === 'payouts' ? 'bg-[#0D2C54] text-white' : 'bg-white text-slate-700 border border-slate-200'"
          @click="activeTab = 'payouts'"
        >
          Lịch sử hoa hồng / Rút tiền
        </button>
      </div>

      <!-- Tab 1: Orders -->
      <div v-if="activeTab === 'orders'" class="card-surface p-4 sm:p-5 space-y-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Đơn hàng qua mã giới thiệu của bạn</h2>
          <select v-model="statusFilter" class="ymm-select text-xs sm:w-48">
            <option value="">Tất cả trạng thái</option>
            <option v-for="(label, key) in STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
          </select>
        </div>

        <p v-if="filteredOrders.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">
          Chưa có đơn hàng nào từ link/mã giới thiệu của bạn.
        </p>

        <template v-else>
          <div class="hidden lg:block overflow-x-auto">
            <table class="w-full text-left border-collapse text-xs">
              <thead>
                <tr class="border-b border-slate-200 text-slate-500 uppercase text-[11px]">
                  <th class="py-2.5 pr-4 whitespace-nowrap">Mã đơn</th>
                  <th class="py-2.5 pr-4 whitespace-nowrap">Khách hàng</th>
                  <th class="py-2.5 pr-4">Sản phẩm &amp; Xe</th>
                  <th class="py-2.5 pr-4 whitespace-nowrap">Giá trị đơn</th>
                  <th class="py-2.5 pr-4 whitespace-nowrap">Hoa hồng</th>
                  <th class="py-2.5 whitespace-nowrap">Trạng thái</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100">
                <tr v-for="o in filteredOrders" :key="o.id" class="align-top">
                  <td class="py-3.5 pr-4 whitespace-nowrap">
                    <strong class="text-[#0D2C54] tabular-nums block">#{{ o.order_code }}</strong>
                    <span class="text-[11px] text-slate-500 tabular-nums">{{ formatDate(o.created_at) }}</span>
                  </td>
                  <td class="py-3.5 pr-4 whitespace-nowrap">
                    <strong class="text-slate-900 block">{{ o.customer_name }}</strong>
                    <span class="text-slate-500 tabular-nums block">{{ maskPhone(o.phone) }}</span>
                  </td>
                  <td class="py-3.5 pr-4 max-w-xs">
                    <p class="m-0 text-slate-700 whitespace-pre-line leading-snug">{{ o.items_summary }}</p>
                    <span class="text-[11px] text-slate-500">{{ o.payment_method }}</span>
                  </td>
                  <td class="py-3.5 pr-4 whitespace-nowrap font-semibold text-slate-900 tabular-nums">{{ formatCurrency(o.total_amount) }}</td>
                  <td class="py-3.5 pr-4 whitespace-nowrap font-bold text-[#15803D] tabular-nums">
                    {{ formatCurrency(o.commission_amount) }}
                    <span class="block text-[11px] font-medium text-slate-500">{{ o.commission_rate }}%</span>
                  </td>
                  <td class="py-3.5 whitespace-nowrap">
                    <span class="inline-block px-2.5 py-0.5 rounded-full border font-semibold text-[11px]" :class="STATUS_BADGE[o.status]">{{ STATUS_LABELS[o.status] || o.status }}</span>
                    <span class="block text-[11px] text-slate-500 mt-1">{{ COMM_LABELS[o.commission_status] || o.commission_status }}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="lg:hidden space-y-3">
            <div v-for="o in filteredOrders" :key="o.id" class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-4 space-y-2.5 text-xs">
              <div class="flex items-start justify-between gap-2">
                <div>
                  <strong class="text-sm text-[#0D2C54] tabular-nums block">#{{ o.order_code }}</strong>
                  <span class="text-[11px] text-slate-500 tabular-nums">{{ formatDate(o.created_at) }}</span>
                </div>
                <span class="px-2.5 py-1 rounded-full border text-[11px] font-semibold whitespace-nowrap" :class="STATUS_BADGE[o.status]">
                  {{ STATUS_LABELS[o.status] || o.status }}
                </span>
              </div>
              <div class="text-slate-700">
                <strong>{{ o.customer_name }}</strong> · <span class="tabular-nums text-slate-500">{{ maskPhone(o.phone) }}</span>
              </div>
              <p class="m-0 text-slate-600 whitespace-pre-line leading-relaxed bg-white rounded-lg p-2.5 border border-slate-200/80">{{ o.items_summary }}</p>
              <div class="flex items-center justify-between pt-2 border-t border-slate-200">
                <div>
                  <span class="text-[11px] text-slate-500 block">Giá trị đơn</span>
                  <strong class="text-slate-900 tabular-nums">{{ formatCurrency(o.total_amount) }}</strong>
                </div>
                <div class="text-right">
                  <span class="text-[11px] text-slate-500 block">Hoa hồng ({{ COMM_LABELS[o.commission_status] }})</span>
                  <strong class="text-sm text-[#15803D] tabular-nums">{{ formatCurrency(o.commission_amount) }}</strong>
                </div>
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- Tab 2: Payouts -->
      <div v-else class="space-y-4">
        <div class="card-surface p-4 sm:p-5 space-y-3">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div>
              <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Tổng hợp đối soát hoa hồng</h2>
              <p class="text-xs text-slate-500 mt-1 m-0">Hoa hồng được duyệt sau khi đơn hàng giao lắp hoàn thành.</p>
            </div>
            <a href="https://zalo.me/0963294492" target="_blank" rel="noopener" class="btn-outline text-xs px-4 min-h-[44px] lg:min-h-[40px] whitespace-nowrap shrink-0 no-underline">
              Nhắn Zalo yêu cầu rút tiền
            </a>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 text-xs">
            <div class="bg-[#F4F6F9] rounded-xl p-3.5 border border-slate-200">
              <span class="text-slate-500 block">Chờ duyệt</span>
              <strong class="text-base font-bold text-[#0D2C54] tabular-nums block mt-1">{{ formatCurrency(kpis.pending) }}</strong>
            </div>
            <div class="bg-[#EFF4FA] rounded-xl p-3.5 border border-[#0D2C54]/20">
              <span class="text-[#0D2C54] block">Đã duyệt — Chờ chi trả</span>
              <strong class="text-base font-bold text-[#0D2C54] tabular-nums block mt-1">{{ formatCurrency(kpis.approved) }}</strong>
            </div>
            <div class="bg-green-50 rounded-xl p-3.5 border border-green-200">
              <span class="text-[#15803D] block">Tổng đã thanh toán</span>
              <strong class="text-base font-bold text-[#15803D] tabular-nums block mt-1">{{ formatCurrency(kpis.paid) }}</strong>
            </div>
          </div>
        </div>

        <div class="card-surface p-4 sm:p-5 space-y-4">
          <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Lịch sử các đợt thanh toán hoa hồng</h2>
          <p v-if="myPayouts.length === 0" class="text-xs text-slate-500 text-center py-6 m-0">
            Chưa có đợt thanh toán hoa hồng nào được ghi nhận.
          </p>
          <template v-else>
            <div class="hidden lg:block overflow-x-auto">
              <table class="w-full text-left border-collapse text-xs">
                <thead>
                  <tr class="border-b border-slate-200 text-slate-500 uppercase text-[11px]">
                    <th class="py-2.5 pr-4 whitespace-nowrap">Thời gian chi trả</th>
                    <th class="py-2.5 pr-4 whitespace-nowrap">Số đơn</th>
                    <th class="py-2.5 pr-4 whitespace-nowrap">Số tiền đã nhận</th>
                    <th class="py-2.5">Ghi chú / Mã giao dịch</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-100">
                  <tr v-for="p in myPayouts" :key="p.id">
                    <td class="py-3 pr-4 whitespace-nowrap text-slate-700 tabular-nums">{{ formatDate(p.paid_at) }}</td>
                    <td class="py-3 pr-4 whitespace-nowrap font-semibold text-[#0D2C54] tabular-nums">{{ p.order_count }} đơn</td>
                    <td class="py-3 pr-4 whitespace-nowrap font-bold text-[#15803D] tabular-nums">{{ formatCurrency(p.amount) }}</td>
                    <td class="py-3 text-slate-600">{{ p.note || 'Đã chuyển khoản thanh toán hoa hồng' }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="lg:hidden space-y-3">
              <div v-for="p in myPayouts" :key="p.id" class="rounded-xl border border-slate-200 bg-[#F8FAFC] p-3.5 text-xs space-y-1">
                <div class="flex justify-between items-center">
                  <strong class="text-[#0D2C54]">{{ p.order_count }} đơn đối soát</strong>
                  <strong class="text-[#15803D] tabular-nums">{{ formatCurrency(p.amount) }}</strong>
                </div>
                <p class="text-[11px] text-slate-500 m-0 tabular-nums">{{ formatDate(p.paid_at) }}</p>
                <p class="text-slate-600 m-0">{{ p.note || 'Đã chuyển khoản thanh toán hoa hồng' }}</p>
              </div>
            </div>
          </template>
        </div>
      </div>
    </section>
  </main>
</template>
