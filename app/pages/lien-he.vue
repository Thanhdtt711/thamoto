<script setup lang="ts">
import { Check } from 'lucide-vue-next';

useSeoMeta({
  title: 'Liên Hệ & Đặt Đo Xe | Trung Thành Auto',
  description: 'Liên hệ hotline hoặc đặt lịch đo lắp thảm lót sàn ô tô tại nhà với Trung Thành Auto.'
});

const { supabase, isConfigured } = useSupabase();
const { getRefCode } = useAffiliate();

const name = ref('');
const phone = ref('');
const brand = ref('');
const model = ref('');
const year = ref('');
const message = ref('');
const formError = ref('');
const isSubmitting = ref(false);
const showSuccess = ref(false);

const models = computed(() => BRAND_CATALOG.find((b) => b.name === brand.value)?.models || []);
const years = computed(() => models.value.find((m) => m.name === model.value)?.years || []);

watch(brand, () => { model.value = ''; year.value = ''; });
watch(model, () => { year.value = ''; });

const handleSubmit = async () => {
  const cleanPhone = phone.value.replace(/\s+/g, '');
  if (name.value.trim().length < 2) {
    formError.value = 'Vui lòng nhập họ tên của bạn (ít nhất 2 ký tự).';
    return;
  }
  if (!/^0[35789]\d{8}$/.test(cleanPhone)) {
    formError.value = 'Số điện thoại không hợp lệ. Vui lòng nhập đúng 10 số (VD: 0963294492).';
    return;
  }
  formError.value = '';
  isSubmitting.value = true;

  try {
    if (isConfigured && supabase) {
      const vehicleStr = [brand.value, model.value, year.value].filter(Boolean).join(' ');
      const { error } = await supabase.from('leads').insert({
        customer_name: name.value.trim(),
        phone: cleanPhone,
        vehicle: vehicleStr || null,
        message: message.value.trim() || null,
        affiliate_code: getRefCode() || null
      });
      if (error) throw error;
    }
    showSuccess.value = true;
  } catch {
    formError.value = 'Không thể gửi yêu cầu lúc này. Vui lòng thử lại hoặc nhắn Zalo 0963 294 492.';
  } finally {
    isSubmitting.value = false;
  }
};

const closeSuccess = () => {
  showSuccess.value = false;
  name.value = '';
  phone.value = '';
  brand.value = '';
  model.value = '';
  year.value = '';
  message.value = '';
};
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-6">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54]">Liên hệ</span>
    </nav>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 items-start">
      <div class="space-y-4">
        <h1 class="section-heading">LIÊN HỆ TƯ VẤN &amp; LẮP ĐẶT TẠI NHÀ</h1>
        <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
          Đặt lịch đo phom hoặc nhận tư vấn chọn chất liệu thảm 6D, 360 độ, nhựa TPE phù hợp nhất cho xe của bạn.
        </p>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3.5">
          <div class="card-surface p-4 space-y-1.5">
            <span class="text-xs font-semibold uppercase text-slate-500">Hotline 24/7</span>
            <a href="tel:0963294492" class="text-base font-bold text-[#C81E2B] block tabular-nums no-underline">0963 294 492</a>
          </div>
          <div class="card-surface p-4 space-y-1.5">
            <span class="text-xs font-semibold uppercase text-slate-500">Zalo Tư Vấn</span>
            <a href="https://zalo.me/0963294492" target="_blank" rel="noopener" class="text-base font-bold text-[#0D2C54] block no-underline">Chat Zalo Ngay</a>
          </div>
          <div class="card-surface p-4 space-y-1">
            <span class="text-xs font-semibold uppercase text-[#0D2C54]">Email</span>
            <a href="mailto:dothanh0711@gmail.com" class="text-xs font-semibold text-slate-700 hover:text-[#0D2C54] block no-underline">dothanh0711@gmail.com</a>
          </div>
          <div class="card-surface p-4 space-y-1">
            <span class="text-xs font-semibold uppercase text-[#0D2C54]">Địa chỉ</span>
            <p class="text-xs text-slate-600 m-0">Yên Lãng, Hà Nội</p>
          </div>
        </div>
      </div>

      <div class="card-surface p-5 sm:p-6 space-y-4">
        <h2 class="text-base font-bold uppercase text-[#0D2C54] pb-3 border-b border-slate-200 m-0">Đăng ký tư vấn nhanh</h2>

        <form novalidate class="space-y-3.5" @submit.prevent="handleSubmit">
          <p v-if="formError" role="alert" class="text-xs font-semibold text-[#C81E2B] bg-[#FEF2F2] border border-[#C81E2B]/30 rounded-lg px-3.5 py-2.5 m-0">
            {{ formError }}
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label for="contact-name" class="text-xs font-semibold text-slate-700 block mb-1">Họ tên *</label>
              <input id="contact-name" v-model="name" type="text" required placeholder="Nhập họ tên..." class="field-input">
            </div>
            <div>
              <label for="contact-phone" class="text-xs font-semibold text-slate-700 block mb-1">Số điện thoại *</label>
              <input id="contact-phone" v-model="phone" type="tel" required placeholder="Nhập SĐT..." class="field-input">
            </div>
          </div>

          <div class="grid grid-cols-3 gap-2">
            <select v-model="brand" class="ymm-select text-xs" aria-label="Hãng xe">
              <option value="">Hãng xe</option>
              <option v-for="b in BRAND_CATALOG" :key="b.slug" :value="b.name">{{ b.name }}</option>
            </select>
            <select v-model="model" :disabled="!brand" class="ymm-select text-xs" aria-label="Dòng xe">
              <option value="">Dòng xe</option>
              <option v-for="m in models" :key="m.name" :value="m.name">{{ m.name }}</option>
            </select>
            <select v-model="year" :disabled="!model" class="ymm-select text-xs" aria-label="Năm sản xuất">
              <option value="">Năm SX</option>
              <option v-for="y in years" :key="y" :value="y">{{ y }}</option>
            </select>
          </div>

          <div>
            <label for="contact-message" class="text-xs font-semibold text-slate-700 block mb-1">Nội dung yêu cầu</label>
            <textarea id="contact-message" v-model="message" rows="3" placeholder="Loại thảm quan tâm, địa chỉ lắp đặt..." class="field-input min-h-[84px] resize-none" />
          </div>

          <button type="submit" :disabled="isSubmitting" class="btn-cta w-full text-xs">
            {{ isSubmitting ? 'ĐANG GỬI YÊU CẦU...' : 'GỬI YÊU CẦU TƯ VẤN' }}
          </button>
        </form>
      </div>
    </div>

    <Teleport to="body">
      <div v-if="showSuccess" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-slate-900/60" @click="closeSuccess" />
        <div class="bg-white border border-slate-200 rounded-2xl p-6 text-center max-w-sm w-full relative z-10 shadow-2xl space-y-3">
          <div class="w-12 h-12 rounded-full bg-green-50 border border-green-200 text-[#15803D] flex items-center justify-center mx-auto">
            <Check class="w-6 h-6" />
          </div>
          <h3 class="font-bold text-[#0D2C54] m-0">Gửi Yêu Cầu Thành Công!</h3>
          <p class="text-xs text-slate-600 m-0">Kỹ thuật viên Trung Thành Auto sẽ liên hệ lại với bạn trong 15 phút.</p>
          <button type="button" class="btn-cta w-full text-xs" @click="closeSuccess">ĐỒNG Ý</button>
        </div>
      </div>
    </Teleport>
  </main>
</template>
