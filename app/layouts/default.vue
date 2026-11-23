<script setup lang="ts">
const { loadFromStorage } = useCart();
const { captureFromRoute } = useAffiliate();
const route = useRoute();

onMounted(() => {
  loadFromStorage();
  captureFromRoute();
});

watch(() => route.fullPath, () => {
  captureFromRoute();
});
</script>

<template>
  <div class="min-h-screen flex flex-col bg-[#F4F6F9] text-[#0F172A]">
    <a href="#main-content" class="skip-to-content">Chuyển đến nội dung chính</a>
    <AppHeader />
    <div class="flex-1">
      <slot />
    </div>
    <AppFooter />
    <CartDrawer />
    <MobileNav />
    <AppToast />
  </div>
</template>
