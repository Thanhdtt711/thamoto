<script setup lang="ts">
import { Search, ShoppingBag, ChevronLeft } from 'lucide-vue-next';

const route = useRoute();
const router = useRouter();
const { totalCount, openDrawer } = useCart();

const searchQuery = ref('');
const isHome = computed(() => route.path === '/');

const pageTitle = computed(() => {
  const map: Record<string, string> = {
    '/san-pham': 'CHỌN DÒNG XE',
    '/chi-tiet': 'CHỌN ĐỜI XE & CẤU HÌNH',
    '/gio-hang': 'GIỎ HÀNG',
    '/thanh-toan': 'THANH TOÁN',
    '/gioi-thieu': 'GIỚI THIỆU',
    '/tin-tuc': 'TIN TỨC',
    '/lien-he': 'LIÊN HỆ',
    '/cong-tac-vien': 'CỘNG TÁC VIÊN',
    '/ctv': 'CỔNG CTV',
    '/admin': 'QUẢN TRỊ ADMIN'
  };
  if (route.path.startsWith('/tin-tuc/')) return 'CHI TIẾT TIN TỨC';
  return map[route.path] || 'TRUNG THÀNH AUTO';
});

const handleSearch = () => {
  const q = searchQuery.value.trim();
  router.push(q ? `/san-pham?q=${encodeURIComponent(q)}` : '/san-pham');
};

const goBack = () => {
  if (import.meta.client && window.history.length > 1) {
    router.back();
  } else {
    router.push('/');
  }
};

const navLinks = [
  { label: 'TRANG CHỦ', to: '/' },
  { label: 'SẢN PHẨM', to: '/san-pham' },
  { label: 'TIN TỨC', to: '/tin-tuc' },
  { label: 'LIÊN HỆ', to: '/lien-he' }
];
</script>

<template>
  <header class="sticky top-0 z-40 bg-[#0D2C54] text-white shadow-md">
    <!-- Mobile Home Header -->
    <div v-if="isHome" class="lg:hidden container-app h-14 flex items-center justify-between gap-2.5">
      <NuxtLink to="/" class="flex items-center gap-2 no-underline shrink-0">
        <svg class="w-8 h-8 shrink-0" viewBox="0 0 36 36" fill="none" aria-hidden="true">
          <rect width="36" height="36" rx="8" fill="#C81E2B" />
          <path d="M8 12.5C8 11.1193 9.11929 10 10.5 10H25.5C26.8807 10 28 11.1193 28 12.5V22L23.5 26.5H12.5L8 22V12.5Z" stroke="white" stroke-width="2" stroke-linejoin="round" />
          <path d="M13 15.5H23M18 15.5V22" stroke="white" stroke-width="2.2" stroke-linecap="round" />
        </svg>
        <div class="leading-none">
          <span class="block text-xs font-bold tracking-tight text-white">TRUNG THÀNH</span>
          <span class="block text-[9px] font-semibold tracking-widest text-slate-300 mt-0.5">THẢM LÓT SÀN</span>
        </div>
      </NuxtLink>

      <form class="flex-1 min-w-0 relative" @submit.prevent="handleSearch">
        <input
          v-model="searchQuery"
          type="search"
          placeholder="Tìm xe (VD: Fortuner, CX-5)..."
          aria-label="Tìm kiếm dòng xe"
          class="w-full h-10 rounded-lg bg-white text-slate-900 placeholder:text-slate-400 text-xs pl-3 pr-9 border-0 focus:outline-none focus:ring-2 focus:ring-[#C81E2B]"
        >
        <button type="submit" class="absolute right-0 top-0 h-10 w-9 flex items-center justify-center text-slate-500 hover:text-[#0D2C54]" aria-label="Tìm kiếm">
          <Search class="w-4 h-4" />
        </button>
      </form>

      <button type="button" class="icon-touch-btn relative text-white hover:bg-white/10 rounded-lg transition shrink-0" aria-label="Mở giỏ hàng" @click="openDrawer">
        <ShoppingBag class="w-5 h-5" />
        <span v-if="totalCount > 0" class="absolute top-1.5 right-1.5 bg-[#C81E2B] text-white text-[10px] font-semibold rounded-full min-w-[18px] h-[18px] px-1 flex items-center justify-center border border-[#0D2C54] tabular-nums">
          {{ totalCount }}
        </span>
      </button>
    </div>

    <!-- Mobile Subpage Header -->
    <div v-else class="lg:hidden container-app h-14 flex items-center justify-between gap-2">
      <button type="button" class="icon-touch-btn -ml-2 text-white hover:bg-white/10 rounded-lg transition shrink-0" aria-label="Quay lại" @click="goBack">
        <ChevronLeft class="w-6 h-6" />
      </button>
      <span class="text-sm font-bold uppercase tracking-wide text-white truncate flex-1 text-center">
        {{ pageTitle }}
      </span>
      <button type="button" class="icon-touch-btn relative text-white hover:bg-white/10 rounded-lg transition shrink-0" aria-label="Mở giỏ hàng" @click="openDrawer">
        <ShoppingBag class="w-5 h-5" />
        <span v-if="totalCount > 0" class="absolute top-1.5 right-1.5 bg-[#C81E2B] text-white text-[10px] font-semibold rounded-full min-w-[18px] h-[18px] px-1 flex items-center justify-center border border-[#0D2C54] tabular-nums">
          {{ totalCount }}
        </span>
      </button>
    </div>

    <!-- Desktop Header -->
    <div class="hidden lg:flex container-app h-[68px] items-center justify-between gap-6">
      <NuxtLink to="/" class="flex items-center gap-3 no-underline shrink-0 group">
        <svg class="w-10 h-10 shrink-0" viewBox="0 0 36 36" fill="none" aria-hidden="true">
          <rect width="36" height="36" rx="8" fill="#C81E2B" />
          <path d="M8 12.5C8 11.1193 9.11929 10 10.5 10H25.5C26.8807 10 28 11.1193 28 12.5V22L23.5 26.5H12.5L8 22V12.5Z" stroke="white" stroke-width="2" stroke-linejoin="round" />
          <path d="M13 15.5H23M18 15.5V22" stroke="white" stroke-width="2.2" stroke-linecap="round" />
        </svg>
        <div class="leading-none">
          <span class="block text-[15px] font-bold tracking-tight text-white mb-1">TRUNG THÀNH AUTO</span>
          <span class="block text-[10px] font-semibold text-slate-300 mt-0.5">Thảm lót sàn ô tô</span>
        </div>
      </NuxtLink>

      <nav class="flex items-center gap-1" aria-label="Điều hướng chính">
        <NuxtLink
          v-for="item in navLinks"
          :key="item.to"
          :to="item.to"
          class="px-3.5 py-2 rounded-lg text-[13px] font-semibold no-underline transition whitespace-nowrap"
          :class="route.path === item.to || (item.to !== '/' && route.path.startsWith(item.to)) ? 'text-white bg-white/15' : 'text-slate-200 hover:text-white hover:bg-white/10'"
        >
          {{ item.label }}
        </NuxtLink>
      </nav>

      <div class="flex items-center gap-3">
        <form class="relative w-60 xl:w-72" @submit.prevent="handleSearch">
          <input
            v-model="searchQuery"
            type="search"
            placeholder="Tìm xe (VD: Fortuner, CX-5)..."
            aria-label="Tìm kiếm dòng xe"
            class="w-full h-10 rounded-lg bg-white text-slate-900 placeholder:text-slate-400 text-xs pl-3.5 pr-9 border-0 focus:outline-none focus:ring-2 focus:ring-[#C81E2B]"
          >
          <button type="submit" class="absolute right-0 top-0 h-10 w-9 flex items-center justify-center text-slate-500 hover:text-[#0D2C54]" aria-label="Tìm kiếm">
            <Search class="w-4 h-4" />
          </button>
        </form>

        <button type="button" class="relative inline-flex items-center gap-2 bg-[#C81E2B] hover:bg-[#A81622] text-white px-4 h-10 rounded-lg text-xs font-semibold transition shrink-0 shadow-sm cursor-pointer" aria-label="Giỏ hàng" @click="openDrawer">
          <ShoppingBag class="w-4 h-4" />
          <span>Giỏ hàng</span>
          <span v-if="totalCount > 0" class="bg-white text-[#C81E2B] text-[10px] font-bold rounded-full min-w-[18px] h-[18px] px-1 flex items-center justify-center tabular-nums">
            {{ totalCount }}
          </span>
        </button>
      </div>
    </div>
  </header>
</template>
