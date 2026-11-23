<script setup lang="ts">
import { Search, Car } from 'lucide-vue-next';

const route = useRoute();
const router = useRouter();

const activeBrandSlug = ref<string>(route.query.hang ? String(route.query.hang) : 'all');
const searchQuery = ref<string>(route.query.q ? String(route.query.q) : '');

watch(() => route.query.hang, (val) => {
  activeBrandSlug.value = val ? String(val) : 'all';
});

const activeBrand = computed(() =>
  activeBrandSlug.value === 'all' ? null : getBrandByQuery(activeBrandSlug.value)
);

useSeoMeta({
  title: () => activeBrand.value ? `Thảm Lót Sàn Xe ${activeBrand.value.name} - Trung Thành Auto` : 'Tất Cả Dòng Xe - Trung Thành Auto',
  description: 'Chọn đúng dòng xe theo hãng để xem form đời xe và bảng giá thảm lót sàn ô tô chuẩn phom.'
});

const selectBrand = (slug: string) => {
  activeBrandSlug.value = slug;
  searchQuery.value = '';
  router.replace(slug === 'all' ? '/san-pham' : `/san-pham?hang=${slug}`);
};

const filteredModels = computed(() => {
  const raw = searchQuery.value.toLowerCase().trim();
  const norm = toSlug(raw);
  const matches = (text: string) =>
    !raw || text.toLowerCase().includes(raw) || (Boolean(norm) && toSlug(text).includes(norm));

  if (activeBrandSlug.value === 'all') {
    const all: CarModelWithMeta[] = [];
    BRAND_CATALOG.forEach((b) => {
      b.models.forEach((m) => {
        if (matches(`${b.name} ${m.name}`)) {
          all.push({ ...m, brand: b.name, brandSlug: b.slug, slug: toSlug(m.name) });
        }
      });
    });
    return all;
  }
  return getModelsWithMeta(activeBrandSlug.value).filter((m) => matches(m.name));
});

const segments = ['SUV / CUV / MPV', 'SEDAN / HATCHBACK'] as const;
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-5">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54]">{{ activeBrand ? activeBrand.name : 'Tất cả dòng xe' }}</span>
    </nav>

    <!-- Brand Quick-Switch Bar -->
    <div id="brand-tabs-bar" class="flex flex-wrap gap-2">
      <button
        type="button"
        class="inline-flex items-center gap-1.5 min-h-[40px] px-3.5 rounded-lg text-xs font-semibold cursor-pointer transition"
        :class="activeBrandSlug === 'all'
          ? 'bg-[#FEF2F2] text-[#C81E2B] border-2 border-[#C81E2B] shadow-sm'
          : 'bg-white text-slate-700 border border-slate-200 hover:border-[#0D2C54] hover:text-[#0D2C54]'"
        @click="selectBrand('all')"
      >
        <Car class="w-4 h-4 shrink-0" />
        <span>Tất cả</span>
      </button>

      <button
        v-for="b in BRAND_CATALOG"
        :key="b.slug"
        type="button"
        class="inline-flex items-center gap-1.5 min-h-[40px] px-3 rounded-lg text-xs font-semibold cursor-pointer transition"
        :class="activeBrandSlug === b.slug
          ? 'bg-[#FEF2F2] text-[#C81E2B] border-2 border-[#C81E2B] shadow-sm'
          : 'bg-white text-slate-700 border border-slate-200 hover:border-[#0D2C54] hover:text-[#0D2C54]'"
        @click="selectBrand(b.slug)"
      >
        <img :src="b.logo" :alt="b.name" width="22" height="22" class="w-5 h-5 object-contain shrink-0">
        <span>{{ b.name }}</span>
      </button>
    </div>

    <!-- Custom-Fit Banner (placed above heading as requested) -->
    <div class="card-surface p-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 bg-[#F8FAFC]">
      <p class="text-xs sm:text-sm text-slate-700 m-0">
        <strong class="text-[#0D2C54]">Xe của bạn chưa có trong danh sách?</strong> Nhắn Zalo hoặc để lại thông tin để kỹ thuật viên hỗ trợ đo phom miễn phí.
      </p>
      <div class="flex items-center gap-2.5 shrink-0">
        <a href="https://zalo.me/0963294492" target="_blank" rel="noopener" class="btn-outline text-xs px-4 min-h-[40px] no-underline">Chat Zalo</a>
        <NuxtLink to="/lien-he" class="btn-cta text-xs px-4 min-h-[40px] no-underline">GỬI YÊU CẦU</NuxtLink>
      </div>
    </div>

    <!-- Heading + Quick Search -->
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
      <div>
        <h1 class="section-heading m-0">
          {{ activeBrand ? `CHỌN DÒNG XE ${activeBrand.name.toUpperCase()}` : 'TẤT CẢ DÒNG XE' }}
        </h1>
        <p class="text-xs text-slate-500 mt-1 m-0">Chọn đúng dòng xe của bạn để xem form đời xe và bảng giá chi tiết.</p>
      </div>

      <div class="relative w-full sm:w-72">
        <input
          v-model="searchQuery"
          type="search"
          :placeholder="activeBrand ? `Tìm dòng xe ${activeBrand.name}...` : 'Tìm nhanh tên hãng hoặc dòng xe...'"
          class="field-input pr-10 text-xs"
        >
        <Search class="w-4 h-4 text-slate-400 absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none" />
      </div>
    </div>

    <!-- Empty State -->
    <div v-if="filteredModels.length === 0" class="card-surface p-8 text-center space-y-3">
      <p class="text-sm font-semibold text-slate-700 m-0">Không tìm thấy dòng xe phù hợp.</p>
      <NuxtLink to="/lien-he" class="btn-cta text-xs px-6">ĐẶT ĐO PHOM RIÊNG THEO XE</NuxtLink>
    </div>

    <!-- Segments -->
    <div v-else class="space-y-7">
      <template v-for="seg in segments" :key="seg">
        <section v-if="filteredModels.some((m) => m.segment === seg)" class="space-y-3">
          <div class="flex items-center justify-between border-b border-slate-200 pb-2">
            <h2 class="text-sm md:text-base font-bold uppercase tracking-wide text-[#0D2C54] m-0">{{ seg }}</h2>
            <span class="text-xs font-semibold text-slate-500 tabular-nums">
              {{ filteredModels.filter((m) => m.segment === seg).length }} dòng xe
            </span>
          </div>

          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3.5 md:gap-5">
            <NuxtLink
              v-for="m in filteredModels.filter((x) => x.segment === seg)"
              :key="`${m.brandSlug}-${m.slug}`"
              :to="`/chi-tiet?hang=${m.brandSlug}&xe=${m.slug}`"
              class="model-card"
            >
              <div class="aspect-[16/9] bg-slate-100 overflow-hidden">
                <img :src="m.image" :alt="`Thảm lót sàn ${m.brand} ${m.name}`" width="640" height="360" loading="lazy" class="w-full h-full object-cover object-center">
              </div>
              <div class="model-card__footer">
                {{ activeBrandSlug === 'all' ? `${m.brand} ${m.name}` : m.name }}
              </div>
            </NuxtLink>
          </div>
        </section>
      </template>
    </div>
  </main>
</template>
