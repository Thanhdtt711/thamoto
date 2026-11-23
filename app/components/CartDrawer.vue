<script setup lang="ts">
import { X, ShoppingBag, Trash2, Plus, Minus } from 'lucide-vue-next';

const { items, isDrawerOpen, subtotal, closeDrawer, updateQuantity, removeItem } = useCart();
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isDrawerOpen"
      class="fixed inset-0 bg-slate-900/50 backdrop-blur-[2px] z-50"
      @click="closeDrawer"
    />

    <aside
      aria-label="Giỏ hàng"
      class="fixed top-0 right-0 h-full w-full max-w-md bg-white z-50 shadow-2xl transform transition-transform duration-300 flex flex-col"
      :class="isDrawerOpen ? 'translate-x-0' : 'translate-x-full'"
    >
      <div class="p-4 border-b border-slate-200 flex items-center justify-between bg-[#0D2C54] text-white">
        <div class="flex items-center gap-2">
          <ShoppingBag class="w-5 h-5" />
          <h2 class="text-sm font-bold uppercase m-0">Giỏ hàng của bạn</h2>
        </div>
        <button type="button" class="icon-touch-btn text-white hover:bg-white/10 rounded-lg" aria-label="Đóng giỏ hàng" @click="closeDrawer">
          <X class="w-5 h-5" />
        </button>
      </div>

      <div v-if="items.length === 0" class="flex-1 flex flex-col items-center justify-center p-8 text-center space-y-4">
        <div class="w-16 h-16 rounded-full bg-slate-100 text-slate-400 flex items-center justify-center">
          <ShoppingBag class="w-8 h-8" />
        </div>
        <p class="text-sm font-semibold text-slate-700 m-0">Giỏ hàng đang trống</p>
        <p class="text-xs text-slate-500 m-0">Chọn hãng xe và đời xe để xem bộ thảm chuẩn phom 100%.</p>
        <NuxtLink to="/san-pham" class="btn-cta text-xs px-6" @click="closeDrawer">CHỌN DÒNG XE NGAY</NuxtLink>
      </div>

      <template v-else>
        <div class="flex-1 overflow-y-auto p-4 space-y-3">
          <div
            v-for="(item, idx) in items"
            :key="item.id"
            class="flex gap-3 p-3 rounded-xl border border-slate-200 bg-[#F8FAFC]"
          >
            <img :src="item.image" :alt="item.name" width="64" height="64" class="w-16 h-16 rounded-lg object-cover bg-white border border-slate-200 shrink-0">
            <div class="flex-1 min-w-0 space-y-1">
              <div class="flex items-start justify-between gap-2">
                <p class="text-xs font-semibold text-slate-900 m-0 line-clamp-1">{{ item.name }}</p>
                <button type="button" class="text-slate-400 hover:text-[#C81E2B] p-1" aria-label="Xóa" @click="removeItem(idx)">
                  <Trash2 class="w-3.5 h-3.5" />
                </button>
              </div>
              <p class="text-[11px] text-slate-500 m-0">
                {{ item.material }} · {{ item.color }}
              </p>
              <p v-if="item.formLabel" class="text-[11px] text-slate-500 m-0">{{ item.formLabel }}</p>
              <div class="flex items-center justify-between pt-1">
                <div class="inline-flex items-center border border-slate-300 rounded-lg bg-white">
                  <button type="button" class="w-7 h-7 flex items-center justify-center text-slate-600 hover:text-[#0D2C54]" aria-label="Giảm" @click="updateQuantity(idx, -1)">
                    <Minus class="w-3 h-3" />
                  </button>
                  <span class="w-7 text-center text-xs font-semibold tabular-nums">{{ item.quantity }}</span>
                  <button type="button" class="w-7 h-7 flex items-center justify-center text-slate-600 hover:text-[#0D2C54]" aria-label="Tăng" @click="updateQuantity(idx, 1)">
                    <Plus class="w-3 h-3" />
                  </button>
                </div>
                <span class="text-xs font-bold text-[#15803D] tabular-nums">{{ formatCurrency(item.price * item.quantity) }}</span>
              </div>
            </div>
          </div>
        </div>

        <div class="p-4 border-t border-slate-200 bg-white space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-xs font-semibold text-slate-600 uppercase">Tạm tính</span>
            <span class="font-bold text-lg text-[#15803D] tabular-nums">{{ formatCurrency(subtotal) }}</span>
          </div>
          <div class="grid grid-cols-2 gap-2.5">
            <NuxtLink to="/gio-hang" class="btn-outline text-xs" @click="closeDrawer">XEM GIỎ HÀNG</NuxtLink>
            <NuxtLink to="/thanh-toan" class="btn-cta text-xs" @click="closeDrawer">THANH TOÁN</NuxtLink>
          </div>
        </div>
      </template>
    </aside>
  </Teleport>
</template>
