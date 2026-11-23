<script setup lang="ts">
import { Search, ShieldCheck, Truck, RefreshCw, Star, X } from 'lucide-vue-next';

useSeoMeta({
  title: 'Trung Thành Auto | Thảm Lót Sàn Ô Tô Chuẩn Phom Xe',
  description: 'Tìm thảm lót sàn ô tô 6D, 360 độ, nhựa TPE chính xác theo hãng xe, dòng xe và năm sản xuất. Vừa vặn 100%, lắp tại nhà, đổi trả 1-1.'
});

const router = useRouter();

const selectedBrand = ref('');
const selectedModel = ref('');
const selectedYear = ref('');

const availableModels = computed(() => {
  const b = BRAND_CATALOG.find((x) => x.name === selectedBrand.value);
  return b ? b.models : [];
});

const availableYears = computed(() => {
  const m = availableModels.value.find((x) => x.name === selectedModel.value);
  return m ? m.years : [];
});

watch(selectedBrand, () => {
  selectedModel.value = '';
  selectedYear.value = '';
});

watch(selectedModel, () => {
  selectedYear.value = '';
});

const canSearch = computed(() => Boolean(selectedBrand.value && selectedModel.value && selectedYear.value));

const handleYmmSubmit = () => {
  if (!canSearch.value) return;
  const hangSlug = toSlug(selectedBrand.value);
  const xeSlug = toSlug(selectedModel.value);
  router.push(`/chi-tiet?hang=${hangSlug}&xe=${xeSlug}&nam=${encodeURIComponent(selectedYear.value)}`);
};

const bestSellers = [
  { id: 4, name: 'Thảm 6D Cao Cấp', material: 'Thảm 6D Cao Cấp', price: 1500000, image: '/assets/images/mat-6d-red.webp' },
  { id: 12, name: 'Thảm 360 Full Xe', material: 'Thảm 360 Full Xe', price: 2200000, image: '/assets/images/mat-carbon-gold.webp' },
  { id: 2, name: 'Thảm Nhựa TPE Đúc Khuôn', material: 'Thảm Nhựa TPE Đúc Khuôn', price: 1890000, image: '/assets/images/mat-tpe-black.webp' },
  { id: 3, name: 'Thảm Da 5D Quả Trám', material: 'Thảm Da 5D Quả Trám', price: 1250000, image: '/assets/images/mat-5d-brown.webp' }
];

const installations = [
  { image: '/assets/images/install-fortuner.webp', title: 'Toyota Fortuner 2021', desc: 'Thảm 6D Đen chỉ đỏ + Rối chống bẩn', reviewer: 'Anh Hoàng · Đống Đa' },
  { image: '/assets/images/install-santafe.webp', title: 'Hyundai SantaFe 2023', desc: 'Thảm 360 Full sàn Nâu cafe', reviewer: 'Anh Tuấn · Cầu Giấy' },
  { image: '/assets/images/install-cx5.webp', title: 'Mazda CX-5 2022', desc: 'Thảm Da Carbon Đen chỉ vàng', reviewer: 'Chị Hương · Thanh Xuân' },
  { image: '/assets/images/install-crv.webp', title: 'Honda CR-V 2024', desc: 'Thảm Nhựa TPE Đúc Khuôn 3D', reviewer: 'Anh Minh · Long Biên' }
];

const lightboxItem = ref<{ image: string; title: string; desc: string } | null>(null);
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-8 md:space-y-10">
    <!-- 1. YMM Filter -->
    <section aria-labelledby="ymm-heading" class="card-surface p-4 sm:p-6">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-4">
        <div>
          <h1 id="ymm-heading" class="text-base sm:text-xl font-bold uppercase text-[#0D2C54] m-0">
            TÌM THẢM CHUẨN PHOM THEO XE CỦA BẠN
          </h1>
          <p class="text-xs sm:text-sm text-slate-500 mt-1 m-0">
            Chọn Hãng → Dòng xe → Năm sản xuất để xem phom và báo giá chính xác.
          </p>
        </div>
        <NuxtLink to="/lien-he" class="text-xs font-semibold text-[#C81E2B] hover:underline no-underline shrink-0">
          Đặt may đo riêng theo xe →
        </NuxtLink>
      </div>

      <form class="grid grid-cols-1 md:grid-cols-4 gap-3" @submit.prevent="handleYmmSubmit">
        <select v-model="selectedBrand" aria-label="Chọn Hãng Xe" class="ymm-select">
          <option value="">1. Chọn Hãng Xe</option>
          <option v-for="b in BRAND_CATALOG" :key="b.slug" :value="b.name">{{ b.name }}</option>
        </select>

        <select v-model="selectedModel" :disabled="!selectedBrand" aria-label="Chọn Dòng Xe" class="ymm-select">
          <option value="">2. Chọn Dòng Xe</option>
          <option v-for="m in availableModels" :key="m.name" :value="m.name">{{ m.name }}</option>
        </select>

        <select v-model="selectedYear" :disabled="!selectedModel" aria-label="Chọn Năm Sản Xuất" class="ymm-select">
          <option value="">3. Chọn Năm Sản Xuất</option>
          <option v-for="y in availableYears" :key="y" :value="y">{{ y }}</option>
        </select>

        <button type="submit" :disabled="!canSearch" class="btn-cta w-full text-xs sm:text-sm">
          <Search class="w-4 h-4" />
          <span>TÌM KIẾM NGAY</span>
        </button>
      </form>

      <div class="mt-4 pt-3.5 border-t border-slate-100 grid grid-cols-3 gap-2 text-[11px] sm:text-xs text-slate-600">
        <div class="flex items-center gap-1.5">
          <ShieldCheck class="w-4 h-4 text-[#0D2C54] shrink-0" />
          <span>Chuẩn phom 100%</span>
        </div>
        <div class="flex items-center gap-1.5">
          <Truck class="w-4 h-4 text-[#0D2C54] shrink-0" />
          <span>Lắp tại nhà miễn phí</span>
        </div>
        <div class="flex items-center gap-1.5">
          <RefreshCw class="w-4 h-4 text-[#0D2C54] shrink-0" />
          <span>Đổi trả 1-1 · BH 24T</span>
        </div>
      </div>
    </section>

    <!-- 2. Brands Grid -->
    <section aria-labelledby="brands-heading" class="space-y-4">
      <div class="flex items-center justify-between gap-3">
        <h2 id="brands-heading" class="section-heading">CHỌN THEO HÃNG XE</h2>
        <NuxtLink to="/san-pham" class="text-xs font-semibold text-[#0D2C54] hover:text-[#C81E2B] no-underline shrink-0">
          Xem tất cả →
        </NuxtLink>
      </div>

      <div class="flex md:grid md:grid-cols-4 lg:grid-cols-6 gap-3 overflow-x-auto md:overflow-visible no-scrollbar pb-1">
        <NuxtLink
          v-for="b in BRAND_CATALOG"
          :key="b.slug"
          :to="`/san-pham?hang=${b.slug}`"
          class="brand-circle-card"
        >
          <div class="brand-circle-badge p-2.5">
            <img :src="b.logo" :alt="`Logo ${b.name}`" width="40" height="40" loading="lazy" class="w-full h-full object-contain">
          </div>
          <span class="brand-circle-name text-xs font-semibold text-[#0D2C54] text-center leading-tight uppercase">{{ b.name }}</span>
          <span class="hidden lg:block text-[11px] font-medium text-slate-500 tabular-nums">{{ b.models.length }} dòng xe</span>
        </NuxtLink>
      </div>
    </section>

    <!-- 3. Best Sellers -->
    <section aria-labelledby="bestsellers-heading" class="space-y-4">
      <div class="flex items-center justify-between gap-3">
        <h2 id="bestsellers-heading" class="section-heading">SẢN PHẨM BÁN CHẠY</h2>
        <NuxtLink to="/san-pham" class="text-xs font-semibold text-[#0D2C54] hover:text-[#C81E2B] no-underline shrink-0">
          Chọn theo xe →
        </NuxtLink>
      </div>

      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3.5 md:gap-5">
        <NuxtLink
          v-for="p in bestSellers"
          :key="p.id"
          :to="`/chi-tiet?material=${encodeURIComponent(p.material)}`"
          class="card-surface overflow-hidden flex flex-col group no-underline hover:border-[#0D2C54] transition"
        >
          <div class="aspect-[4/3] bg-slate-100 overflow-hidden">
            <img :src="p.image" :alt="p.name" width="360" height="270" loading="lazy" class="w-full h-full object-cover group-hover:scale-105 transition duration-300">
          </div>
          <div class="p-3.5 space-y-1.5 flex-1 flex flex-col justify-between">
            <h3 class="text-xs sm:text-sm font-semibold text-slate-900 m-0 leading-snug group-hover:text-[#0D2C54]">{{ p.name }}</h3>
            <p class="text-sm font-bold text-[#15803D] m-0 tabular-nums">{{ formatCurrency(p.price) }}</p>
          </div>
        </NuxtLink>
      </div>
    </section>

    <!-- 4. Customer Installations -->
    <section aria-labelledby="installations-heading" class="space-y-4">
      <div class="flex items-center justify-between gap-3">
        <h2 id="installations-heading" class="section-heading">KHÁCH HÀNG LẮP ĐẶT THỰC TẾ</h2>
        <span class="text-xs text-slate-500 hidden sm:inline">Ảnh chụp trực tiếp tại xưởng &amp; lắp tại nhà</span>
      </div>

      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3.5 md:gap-5">
        <button
          v-for="item in installations"
          :key="item.title"
          type="button"
          class="card-surface overflow-hidden text-left p-0 cursor-pointer group hover:border-[#0D2C54] transition"
          @click="lightboxItem = item"
        >
          <div class="aspect-[4/3] bg-slate-100 overflow-hidden">
            <img :src="item.image" :alt="item.title" width="360" height="270" loading="lazy" class="w-full h-full object-cover group-hover:scale-105 transition duration-300">
          </div>
          <div class="p-3 space-y-1">
            <div class="flex items-center gap-0.5 text-[#F59E0B]">
              <Star v-for="n in 5" :key="n" class="w-3 h-3 fill-current" />
            </div>
            <p class="text-xs sm:text-sm font-bold text-[#0D2C54] m-0 tabular-nums">{{ item.title }}</p>
            <p class="text-[11px] text-slate-600 m-0 line-clamp-1">{{ item.desc }}</p>
            <p class="text-[10px] text-slate-400 m-0">{{ item.reviewer }}</p>
          </div>
        </button>
      </div>
    </section>

    <!-- Lightbox Modal -->
    <Teleport to="body">
      <div v-if="lightboxItem" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-slate-900/75" @click="lightboxItem = null" />
        <div class="relative z-10 bg-white rounded-2xl max-w-2xl w-full overflow-hidden shadow-2xl">
          <button
            type="button"
            class="absolute top-3 right-3 icon-touch-btn rounded-full bg-white/90 text-slate-800 shadow"
            aria-label="Đóng ảnh"
            @click="lightboxItem = null"
          >
            <X class="w-5 h-5" />
          </button>
          <img :src="lightboxItem.image" :alt="lightboxItem.title" class="w-full max-h-[70vh] object-cover">
          <div class="p-4 text-center">
            <p class="text-sm font-semibold text-[#0D2C54] m-0">{{ lightboxItem.title }} — {{ lightboxItem.desc }}</p>
          </div>
        </div>
      </div>
    </Teleport>
  </main>
</template>
