<script setup lang="ts">
const { toast } = useToast();
</script>

<template>
  <Teleport to="body">
    <div
      v-if="toast.visible"
      role="status"
      aria-live="polite"
      class="fixed top-4 right-4 left-4 sm:left-auto sm:w-auto sm:max-w-sm z-[60] flex items-center gap-2.5 px-4 py-3 rounded-xl shadow-xl border text-xs font-semibold"
      :class="toast.type === 'error'
        ? 'bg-[#FEF2F2] border-[#C81E2B]/40 text-[#C81E2B]'
        : 'bg-white border-[#15803D]/30 text-[#0D2C54]'"
    >
      <span
        class="w-2.5 h-2.5 rounded-full shrink-0"
        :class="toast.type === 'error' ? 'bg-[#C81E2B]' : 'bg-[#15803D]'"
      />
      <span class="leading-snug">{{ toast.message }}</span>
    </div>
  </Teleport>
</template>
