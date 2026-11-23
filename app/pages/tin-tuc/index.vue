<script setup lang="ts">
useSeoMeta({
  title: 'Tin Tức & Kinh Nghiệm Chọn Thảm Ô Tô | Trung Thành Auto',
  description: 'Kinh nghiệm chọn thảm lót sàn ô tô 6D, 360 độ, nhựa TPE và hướng dẫn vệ sinh bảo quản từ chuyên gia Trung Thành Auto.'
});

const activeCategory = ref<'all' | 'kinh-nghiem' | 'xu-huong' | 'su-kien'>('all');
const searchQuery = ref('');

const featuredArticle = computed(() => NEWS_ARTICLES.find((a) => a.featured) || NEWS_ARTICLES[0]!);
const filteredArticles = computed(() => {
  const q = searchQuery.value.trim().toLowerCase();
  return NEWS_ARTICLES.filter((a) => {
    if (a.id === featuredArticle.value.id && !q && activeCategory.value === 'all') return false;
    if (activeCategory.value !== 'all' && a.category !== activeCategory.value) return false;
    if (q && !a.title.toLowerCase().includes(q) && !a.desc.toLowerCase().includes(q)) return false;
    return true;
  });
});

const tabs = [
  { key: 'all', label: 'Tất cả' },
  { key: 'kinh-nghiem', label: 'Kinh nghiệm' },
  { key: 'xu-huong', label: 'Xu hướng' },
  { key: 'su-kien', label: 'Sự kiện' }
] as const;
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-6">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54]">Tin tức</span>
    </nav>

    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
      <h1 class="section-heading m-0">TIN TỨC &amp; KINH NGHIỆM</h1>
      <input v-model="searchQuery" type="search" placeholder="Tìm bài viết..." class="field-input sm:w-64 text-xs">
    </div>

    <div class="flex flex-wrap gap-2">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        class="px-4 py-2 rounded-lg text-xs font-semibold border cursor-pointer transition"
        :class="activeCategory === tab.key
          ? 'bg-[#0D2C54] text-white border-[#0D2C54]'
          : 'bg-white text-slate-700 border-slate-200 hover:border-[#0D2C54]'"
        @click="activeCategory = tab.key"
      >
        {{ tab.label }}
      </button>
    </div>

    <!-- Featured Article -->
    <NuxtLink
      v-if="activeCategory === 'all' && !searchQuery"
      :to="`/tin-tuc/${featuredArticle.slug}`"
      class="card-surface overflow-hidden grid grid-cols-1 lg:grid-cols-2 group no-underline hover:border-[#0D2C54] transition"
    >
      <div class="aspect-[16/10] bg-slate-100 overflow-hidden">
        <img :src="featuredArticle.image" :alt="featuredArticle.title" width="640" height="400" class="w-full h-full object-cover group-hover:scale-105 transition duration-300">
      </div>
      <div class="p-5 sm:p-7 flex flex-col justify-center space-y-3">
        <span class="text-xs font-semibold text-[#C81E2B] uppercase">{{ featuredArticle.categoryLabel }} · {{ featuredArticle.date }}</span>
        <h2 class="text-lg sm:text-xl font-bold text-[#0D2C54] m-0 leading-snug group-hover:text-[#C81E2B] transition">
          {{ featuredArticle.title }}
        </h2>
        <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">{{ featuredArticle.desc }}</p>
        <span class="text-xs font-semibold text-[#0D2C54]">Đọc bài viết →</span>
      </div>
    </NuxtLink>

    <!-- Grid -->
    <div v-if="filteredArticles.length === 0" class="card-surface p-8 text-center text-xs text-slate-500">
      Không tìm thấy bài viết phù hợp.
    </div>
    <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
      <NuxtLink
        v-for="a in filteredArticles"
        :key="a.id"
        :to="`/tin-tuc/${a.slug}`"
        class="card-surface overflow-hidden flex flex-col group no-underline hover:border-[#0D2C54] transition"
      >
        <div class="aspect-[16/10] bg-slate-100 overflow-hidden">
          <img :src="a.image" :alt="a.title" width="400" height="250" loading="lazy" class="w-full h-full object-cover group-hover:scale-105 transition duration-300">
        </div>
        <div class="p-4 flex-1 flex flex-col justify-between gap-3">
          <div class="space-y-1.5">
            <span class="text-[11px] font-semibold text-[#C81E2B] uppercase">{{ a.categoryLabel }} · {{ a.date }}</span>
            <h3 class="font-semibold text-slate-900 text-sm m-0 leading-snug group-hover:text-[#0D2C54] line-clamp-2">{{ a.title }}</h3>
            <p class="text-xs text-slate-600 m-0 leading-relaxed line-clamp-2">{{ a.desc }}</p>
          </div>
          <span class="text-xs font-semibold text-[#0D2C54]">Đọc tiếp →</span>
        </div>
      </NuxtLink>
    </div>
  </main>
</template>
