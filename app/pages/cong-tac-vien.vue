<script setup lang="ts">
import { Handshake, LogIn, Percent, Link2, BarChart3, Check } from 'lucide-vue-next';

useSeoMeta({
  title: 'Chương Trình Cộng Tác Viên | Trung Thành Auto',
  description: 'Đăng ký làm cộng tác viên bán thảm lót sàn ô tô Trung Thành Auto. Không cần ôm hàng, hoa hồng 10% - 15%, theo dõi đơn minh bạch.'
});

const { supabase, isConfigured } = useSupabase();

const fullName = ref('');
const phone = ref('');
const email = ref('');
const password = ref('');
const codeInput = ref('');
const jobType = ref('Sale hãng xe');
const area = ref('');
const errorMsg = ref('');
const isSubmitting = ref(false);
const registeredInfo = ref<{ code: string; needConfirm: boolean } | null>(null);

const generateCode = (raw: string) => {
  const clean = raw.trim().toUpperCase().replace(/[^A-Z0-9_-]/g, '').slice(0, 16);
  return clean.length >= 3 ? clean : `CTV${Math.floor(1000 + Math.random() * 9000)}`;
};

const handleRegister = async () => {
  errorMsg.value = '';
  const cleanPhone = phone.value.replace(/\s+/g, '');
  const cleanEmail = email.value.trim().toLowerCase();
  const code = generateCode(codeInput.value);

  if (fullName.value.trim().length < 2) {
    errorMsg.value = 'Vui lòng nhập họ và tên (ít nhất 2 ký tự).';
    return;
  }
  if (!/^0[35789]\d{8}$/.test(cleanPhone)) {
    errorMsg.value = 'Số điện thoại không hợp lệ (cần đúng 10 số, VD: 0963294492).';
    return;
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) {
    errorMsg.value = 'Email không hợp lệ.';
    return;
  }
  if (password.value.length < 6) {
    errorMsg.value = 'Mật khẩu phải có ít nhất 6 ký tự.';
    return;
  }
  if (!isConfigured || !supabase) {
    errorMsg.value = 'Chưa cấu hình kết nối Supabase (.env).';
    return;
  }

  isSubmitting.value = true;
  try {
    const { data, error } = await supabase.auth.signUp({
      email: cleanEmail,
      password: password.value,
      options: {
        data: {
          full_name: fullName.value.trim(),
          phone: cleanPhone,
          code,
          area: area.value.trim(),
          job_type: jobType.value
        }
      }
    });
    if (error) throw error;
    registeredInfo.value = { code, needConfirm: !data.session };
  } catch (err: any) {
    errorMsg.value = err?.message || 'Đăng ký thất bại. Vui lòng thử lại sau.';
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-6">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54]">Cộng tác viên</span>
    </nav>

    <section class="bg-[#0D2C54] text-white rounded-2xl p-5 sm:p-8 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-5">
      <div class="space-y-2.5 max-w-2xl">
        <span class="inline-flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wider px-3 py-1 rounded-full bg-white/10 text-[#F59E0B]">
          <Handshake class="w-3.5 h-3.5" /> Hợp tác phân phối toàn quốc
        </span>
        <h1 class="text-xl sm:text-2xl lg:text-3xl font-bold m-0 leading-tight">TUYỂN CỘNG TÁC VIÊN THẢM LÓT SÀN Ô TÔ</h1>
        <p class="text-xs sm:text-sm text-slate-200 m-0 leading-relaxed">
          Phù hợp cho Sale hãng xe, chủ Gara, tiệm rửa xe hoặc bán hàng online. Chỉ cần chia sẻ link giới thiệu có mã CTV — xưởng lo đo phom, cắt may, giao lắp và bảo hành 24 tháng.
        </p>
      </div>
      <div class="flex flex-wrap gap-3 shrink-0">
        <a href="#ctv-register-form" class="btn-cta text-xs px-5 no-underline">ĐĂNG KÝ NGAY</a>
        <NuxtLink to="/ctv" class="inline-flex items-center justify-center gap-2 min-h-[44px] px-5 rounded-lg bg-white/10 hover:bg-white/20 text-white text-xs font-semibold no-underline transition border border-white/20">
          <LogIn class="w-4 h-4" /> ĐĂNG NHẬP CỔNG CTV
        </NuxtLink>
      </div>
    </section>

    <section class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <div class="card-surface p-5 space-y-2">
        <div class="w-10 h-10 rounded-xl bg-[#EFF4FA] text-[#0D2C54] flex items-center justify-center">
          <Percent class="w-5 h-5" />
        </div>
        <h2 class="text-sm font-bold text-[#0D2C54] uppercase m-0">Hoa hồng 10% – 15% / đơn</h2>
        <p class="text-xs text-slate-600 m-0 leading-relaxed">Tự động tính hoa hồng theo từng đơn thành công. Không áp doanh số, không cần vốn ôm hàng.</p>
      </div>
      <div class="card-surface p-5 space-y-2">
        <div class="w-10 h-10 rounded-xl bg-[#EFF4FA] text-[#0D2C54] flex items-center justify-center">
          <Link2 class="w-5 h-5" />
        </div>
        <h2 class="text-sm font-bold text-[#0D2C54] uppercase m-0">Lưu mã giới thiệu 30 ngày</h2>
        <p class="text-xs text-slate-600 m-0 leading-relaxed">Khách bấm link của bạn hôm nay, tuần sau quay lại đặt vẫn tự động ghi nhận đúng mã CTV.</p>
      </div>
      <div class="card-surface p-5 space-y-2">
        <div class="w-10 h-10 rounded-xl bg-[#EFF4FA] text-[#0D2C54] flex items-center justify-center">
          <BarChart3 class="w-5 h-5" />
        </div>
        <h2 class="text-sm font-bold text-[#0D2C54] uppercase m-0">Theo dõi đơn minh bạch</h2>
        <p class="text-xs text-slate-600 m-0 leading-relaxed">Đăng nhập Cổng CTV để tạo link nhanh theo từng dòng xe, xem trạng thái đơn và lịch sử chi trả.</p>
      </div>
    </section>

    <div class="grid grid-cols-1 lg:grid-cols-5 gap-6 items-start">
      <section class="lg:col-span-2 card-surface p-5 space-y-4">
        <h2 class="text-sm font-bold uppercase text-[#0D2C54] pb-3 border-b border-slate-200 m-0">3 bước bắt đầu bán hàng</h2>
        <ol class="space-y-3.5 m-0 p-0 list-none text-xs sm:text-sm text-slate-700">
          <li class="flex gap-3">
            <span class="w-6 h-6 rounded-full bg-[#0D2C54] text-white text-xs font-bold flex items-center justify-center shrink-0">1</span>
            <div><strong class="text-[#0D2C54] block">Đăng ký tài khoản CTV</strong>Điền thông tin và chọn mã CTV ngắn gọn.</div>
          </li>
          <li class="flex gap-3">
            <span class="w-6 h-6 rounded-full bg-[#0D2C54] text-white text-xs font-bold flex items-center justify-center shrink-0">2</span>
            <div><strong class="text-[#0D2C54] block">Duyệt &amp; kích hoạt nhanh</strong>Quản trị viên duyệt tài khoản và xác nhận mức hoa hồng qua Zalo.</div>
          </li>
          <li class="flex gap-3">
            <span class="w-6 h-6 rounded-full bg-[#0D2C54] text-white text-xs font-bold flex items-center justify-center shrink-0">3</span>
            <div><strong class="text-[#0D2C54] block">Lấy link &amp; nhận hoa hồng</strong>Vào <NuxtLink to="/ctv" class="text-[#C81E2B] font-semibold underline">Cổng CTV</NuxtLink> tạo link gửi khách và đối soát định kỳ.</div>
          </li>
        </ol>
      </section>

      <section id="ctv-register-form" class="lg:col-span-3 card-surface p-5 sm:p-6 space-y-4">
        <div class="flex items-center justify-between gap-3 pb-3 border-b border-slate-200">
          <h2 class="text-base font-bold uppercase text-[#0D2C54] m-0">Đăng ký tài khoản CTV</h2>
          <NuxtLink to="/ctv" class="text-xs font-semibold text-[#0D2C54] hover:text-[#C81E2B] no-underline">Đã có tài khoản? Đăng nhập →</NuxtLink>
        </div>

        <p v-if="errorMsg" role="alert" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3.5 py-2.5 m-0">
          {{ errorMsg }}
        </p>

        <div v-if="registeredInfo" class="rounded-xl bg-green-50 border border-green-200 p-5 text-center space-y-3">
          <div class="w-12 h-12 rounded-full bg-white border border-green-200 text-[#15803D] flex items-center justify-center mx-auto">
            <Check class="w-6 h-6" />
          </div>
          <h3 class="text-base font-bold text-[#0D2C54] m-0">Đăng ký CTV thành công!</h3>
          <p class="text-xs text-slate-600 m-0 leading-relaxed">
            Mã CTV của bạn là <strong class="text-[#0D2C54]">{{ registeredInfo.code }}</strong>.
            {{ registeredInfo.needConfirm ? 'Vui lòng xác nhận email và chờ quản trị viên kích hoạt.' : 'Tài khoản đang ở trạng thái Chờ duyệt — quản trị viên sẽ kích hoạt sớm.' }}
          </p>
          <div class="flex flex-wrap justify-center gap-3 pt-1">
            <NuxtLink to="/ctv" class="btn-cta text-xs px-5">VÀO CỔNG CTV</NuxtLink>
            <a href="https://zalo.me/0963294492" target="_blank" rel="noopener" class="btn-outline text-xs px-5 no-underline">NHẮN ZALO DUYỆT NHANH</a>
          </div>
        </div>

        <form v-else novalidate class="space-y-3.5" @submit.prevent="handleRegister">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3.5">
            <div class="space-y-1">
              <label for="ctv-name" class="text-xs font-semibold text-slate-700 block">Họ và tên *</label>
              <input id="ctv-name" v-model="fullName" type="text" required placeholder="VD: Nguyễn Minh Tuấn" class="field-input">
            </div>
            <div class="space-y-1">
              <label for="ctv-phone" class="text-xs font-semibold text-slate-700 block">Số điện thoại / Zalo *</label>
              <input id="ctv-phone" v-model="phone" type="tel" required placeholder="VD: 0963294492" class="field-input">
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3.5">
            <div class="space-y-1">
              <label for="ctv-email" class="text-xs font-semibold text-slate-700 block">Email đăng nhập *</label>
              <input id="ctv-email" v-model="email" type="email" required placeholder="email@domain.com" class="field-input">
            </div>
            <div class="space-y-1">
              <label for="ctv-password" class="text-xs font-semibold text-slate-700 block">Mật khẩu (tối thiểu 6 ký tự) *</label>
              <input id="ctv-password" v-model="password" type="password" required minlength="6" placeholder="Nhập mật khẩu..." class="field-input">
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3.5">
            <div class="space-y-1">
              <label for="ctv-code" class="text-xs font-semibold text-slate-700 block">Mã CTV mong muốn</label>
              <input id="ctv-code" v-model="codeInput" type="text" placeholder="VD: TUAN01" class="field-input uppercase">
            </div>
            <div class="space-y-1">
              <label for="ctv-job" class="text-xs font-semibold text-slate-700 block">Công việc hiện tại</label>
              <select id="ctv-job" v-model="jobType" class="ymm-select text-xs">
                <option value="Sale hãng xe">Sale hãng xe</option>
                <option value="Chủ Gara / Detailing">Chủ Gara / Detailing</option>
                <option value="Tiệm rửa xe">Tiệm rửa xe</option>
                <option value="Bán hàng online">Bán hàng online</option>
                <option value="Khác">Khác</option>
              </select>
            </div>
            <div class="space-y-1">
              <label for="ctv-area" class="text-xs font-semibold text-slate-700 block">Khu vực / Tỉnh thành</label>
              <input id="ctv-area" v-model="area" type="text" placeholder="VD: Hà Nội" class="field-input">
            </div>
          </div>

          <button type="submit" :disabled="isSubmitting" class="btn-cta w-full text-xs">
            {{ isSubmitting ? 'ĐANG TẠO TÀI KHOẢN...' : 'ĐĂNG KÝ LÀM CỘNG TÁC VIÊN' }}
          </button>
        </form>
      </section>
    </div>
  </main>
</template>
