<script setup lang="ts">
const route = useRoute();
const slug = computed(() => String(route.params.slug || '').replace(/\.html$/, ''));
const article = computed(() => NEWS_ARTICLES.find((a) => a.slug === slug.value) || NEWS_ARTICLES[0]!);
const related = computed(() => NEWS_ARTICLES.filter((a) => a.id !== article.value.id).slice(0, 3));

useSeoMeta({
  title: () => `${article.value.title} | Trung Thành Auto`,
  description: () => article.value.desc
});
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-6">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <NuxtLink to="/tin-tuc">Tin tức</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54] truncate max-w-md">{{ article.title }}</span>
    </nav>

    <article class="max-w-3xl mx-auto card-surface overflow-hidden">
      <div class="aspect-[16/9] bg-slate-100">
        <img :src="article.image" :alt="article.title" width="800" height="450" class="w-full h-full object-cover">
      </div>
      <div class="p-5 sm:p-8 space-y-4">
        <span class="text-xs font-semibold text-[#C81E2B] uppercase">{{ article.categoryLabel }} · {{ article.date }}</span>
        <h1 class="text-xl sm:text-2xl font-bold text-[#0D2C54] m-0 leading-snug">{{ article.title }}</h1>
        <p class="text-sm font-semibold text-slate-700 m-0 leading-relaxed">{{ article.desc }}</p>
        <div class="space-y-3.5 text-sm text-slate-700 leading-relaxed pt-2 border-t border-slate-100">
          <p v-for="(para, i) in article.content" :key="i" class="m-0">{{ para }}</p>
        </div>
        <div class="pt-4 border-t border-slate-200 flex flex-wrap items-center justify-between gap-3">
          <NuxtLink to="/san-pham" class="btn-cta text-xs px-5">CHỌN THẢM THEO DÒNG XE</NuxtLink>
          <NuxtLink to="/tin-tuc" class="btn-outline text-xs px-5">← Quay lại danh sách tin</NuxtLink>
        </div>
      </div>
    </article>

    <section class="max-w-3xl mx-auto space-y-3">
      <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Bài viết liên quan</h2>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <NuxtLink
          v-for="r in related"
          :key="r.id"
          :to="`/tin-tuc/${r.slug}`"
          class="card-surface p-3.5 space-y-1.5 no-underline hover:border-[#0D2C54] transition"
        >
          <span class="text-[10px] font-semibold text-[#C81E2B] uppercase">{{ r.categoryLabel }}</span>
          <h3 class="text-xs font-semibold text-slate-900 m-0 line-clamp-2">{{ r.title }}</h3>
        </NuxtLink>
      </div>
    </section>
  </main>
</template>
