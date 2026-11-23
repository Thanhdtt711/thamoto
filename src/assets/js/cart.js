export const Cart = {
  getCart() {
    try {
      const saved = localStorage.getItem('thamoto_cart');
      const parsed = saved ? JSON.parse(saved) : [];
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  },

  saveCart(cart) {
    localStorage.setItem('thamoto_cart', JSON.stringify(cart));
    window.dispatchEvent(new CustomEvent('cartChanged', { detail: cart }));
  },

  addToCart(product) {
    const cart = this.getCart();

    const vehicleStr = product.vehicle
      ? `${product.vehicle.brand}-${product.vehicle.model}-${product.vehicle.year || product.formLabel || ''}`
      : 'generic';
    const addonsStr = Array.isArray(product.addons) && product.addons.length > 0
      ? product.addons.map(a => a.id).sort().join('+')
      : 'none';
    const formStr = product.formLabel || '';
    const uniqueId = `${product.productId}-${product.color}-${product.material}-${vehicleStr}-${formStr}-${addonsStr}`
      .replace(/\s+/g, '-')
      .toLowerCase();

    const existingIndex = cart.findIndex(item => item.id === uniqueId);

    if (existingIndex > -1) {
      cart[existingIndex].quantity += (product.quantity || 1);
    } else {
      cart.push({
        id: uniqueId,
        productId: product.productId,
        name: product.name,
        price: product.price,
        image: product.image,
        color: product.color,
        material: product.material,
        vehicle: product.vehicle || null,
        formLabel: product.formLabel || '',
        addons: Array.isArray(product.addons) ? product.addons : [],
        engraving: product.engraving || '',
        quantity: product.quantity || 1
      });
    }

    this.saveCart(cart);

    if (!product.silent) {
      setTimeout(() => {
        window.dispatchEvent(new CustomEvent('openCartDrawer'));
      }, 100);
    }
  },

  updateQuantity(id, quantity) {
    const cart = this.getCart();
    const index = cart.findIndex(item => item.id === id);
    if (index > -1) {
      if (quantity <= 0) {
        cart.splice(index, 1);
      } else {
        cart[index].quantity = quantity;
      }
      this.saveCart(cart);
    }
  },

  removeFromCart(id) {
    const cart = this.getCart().filter(item => item.id !== id);
    this.saveCart(cart);
  },

  getCartTotal() {
    return this.getCart().reduce((sum, item) => sum + (item.price * item.quantity), 0);
  },

  getCartCount() {
    return this.getCart().reduce((sum, item) => sum + item.quantity, 0);
  },

  clearCart() {
    this.saveCart([]);
  },

  formatCurrency(value) {
    return `${new Intl.NumberFormat('vi-VN').format(value || 0)} đ`;
  }
};

window.Cart = Cart;
