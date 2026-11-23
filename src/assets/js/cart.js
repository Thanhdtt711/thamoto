export const Cart = {
  getCart() {
    const saved = localStorage.getItem('thamoto_cart');
    return saved ? JSON.parse(saved) : [];
  },
  
  saveCart(cart) {
    localStorage.setItem('thamoto_cart', JSON.stringify(cart));
    // Dispatch custom event to notify all listeners (Header badge, Drawer, etc.)
    window.dispatchEvent(new CustomEvent('cartChanged', { detail: cart }));
  },
  
  addToCart(product) {
    // product should contain: productId, name, price, image, color, material, vehicle (optional), quantity
    const cart = this.getCart();
    
    // Generate a unique ID for this specific configuration
    const vehicleStr = product.vehicle ? `${product.vehicle.brand}-${product.vehicle.model}-${product.vehicle.year}` : 'generic';
    const engravingStr = product.engraving ? product.engraving : '';
    const uniqueId = `${product.productId}-${product.color}-${product.material}-${vehicleStr}-${engravingStr}`.replace(/\s+/g, '-').toLowerCase();
    
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
        engraving: product.engraving || "",
        quantity: product.quantity || 1
      });
    }
    
    this.saveCart(cart);
    
    // Auto-open cart drawer after adding
    setTimeout(() => {
      window.dispatchEvent(new CustomEvent('openCartDrawer'));
    }, 100);
  },
  
  updateQuantity(id, quantity) {
    let cart = this.getCart();
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
    let cart = this.getCart();
    cart = cart.filter(item => item.id !== id);
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
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(value);
  }
};

window.Cart = Cart;
