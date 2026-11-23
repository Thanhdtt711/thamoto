export interface CartItem {
  id: string;
  name: string;
  price: number;
  image: string;
  material: string;
  color: string;
  formLabel?: string;
  addons?: string[];
  vehicle?: {
    brand: string;
    model: string;
    year: string;
  };
  quantity: number;
}

const CART_KEY = 'thamoto_cart';

export function useCart() {
  const items = useState<CartItem[]>('cart-items', () => []);
  const isDrawerOpen = useState<boolean>('cart-drawer-open', () => false);
  const initialized = useState<boolean>('cart-initialized', () => false);

  const loadFromStorage = () => {
    if (!import.meta.client || initialized.value) return;
    initialized.value = true;
    try {
      const raw = localStorage.getItem(CART_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) items.value = parsed;
      }
    } catch {
      items.value = [];
    }
  };

  const persist = () => {
    if (!import.meta.client) return;
    try {
      localStorage.setItem(CART_KEY, JSON.stringify(items.value));
    } catch {
      // Ignore storage errors
    }
  };

  const addItem = (item: Omit<CartItem, 'quantity'> & { quantity?: number }) => {
    loadFromStorage();
    const qty = item.quantity || 1;
    const key = [
      item.name,
      item.material,
      item.color,
      item.formLabel || '',
      (item.addons || []).join(','),
      item.vehicle?.brand || '',
      item.vehicle?.model || '',
      item.vehicle?.year || ''
    ].join('|');

    const existing = items.value.find((i) => i.id === key);
    if (existing) {
      existing.quantity += qty;
    } else {
      items.value.push({
        ...item,
        id: key,
        quantity: qty
      });
    }
    persist();
  };

  const updateQuantity = (index: number, delta: number) => {
    const target = items.value[index];
    if (!target) return;
    target.quantity += delta;
    if (target.quantity <= 0) {
      items.value.splice(index, 1);
    }
    persist();
  };

  const removeItem = (index: number) => {
    items.value.splice(index, 1);
    persist();
  };

  const clearCart = () => {
    items.value = [];
    persist();
  };

  const totalCount = computed(() => items.value.reduce((s, i) => s + i.quantity, 0));
  const subtotal = computed(() => items.value.reduce((s, i) => s + i.price * i.quantity, 0));

  return {
    items,
    isDrawerOpen,
    totalCount,
    subtotal,
    loadFromStorage,
    addItem,
    updateQuantity,
    removeItem,
    clearCart,
    openDrawer: () => { isDrawerOpen.value = true; },
    closeDrawer: () => { isDrawerOpen.value = false; }
  };
}
