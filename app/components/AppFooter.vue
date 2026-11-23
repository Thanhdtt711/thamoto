<script setup lang="ts">
import { Phone, Mail, MapPin, Clock, MessageCircle } from 'lucide-vue-next';

const route = useRoute();
const hideMobileFloating = computed(() => ['/gio-hang', '/thanh-toan'].includes(route.path));
</script>

<template>
  <footer class="bg-[#0D2C54] text-slate-200 mt-12">
    <div class="container-app pt-9 pb-24 lg:pb-8">
      <div class="grid grid-cols-1 md:grid-cols-12 gap-8 items-start">
        <div class="md:col-span-5 space-y-4">
          <NuxtLink to="/" class="inline-flex items-center gap-2.5 no-underline">
            <svg class="w-9 h-9 shrink-0" viewBox="0 0 36 36" fill="none" aria-hidden="true">
              <rect width="36" height="36" rx="8" fill="#C81E2B" />
              <path d="M8 12.5C8 11.1193 9.11929 10 10.5 10H25.5C26.8807 10 28 11.1193 28 12.5V22L23.5 26.5H12.5L8 22V12.5Z" stroke="white" stroke-width="2" stroke-linejoin="round" />
              <path d="M13 15.5H23M18 15.5V22" stroke="white" stroke-width="2.2" stroke-linecap="round" />
            </svg>
            <div class="leading-none">
              <span class="block text-sm font-bold tracking-tight text-white">TRUNG THÀNH AUTO</span>
              <span class="block text-[10px] font-semibold tracking-[0.14em] text-slate-300 mt-0.5 uppercase">Thảm Lót Sàn Ô Tô</span>
            </div>
          </NuxtLink>

          <p class="text-xs text-slate-300 leading-relaxed m-0 max-w-sm">
            Chuyên may đo và lắp đặt thảm lót sàn ô tô 6D, 360 độ và nhựa TPE nguyên sinh chuẩn phom từng đời xe. Vừa vặn 100% — Lắp tại nhà — Đổi trả 1-1.
          </p>

          <div class="flex flex-wrap gap-2.5 pt-1">
            <a href="tel:0963294492" class="inline-flex items-center gap-1.5 min-h-[40px] px-4 rounded-lg bg-[#C81E2B] hover:bg-[#A81622] text-white text-xs font-semibold no-underline transition tabular-nums">
              <Phone class="w-3.5 h-3.5" />
              <span>0963 294 492</span>
            </a>
            <a href="https://zalo.me/0963294492" target="_blank" rel="noopener" class="inline-flex items-center gap-1.5 min-h-[40px] px-4 rounded-lg bg-white/10 hover:bg-white/20 border border-white/20 text-white text-xs font-semibold no-underline transition">
              <MessageCircle class="w-3.5 h-3.5" />
              <span>Chat Zalo</span>
            </a>
          </div>
        </div>

        <div class="md:col-span-3 grid grid-cols-2 gap-4 text-xs">
          <div>
            <h3 class="text-xs font-bold uppercase tracking-wider text-white mb-3 mt-0">Điều hướng</h3>
            <ul class="space-y-2 list-none p-0 m-0">
              <li><NuxtLink to="/" class="text-slate-300 hover:text-white no-underline transition">Trang chủ</NuxtLink></li>
              <li><NuxtLink to="/san-pham" class="text-slate-300 hover:text-white no-underline transition">Tất cả dòng xe</NuxtLink></li>
              <li><NuxtLink to="/tin-tuc" class="text-slate-300 hover:text-white no-underline transition">Tin tức</NuxtLink></li>
              <li><NuxtLink to="/gioi-thieu" class="text-slate-300 hover:text-white no-underline transition">Giới thiệu</NuxtLink></li>
              <li><NuxtLink to="/lien-he" class="text-slate-300 hover:text-white no-underline transition">Liên hệ</NuxtLink></li>
              <li><NuxtLink to="/cong-tac-vien" class="text-slate-300 hover:text-white no-underline transition">Đăng ký CTV</NuxtLink></li>
              <li><NuxtLink to="/ctv" class="text-slate-300 hover:text-white no-underline transition">Cổng CTV</NuxtLink></li>
            </ul>
          </div>
          <div>
            <h3 class="text-xs font-bold uppercase tracking-wider text-white mb-3 mt-0">Chính sách</h3>
            <ul class="space-y-2 list-none p-0 m-0">
              <li><NuxtLink to="/gioi-thieu#bao-hanh" class="text-slate-300 hover:text-white no-underline transition">Bảo hành 24 tháng</NuxtLink></li>
              <li><NuxtLink to="/gioi-thieu#doi-tra" class="text-slate-300 hover:text-white no-underline transition">Đổi trả 1-1</NuxtLink></li>
              <li><NuxtLink to="/gioi-thieu#van-chuyen" class="text-slate-300 hover:text-white no-underline transition">Giao &amp; Lắp đặt</NuxtLink></li>
              <li><NuxtLink to="/gioi-thieu#bao-mat" class="text-slate-300 hover:text-white no-underline transition">Bảo mật thông tin</NuxtLink></li>
            </ul>
          </div>
        </div>

        <div class="md:col-span-4 bg-white/5 border border-white/10 rounded-xl p-4 space-y-2.5 text-xs">
          <h3 class="text-xs font-bold uppercase tracking-wider text-white m-0 pb-2 border-b border-white/10">Thông tin liên hệ</h3>
          <p class="flex items-center gap-2.5 m-0">
            <Phone class="w-4 h-4 text-[#F59E0B] shrink-0" />
            <a href="tel:0963294492" class="font-semibold text-white hover:underline no-underline tabular-nums">0963 294 492</a>
          </p>
          <p class="flex items-center gap-2.5 text-slate-300 m-0">
            <Mail class="w-4 h-4 text-[#F59E0B] shrink-0" />
            <a href="mailto:dothanh0711@gmail.com" class="text-slate-200 hover:text-white no-underline hover:underline">dothanh0711@gmail.com</a>
          </p>
          <p class="flex items-start gap-2.5 text-slate-300 m-0">
            <MapPin class="w-4 h-4 text-[#F59E0B] shrink-0 mt-0.5" />
            <span>Yên Lãng, Hà Nội</span>
          </p>
          <p class="flex items-center gap-2.5 text-slate-300 m-0">
            <Clock class="w-4 h-4 text-[#F59E0B] shrink-0" />
            <span class="tabular-nums">08:00 – 21:00 (Hằng ngày)</span>
          </p>
        </div>
      </div>

      <div class="border-t border-white/15 mt-8 pt-4 flex flex-col sm:flex-row items-center justify-between gap-2 text-[11px] text-slate-300">
        <span>&copy; 2026 Trung Thành Auto. Bảo hành chính hãng 24 tháng.</span>
        <span>Vừa vặn 100% · Lắp tại nhà · Đổi trả 1-1</span>
      </div>
    </div>
  </footer>

  <!-- Floating Quick Contact -->
  <div
    class="fixed right-4 bottom-24 lg:bottom-6 z-40 flex flex-col gap-2.5"
    :class="{ 'hidden lg:flex': hideMobileFloating }"
    aria-label="Liên hệ nhanh"
  >
    <a
      href="https://zalo.me/0963294492"
      target="_blank"
      rel="noopener"
      class="w-12 h-12 rounded-full bg-[#0D2C54] hover:bg-[#133A6E] text-white border-2 border-white shadow-lg flex flex-col items-center justify-center no-underline transition hover:scale-105"
      aria-label="Chat Zalo tư vấn nhanh"
    >
      <span class="text-[11px] font-bold leading-none">Zalo</span>
    </a>
    <a
      href="tel:0963294492"
      class="hidden lg:flex w-12 h-12 rounded-full bg-[#C81E2B] hover:bg-[#A81622] text-white border-2 border-white shadow-lg items-center justify-center no-underline transition hover:scale-105"
      aria-label="Gọi hotline 0963 294 492"
    >
      <Phone class="w-5 h-5" />
    </a>
  </div>
</template>
