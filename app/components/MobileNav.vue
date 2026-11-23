<script setup lang="ts">
import { Home, Car, Phone, ShoppingBag } from 'lucide-vue-next';

const route = useRoute();
const { totalCount, openDrawer } = useCart();

const hideOnDetail = computed(() => route.path === '/chi-tiet');
</script>

<template>
  <nav
    v-if="!hideOnDetail"
    aria-label="Điều hướng di động"
    class="lg:hidden fixed bottom-0 left-0 right-0 z-40 bg-white border-t border-slate-200 shadow-[0_-4px_16px_rgba(13,44,84,0.08)]"
  >
    <div class="grid grid-cols-4 h-16">
      <NuxtLink
        to="/"
        class="flex flex-col items-center justify-center gap-1 no-underline text-[11px] font-medium"
        :class="route.path === '/' ? 'text-[#C81E2B] font-semibold' : 'text-slate-500'"
      >
        <Home class="w-5 h-5" />
        <span>Trang chủ</span>
      </NuxtLink>

      <NuxtLink
        to="/san-pham"
        class="flex flex-col items-center justify-center gap-1 no-underline text-[11px] font-medium"
        :class="route.path.startsWith('/san-pham') ? 'text-[#C81E2B] font-semibold' : 'text-slate-500'"
      >
        <Car class="w-5 h-5" />
        <span>Chọn xe</span>
      </NuxtLink>

      <a
        href="tel:0963294492"
        class="flex flex-col items-center justify-center gap-1 no-underline text-[11px] font-medium text-slate-500"
      >
        <Phone class="w-5 h-5" />
        <span>Gọi ngay</span>
      </a>

      <button
        type="button"
        class="relative flex flex-col items-center justify-center gap-1 text-[11px] font-medium text-slate-500 bg-transparent border-0 cursor-pointer"
        @click="openDrawer"
      >
        <span class="relative">
          <ShoppingBag class="w-5 h-5" />
          <span
            v-if="totalCount > 0"
            class="absolute -top-1.5 -right-2.5 bg-[#C81E2B] text-white text-[10px] font-semibold rounded-full min-w-[17px] h-[17px] px-1 flex items-center justify-center tabular-nums"
          >
            {{ totalCount }}
          </span>
        </span>
        <span>Giỏ hàng</span>
      </button>
    </div>
  </nav>
</template>
