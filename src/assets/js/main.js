import { Cart } from './cart.js';
import { VehicleSelector } from './selector.js';

document.addEventListener('DOMContentLoaded', () => {
  if (window.lucide) {
    window.lucide.createIcons();
  }

  // 1. Active Desktop & Mobile Nav Link
  const currentPath = window.location.pathname;
  document.querySelectorAll('.nav-link').forEach(link => {
    const href = link.getAttribute('href');
    const isHome = (currentPath === '/' || currentPath.endsWith('/index.html')) && href === '/index.html';
    const isMatch = href && (currentPath === href || currentPath.endsWith(href));
    if (isHome || isMatch) {
      link.classList.add('text-white', 'bg-white/15');
      link.classList.remove('text-slate-200');
      link.setAttribute('aria-current', 'page');
    }
  });

  document.querySelectorAll('.mobile-nav-link').forEach(link => {
    const href = link.getAttribute('href');
    const isHome = (currentPath === '/' || currentPath.endsWith('/index.html')) && href === '/index.html';
    const isMatch = href && !href.startsWith('tel:') && (currentPath === href || currentPath.endsWith(href));
    if (isHome || isMatch) {
      link.classList.add('text-[#C81E2B]', 'font-bold');
      link.classList.remove('text-slate-500');
      link.setAttribute('aria-current', 'page');
    }
  });

  // 2. Mobile Subpage App Bar (Back button + contextual title)
  const isHomePage = currentPath === '/' || currentPath.endsWith('/index.html');
  if (!isHomePage && !document.body.hasAttribute('data-subpage')) {
    document.body.setAttribute('data-subpage', 'true');
  }

  const backBtn = document.getElementById('mobile-appbar-back');
  if (backBtn) {
    backBtn.addEventListener('click', () => {
      if (window.history.length > 1) {
        window.history.back();
      } else {
        window.location.href = '/index.html';
      }
    });
  }

  const appbarTitle = document.getElementById('mobile-appbar-title');
  if (appbarTitle && document.body.dataset.pageTitle) {
    appbarTitle.textContent = document.body.dataset.pageTitle;
  }

  // Hide floating contact on mobile cart/checkout so it never overlaps form controls
  if (currentPath.endsWith('/gio-hang.html') || currentPath.endsWith('/thanh-toan.html')) {
    document.querySelectorAll('.js-floating-contact').forEach(el => {
      el.classList.add('hidden', 'lg:flex');
    });
  }

  // 3. Cart Drawer Logic
  const cartDrawer = document.getElementById('cart-drawer');
  const cartDrawerOverlay = document.getElementById('cart-drawer-overlay');
  const closeCartBtn = document.getElementById('cart-drawer-close');

  const openDrawer = () => {
    if (cartDrawer && cartDrawerOverlay) {
      cartDrawer.classList.remove('translate-x-full');
      cartDrawerOverlay.classList.remove('hidden');
      document.body.classList.add('overflow-hidden');
    }
  };

  const closeDrawer = () => {
    if (cartDrawer && cartDrawerOverlay) {
      cartDrawer.classList.add('translate-x-full');
      cartDrawerOverlay.classList.add('hidden');
      document.body.classList.remove('overflow-hidden');
    }
  };

  window.addEventListener('openCartDrawer', openDrawer);

  document.querySelectorAll('.btn-open-cart').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      openDrawer();
    });
  });

  if (closeCartBtn) closeCartBtn.addEventListener('click', closeDrawer);
  if (cartDrawerOverlay) cartDrawerOverlay.addEventListener('click', closeDrawer);

  const renderCartDrawer = () => {
    const itemsContainer = document.getElementById('cart-drawer-items');
    const totalEl = document.getElementById('cart-drawer-total');
    const badgeCountEls = document.querySelectorAll('.cart-count-badge');
    const emptyStateEl = document.getElementById('cart-drawer-empty');
    const filledStateEl = document.getElementById('cart-drawer-filled');

    const cart = Cart.getCart();
    const total = Cart.getCartTotal();
    const count = Cart.getCartCount();

    badgeCountEls.forEach(el => {
      el.textContent = count;
      el.classList.toggle('hidden', count === 0);
    });

    document.querySelectorAll('.btn-open-cart').forEach(btn => {
      btn.setAttribute('aria-label', count > 0 ? `Giỏ hàng (${count} sản phẩm)` : 'Giỏ hàng');
    });

    if (totalEl) {
      totalEl.textContent = Cart.formatCurrency(total);
    }

    if (cart.length === 0) {
      if (emptyStateEl) emptyStateEl.classList.remove('hidden');
      if (filledStateEl) filledStateEl.classList.add('hidden');
      if (itemsContainer) itemsContainer.innerHTML = '';
      return;
    }

    if (emptyStateEl) emptyStateEl.classList.add('hidden');
    if (filledStateEl) filledStateEl.classList.remove('hidden');

    if (itemsContainer) {
      const formatVehicleLabel = (v) => {
        if (!v) return '';
        const base = v.model.toLowerCase().startsWith(v.brand.toLowerCase()) ? v.model : `${v.brand} ${v.model}`;
        return `${base}${v.year ? ' ' + v.year : ''}`;
      };
      itemsContainer.innerHTML = cart.map(item => {
        const vehicleInfo = item.vehicle
          ? `<p class="text-[11px] font-semibold text-[#0D2C54] mt-0.5">${formatVehicleLabel(item.vehicle)}</p>`
          : '';
        const formInfo = item.formLabel
          ? `<p class="text-[11px] text-slate-600 mt-0.5">${item.formLabel}</p>`
          : '';
        const addonsInfo = Array.isArray(item.addons) && item.addons.length > 0
          ? `<p class="text-[11px] text-[#C81E2B] mt-0.5">+ ${item.addons.map(a => a.label).join(', ')}</p>`
          : '';

        return `
          <div class="bg-white border border-slate-200 rounded-xl p-3 flex items-start gap-3">
            <img src="${item.image}" alt="${item.name}" width="64" height="64" loading="lazy" class="w-16 h-16 object-cover rounded-lg border border-slate-200 shrink-0">
            <div class="flex-1 min-w-0">
              <h4 class="text-xs font-bold text-slate-900 truncate m-0">${item.name}</h4>
              ${vehicleInfo}
              ${formInfo}
              <p class="text-[11px] text-slate-500 mt-0.5">${item.material} · ${item.color}</p>
              ${addonsInfo}
              <div class="flex items-center justify-between mt-2.5">
                <div class="inline-flex items-center border border-slate-300 rounded-lg bg-slate-50">
                  <button type="button" class="w-11 h-11 flex items-center justify-center text-slate-600 hover:text-slate-900 font-bold btn-qty-minus" data-id="${item.id}" aria-label="Giảm số lượng">-</button>
                  <span class="px-2 text-xs font-bold text-slate-900 tabular-nums">${item.quantity}</span>
                  <button type="button" class="w-11 h-11 flex items-center justify-center text-slate-600 hover:text-slate-900 font-bold btn-qty-plus" data-id="${item.id}" aria-label="Tăng số lượng">+</button>
                </div>
                <div class="flex items-center gap-1">
                  <span class="text-xs font-extrabold text-[#C81E2B] tabular-nums">${Cart.formatCurrency(item.price * item.quantity)}</span>
                  <button type="button" class="w-11 h-11 flex items-center justify-center text-slate-400 hover:text-[#C81E2B] transition btn-remove-item" data-id="${item.id}" aria-label="Xóa sản phẩm">
                    <i data-lucide="trash-2" class="w-4 h-4"></i>
                  </button>
                </div>
              </div>
            </div>
          </div>
        `;
      }).join('');

      if (window.lucide) {
        window.lucide.createIcons();
      }

      itemsContainer.querySelectorAll('.btn-qty-minus').forEach(btn => {
        btn.addEventListener('click', () => {
          const id = btn.getAttribute('data-id');
          const item = cart.find(i => i.id === id);
          if (item) Cart.updateQuantity(id, item.quantity - 1);
        });
      });

      itemsContainer.querySelectorAll('.btn-qty-plus').forEach(btn => {
        btn.addEventListener('click', () => {
          const id = btn.getAttribute('data-id');
          const item = cart.find(i => i.id === id);
          if (item) Cart.updateQuantity(id, item.quantity + 1);
        });
      });

      itemsContainer.querySelectorAll('.btn-remove-item').forEach(btn => {
        btn.addEventListener('click', () => {
          const id = btn.getAttribute('data-id');
          Cart.removeFromCart(id);
        });
      });
    }
  };

  renderCartDrawer();
  window.addEventListener('cartChanged', renderCartDrawer);

  // Keep VehicleSelector imported so global window.VehicleSelector is always ready
  void VehicleSelector;
});
