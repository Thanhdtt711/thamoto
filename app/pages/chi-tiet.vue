<script setup lang="ts">
import { Check, ShoppingBag } from 'lucide-vue-next';

const route = useRoute();
const router = useRouter();
const { addItem, openDrawer } = useCart();
const { showToast } = useToast();
const { supabase, isConfigured } = useSupabase();

interface MatOption { basePrice: number; image: string }
interface AddonOption { id: string; label: string; shortLabel: string; price: number; defaultChecked: boolean }

const ADDON_PREFIX: Record<string, string> = { 'tham-roi': 'Tặng ', 'lot-cop': 'Mua thêm ' };
const FALLBACK_MAT_IMAGE = '/assets/images/mat-6d-red.webp';

const lowerFirst = (s: string) => (s ? s.charAt(0).toLowerCase() + s.slice(1) : s);
const addonIdFromSku = (sku: string) => String(sku || '').replace(/^ADDON-/i, '').toLowerCase();
const buildAddonLabel = (id: string, name: string, price: number) =>
  `${ADDON_PREFIX[id] || ''}${ADDON_PREFIX[id] ? lowerFirst(name) : name} (+${Math.round(price / 1000)}k)`;

// Giá hiển thị lấy từ DB (RPC get_catalog_prices) — cùng nguồn với create_order.
// MAT_PRICING chỉ là dữ liệu dự phòng khi chưa cấu hình / RPC lỗi.
const materials = ref<Record<string, MatOption>>({ ...MAT_PRICING.materials });
const addons = ref<AddonOption[]>(
  MAT_PRICING.addons.map((a) => ({ ...a, label: buildAddonLabel(a.id, a.shortLabel, a.price) }))
);
const pricesLoading = ref(isConfigured);

const loadCatalogPrices = async () => {
  if (!supabase) {
    pricesLoading.value = false;
    return;
  }
  const { data, error } = await supabase.rpc('get_catalog_prices');
  if (!error && Array.isArray(data)) {
    const dbMats: Record<string, MatOption> = {};
    const dbAddons: AddonOption[] = [];
    for (const p of data as any[]) {
      const price = Number(p.base_price) || 0;
      if (p.product_type === 'mat') {
        dbMats[p.name] = {
          basePrice: price,
          image: p.image_url || MAT_PRICING.materials[p.name]?.image || FALLBACK_MAT_IMAGE
        };
      } else if (p.product_type === 'addon') {
        const id = addonIdFromSku(p.sku);
        dbAddons.push({
          id,
          label: buildAddonLabel(id, p.name, price),
          shortLabel: p.name,
          price,
          defaultChecked: MAT_PRICING.addons.find((a) => a.id === id)?.defaultChecked ?? false
        });
      }
    }
    if (Object.keys(dbMats).length > 0) materials.value = dbMats;
    if (dbAddons.length > 0) addons.value = dbAddons;

    if (!materials.value[selectedMaterial.value]) {
      selectedMaterial.value = Object.keys(materials.value)[0]!;
    }
    selectedAddons.value = selectedAddons.value.filter((id) => addons.value.some((a) => a.id === id));
  }
  pricesLoading.value = false;
};

onMounted(loadCatalogPrices);

const vehicle = computed(() => {
  const found = findVehicleByParams(
    route.query.hang ? String(route.query.hang) : undefined,
    route.query.xe ? String(route.query.xe) : undefined
  );
  return found || {
    brand: 'Toyota',
    brandSlug: 'toyota',
    model: 'Fortuner',
    modelSlug: 'fortuner',
    years: ['2025', '2024', '2023', '2022', '2021', '2020'],
    image: '/assets/images/cars/fortuner.webp'
  };
});

const forms = computed(() => getFormsForVehicle(vehicle.value.brand, vehicle.value.model));
const selectedFormId = ref('form-moi');
const selectedMaterial = ref(
  route.query.material && materials.value[String(route.query.material)]
    ? String(route.query.material)
    : 'Thảm 6D Cao Cấp'
);
const selectedColor = ref(MAT_PRICING.colors[0]!.name);
const selectedAddons = ref<string[]>(addons.value.filter((a) => a.defaultChecked).map((a) => a.id));

const galleryImages = computed(() => [
  { src: '/assets/images/floor-after.webp', label: 'Lắp thực tế trên xe' },
  { src: materials.value[selectedMaterial.value]?.image || FALLBACK_MAT_IMAGE, label: selectedMaterial.value },
  { src: vehicle.value.image, label: `${vehicle.value.brand} ${vehicle.value.model}` },
  { src: '/assets/images/mat-carbon-gold.webp', label: 'Cận cảnh chất liệu' }
]);

const activeImage = ref('/assets/images/floor-after.webp');

watch(selectedMaterial, (mat) => {
  const img = materials.value[mat]?.image;
  if (img) activeImage.value = img;
});

const selectedForm = computed(() => forms.value.find((f) => f.id === selectedFormId.value) || forms.value[0]!);

const totalPrice = computed(() => {
  const base = materials.value[selectedMaterial.value]?.basePrice ?? 0;
  const addonTotal = addons.value
    .filter((a) => selectedAddons.value.includes(a.id))
    .reduce((sum, a) => sum + a.price, 0);
  return base + addonTotal;
});

const toggleAddon = (id: string) => {
  if (selectedAddons.value.includes(id)) {
    selectedAddons.value = selectedAddons.value.filter((x) => x !== id);
  } else {
    selectedAddons.value.push(id);
  }
};

useSeoMeta({
  title: () => `Thảm Lót Sàn ${vehicle.value.brand} ${vehicle.value.model} | Trung Thành Auto`,
  description: () => `Chọn đời xe, chất liệu 6D / 360 / TPE và màu sắc thảm lót sàn chuẩn phom cho ${vehicle.value.brand} ${vehicle.value.model}.`
});

const handleAddToCart = (goCheckout = false) => {
  if (pricesLoading.value) return;
  const addonLabels = addons.value
    .filter((a) => selectedAddons.value.includes(a.id))
    .map((a) => a.shortLabel);

  addItem({
    id: '',
    name: `Thảm Lót Sàn ${vehicle.value.brand} ${vehicle.value.model}`,
    price: totalPrice.value,
    image: activeImage.value,
    material: selectedMaterial.value,
    color: selectedColor.value,
    formLabel: selectedForm.value.label,
    addons: addonLabels,
    vehicle: {
      brand: vehicle.value.brand,
      model: vehicle.value.model,
      year: route.query.nam ? String(route.query.nam) : String(selectedForm.value.maxYear)
    }
  });

  if (goCheckout) {
    router.push('/thanh-toan');
  } else {
    showToast('Đã thêm bộ thảm vào giỏ hàng!');
    openDrawer();
  }
};
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 pb-28 lg:pb-10 space-y-5">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <NuxtLink :to="`/san-pham?hang=${vehicle.brandSlug}`">{{ vehicle.brand }}</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54]">{{ vehicle.model }}</span>
    </nav>

    <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
      <!-- Left Sticky Gallery -->
      <div class="lg:col-span-6 lg:sticky lg:top-24 space-y-3">
        <div class="card-surface overflow-hidden aspect-[4/3] bg-slate-100">
          <img :src="activeImage" :alt="`Thảm lót sàn ${vehicle.brand} ${vehicle.model}`" width="720" height="540"
            class="w-full h-full object-cover">
        </div>
        <div class="grid grid-cols-4 gap-2.5">
          <button v-for="img in galleryImages" :key="img.src + img.label" type="button"
            class="aspect-[4/3] rounded-lg overflow-hidden border-2 bg-white cursor-pointer p-0 transition"
            :class="activeImage === img.src ? 'border-[#0D2C54]' : 'border-slate-200 hover:border-slate-400'"
            @click="activeImage = img.src">
            <img :src="img.src" :alt="img.label" width="160" height="120" class="w-full h-full object-cover">
          </button>
        </div>
      </div>

      <!-- Right Configurator -->
      <div class="lg:col-span-6 card-surface p-5 sm:p-6 space-y-6">
        <div class="border-b border-slate-200 pb-4">
          <span class="text-[11px] font-semibold uppercase tracking-wider text-[#C81E2B]">
            CHUẨN PHOM 100% · {{ vehicle.brand.toUpperCase() }}
          </span>
          <h1 class="text-xl sm:text-2xl font-bold text-[#0D2C54] mt-1 mb-0">
            Thảm Lót Sàn {{ vehicle.brand }} {{ vehicle.model }}
          </h1>
        </div>

        <!-- Bước 1: Đời xe -->
        <div class="space-y-2.5">
          <h2 class="text-xs font-bold uppercase tracking-wide text-[#0D2C54] m-0">BƯỚC 1: CHỌN ĐỜI XE</h2>
          <div class="grid grid-cols-2 gap-3">
            <button v-for="f in forms" :key="f.id" type="button"
              class="p-3 rounded-xl border-2 text-left cursor-pointer transition bg-white relative"
              :class="selectedFormId === f.id ? 'border-[#0D2C54] bg-[#EFF4FA]' : 'border-slate-200 hover:border-slate-400'"
              @click="selectedFormId = f.id">
              <span class="text-xs font-bold text-[#0D2C54] block leading-snug tabular-nums">{{ f.label }}</span>
              <span v-if="selectedFormId === f.id"
                class="absolute top-2 right-2 w-5 h-5 rounded-full bg-[#0D2C54] text-white flex items-center justify-center">
                <Check class="w-3 h-3" />
              </span>
            </button>
          </div>
        </div>

        <!-- Bước 2: Chất liệu & Màu sắc -->
        <div class="space-y-4">
          <div class="space-y-2.5">
            <h2 class="text-xs font-bold uppercase tracking-wide text-[#0D2C54] m-0">BƯỚC 2: CHỌN CHẤT LIỆU</h2>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              <button v-for="(info, matName) in materials" :key="matName" type="button"
                class="p-3 rounded-xl border-2 text-left cursor-pointer transition flex items-center justify-between gap-2 bg-white"
                :class="selectedMaterial === matName ? 'border-[#0D2C54] bg-[#EFF4FA]' : 'border-slate-200 hover:border-slate-400'"
                @click="selectedMaterial = String(matName)">
                <span class="text-xs font-semibold text-slate-900">{{ matName }}</span>
                <span class="text-xs font-bold text-[#15803D] tabular-nums shrink-0">{{ formatCurrency(info.basePrice)
                  }}</span>
              </button>
            </div>
          </div>

          <div class="space-y-2.5">
            <h3 class="text-xs font-bold uppercase tracking-wide text-[#0D2C54] m-0">CHỌN MÀU SẮC</h3>
            <div class="flex flex-wrap gap-2.5">
              <button v-for="c in MAT_PRICING.colors" :key="c.name" type="button" class="color-swatch-btn"
                :class="{ 'is-active': selectedColor === c.name }" @click="selectedColor = c.name">
                <span class="color-swatch-dot" :style="{ backgroundColor: c.hex, borderColor: c.ring }" />
                <span>{{ c.name }}</span>
              </button>
            </div>
          </div>
        </div>

        <!-- Ưu đãi kèm theo -->
        <div class="space-y-2.5">
          <h2 class="text-xs font-bold uppercase tracking-wide text-[#0D2C54] m-0">ƯU ĐÃI KÈM THEO</h2>
          <div class="space-y-2">
            <label v-for="addon in addons" :key="addon.id"
              class="flex items-center justify-between gap-3 p-3.5 rounded-xl border cursor-pointer transition"
              :class="selectedAddons.includes(addon.id) ? 'border-[#0D2C54] bg-[#EFF4FA]' : 'border-slate-200 bg-white'">
              <span class="flex items-center gap-2.5 text-xs font-semibold text-slate-800">
                <input type="checkbox" :checked="selectedAddons.includes(addon.id)" class="w-4 h-4 accent-[#0D2C54]"
                  @change="toggleAddon(addon.id)">
                <span>{{ addon.label }}</span>
              </span>
              <span class="text-xs font-bold text-[#15803D] tabular-nums shrink-0">+{{ formatCurrency(addon.price)
                }}</span>
            </label>
          </div>
        </div>

        <!-- Desktop Total & CTA -->
        <div class="hidden lg:block pt-4 border-t border-slate-200 space-y-4">
          <div class="flex items-baseline justify-between">
            <span class="text-sm font-semibold uppercase text-slate-600">TỔNG TIỀN:</span>
            <span class="text-2xl font-bold text-[#15803D] tabular-nums">{{ formatCurrency(totalPrice) }}</span>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <button type="button" class="btn-outline text-xs" :disabled="pricesLoading" @click="handleAddToCart(false)">
              <ShoppingBag class="w-4 h-4" /> THÊM VÀO GIỎ
            </button>
            <button type="button" class="btn-cta text-xs" :disabled="pricesLoading" @click="handleAddToCart(true)">
              ĐẶT MUA NGAY
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Mobile Sticky Bottom Bar -->
    <div
      class="lg:hidden fixed bottom-0 left-0 right-0 z-40 bg-white border-t border-slate-200 px-4 py-3 shadow-[0_-4px_16px_rgba(13,44,84,0.1)]">
      <div class="flex items-center justify-between gap-3">
        <div>
          <span class="text-[10px] font-semibold uppercase text-slate-500 block">Tổng tiền</span>
          <span class="text-lg font-bold text-[#15803D] tabular-nums leading-tight">{{ formatCurrency(totalPrice)
            }}</span>
        </div>
        <div class="flex items-center gap-2">
          <button type="button" class="btn-outline text-xs px-3.5 min-h-[44px]" aria-label="Thêm vào giỏ"
            :disabled="pricesLoading" @click="handleAddToCart(false)">
            <ShoppingBag class="w-4 h-4" />
          </button>
          <button type="button" class="btn-cta text-xs px-5 min-h-[44px]" :disabled="pricesLoading"
            @click="handleAddToCart(true)">
            ĐẶT MUA NGAY
          </button>
        </div>
      </div>
    </div>
  </main>
</template>
