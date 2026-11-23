import { Cart } from './cart.js';
import { VehicleSelector } from './selector.js';

document.addEventListener('DOMContentLoaded', () => {
  // 1. Initialize Lucide Icons
  if (window.lucide) {
    window.lucide.createIcons();
  }

  // 1a. Dynamic Active Navigation Links
  const navLinks = document.querySelectorAll('.nav-link');
  const currentPath = window.location.pathname;
  navLinks.forEach(link => {
    const href = link.getAttribute('href');
    if (href && (currentPath === href || currentPath.endsWith(href) || (currentPath === '/' && href.includes('index.html')))) {
      link.classList.add('text-luxury-gold');
      link.setAttribute('aria-current', 'page');
      const indicator = link.querySelector('span');
      if (indicator) {
        indicator.classList.remove('scale-x-0');
        indicator.classList.add('scale-x-100');
      }
    }
  });

  // 1b. Active Vehicle Sticky Bar Logic
  const updateHeaderVehicleBar = () => {
    const vehicleBar = document.getElementById('header-vehicle-bar');
    const vehicleNameEl = document.getElementById('header-vehicle-name');
    const vehicle = VehicleSelector.getSelectedVehicle();
    if (vehicleBar && vehicleNameEl) {
      if (vehicle) {
        vehicleNameEl.textContent = `${vehicle.brand} ${vehicle.model} ${vehicle.year}`;
        vehicleBar.classList.remove('hidden');
        if (document.body.classList.contains('pt-24')) {
          document.body.style.paddingTop = '168px';
        }
      } else {
        vehicleBar.classList.add('hidden');
        if (document.body.classList.contains('pt-24')) {
          document.body.style.paddingTop = '';
        }
      }
    }
  };
  updateHeaderVehicleBar();
  window.addEventListener('vehicleChanged', updateHeaderVehicleBar);

  const changeVehicleBtn = document.getElementById('btn-change-vehicle');
  if (changeVehicleBtn) {
    changeVehicleBtn.addEventListener('click', (e) => {
      e.preventDefault();
      VehicleSelector.clearSelectedVehicle();
      if (window.location.pathname === '/' || window.location.pathname.endsWith('index.html')) {
        const selectorEl = document.getElementById('hero-vehicle-selector');
        if (selectorEl) {
          selectorEl.scrollIntoView({ behavior: 'smooth' });
        }
      } else {
        window.location.href = '/index.html#hero-vehicle-selector';
      }
    });
  }

  // 2. Header Scroll Effect
  const header = document.getElementById('main-header');
  const navbar = document.getElementById('header-navbar');
  if (header && navbar) {
    const handleScroll = () => {
      if (window.scrollY > 40) {
        navbar.classList.remove('py-5');
        navbar.classList.add('py-2');
        header.classList.add('scrolled-active');
      } else {
        navbar.classList.remove('py-2');
        navbar.classList.add('py-5');
        header.classList.remove('scrolled-active');
      }
    };
    window.addEventListener('scroll', handleScroll, { passive: true });
    handleScroll(); // Run once in case page loads scrolled down
  }

  // 3. Scroll Reveal Animation
  const revealElements = document.querySelectorAll('.scroll-reveal');
  if ('IntersectionObserver' in window && revealElements.length > 0) {
    const revealObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('revealed');
          observer.unobserve(entry.target);
        }
      });
    }, {
      threshold: 0.1,
      rootMargin: '0px 0px -50px 0px'
    });
    revealElements.forEach(el => revealObserver.observe(el));
  } else {
    // Fallback if IntersectionObserver not supported
    revealElements.forEach(el => el.classList.add('revealed'));
  }

  // 4. Cart Drawer Logic
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

  // Listen to open events from other scripts
  window.addEventListener('openCartDrawer', openDrawer);

  // Bind click events to open buttons (e.g. cart buttons in header / mobile nav)
  document.querySelectorAll('.btn-open-cart').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      openDrawer();
    });
  });

  if (closeCartBtn) {
    closeCartBtn.addEventListener('click', closeDrawer);
  }
  if (cartDrawerOverlay) {
    cartDrawerOverlay.addEventListener('click', closeDrawer);
  }

  // Render Cart Drawer Contents
  const renderCartDrawer = () => {
    const itemsContainer = document.getElementById('cart-drawer-items');
    const totalEl = document.getElementById('cart-drawer-total');
    const badgeCountEls = document.querySelectorAll('.cart-count-badge');
    const emptyStateEl = document.getElementById('cart-drawer-empty');
    const filledStateEl = document.getElementById('cart-drawer-filled');
    
    const cart = Cart.getCart();
    const total = Cart.getCartTotal();
    const count = Cart.getCartCount();

    // Update all count badges on page
    badgeCountEls.forEach(el => {
      el.textContent = count;
      if (count === 0) {
        el.classList.add('hidden');
      } else {
        el.classList.remove('hidden');
      }
    });

    // Update cart button aria-label for screen readers
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
      itemsContainer.innerHTML = cart.map(item => {
        const vehicleInfo = item.vehicle ? `<p class="text-xs text-luxury-gold mt-0.5">Xe: ${item.vehicle.brand} ${item.vehicle.model} ${item.vehicle.year}</p>` : '';
        const engravingInfo = item.engraving ? `<p class="text-[10px] text-zinc-400 mt-0.5 italic"><span class="text-luxury-gold">Khắc chữ:</span> "${item.engraving}"</p>` : '';
        return `
          <div class="flex items-start gap-3 py-3 border-b border-[#27272A]/50">
            <img src="${item.image}" alt="${item.name}" width="64" height="64" loading="lazy" class="w-16 h-16 object-cover rounded-md border border-[#27272A]">
            <div class="flex-1 min-w-0">
              <h4 class="text-sm font-semibold text-white truncate">${item.name}</h4>
              <p class="text-xs text-zinc-400 mt-0.5">Chất liệu: ${item.material} | Màu: ${item.color}</p>
              ${vehicleInfo}
              ${engravingInfo}
              <div class="flex items-center justify-between mt-2">
                <div class="flex items-center border border-[#27272A] rounded-md bg-[#09090B]">
                  <button class="px-2 py-0.5 text-zinc-400 hover:text-white btn-qty-minus" data-id="${item.id}">-</button>
                  <span class="px-2 text-xs text-white">${item.quantity}</span>
                  <button class="px-2 py-0.5 text-zinc-400 hover:text-white btn-qty-plus" data-id="${item.id}">+</button>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium text-luxury-gold">${Cart.formatCurrency(item.price * item.quantity)}</span>
                  <button class="text-zinc-500 hover:text-red-500 transition btn-remove-item" data-id="${item.id}">
                    <i data-lucide="trash-2" class="w-4 h-4"></i>
                  </button>
                </div>
              </div>
            </div>
          </div>
        `;
      }).join('');
      
      // Re-create icons for trash can buttons
      if (window.lucide) {
        window.lucide.createIcons();
      }

      // Bind events to quantity and delete buttons
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

  // Render initial drawer state and listen to updates
  renderCartDrawer();
  window.addEventListener('cartChanged', renderCartDrawer);

  // 5. Mobile Navigation Hamburger Menu Toggle
  const menuBtn = document.getElementById('mobile-menu-btn');
  const menuCloseBtn = document.getElementById('mobile-menu-close');
  const mobileMenu = document.getElementById('mobile-menu');
  
  if (mobileMenu) {
    const focusableElements = mobileMenu.querySelectorAll('a, button');
    const firstFocusable = focusableElements[0];
    const lastFocusable = focusableElements[focusableElements.length - 1];

    const trapFocus = (e) => {
      if (e.key !== 'Tab') return;
      if (e.shiftKey) {
        if (document.activeElement === firstFocusable) {
          lastFocusable.focus();
          e.preventDefault();
        }
      } else {
        if (document.activeElement === lastFocusable) {
          firstFocusable.focus();
          e.preventDefault();
        }
      }
    };

    const handleKeyDown = (e) => {
      if (e.key === 'Escape') {
        closeMenu();
      }
    };

    const openMenu = () => {
      mobileMenu.classList.remove('hidden');
      document.body.classList.add('overflow-hidden');
      if (menuBtn) {
        menuBtn.setAttribute('aria-expanded', 'true');
      }
      if (menuCloseBtn) {
        menuCloseBtn.focus();
      }
      document.addEventListener('keydown', handleKeyDown);
      mobileMenu.addEventListener('keydown', trapFocus);
    };

    const closeMenu = () => {
      mobileMenu.classList.add('hidden');
      document.body.classList.remove('overflow-hidden');
      if (menuBtn) {
        menuBtn.setAttribute('aria-expanded', 'false');
        menuBtn.focus();
      }
      document.removeEventListener('keydown', handleKeyDown);
      mobileMenu.removeEventListener('keydown', trapFocus);
    };

    if (menuBtn) {
      menuBtn.addEventListener('click', openMenu);
    }

    if (menuCloseBtn) {
      menuCloseBtn.addEventListener('click', closeMenu);
    }

    // Close menu when clicking any link inside it
    mobileMenu.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', closeMenu);
    });
  }

  // 6. Global vehicle changed listener
  window.addEventListener('vehicleChanged', (e) => {
    // console.log("Vehicle state changed: ", e.detail);
  });

  // 7. Dynamic Mouse Aura Tracking for Luxury Cards
  const handleMouseMove = (e) => {
    const card = e.currentTarget;
    const rect = card.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    card.style.setProperty('--mouse-x', `${x}px`);
    card.style.setProperty('--mouse-y', `${y}px`);
  };

  const initCardGlow = () => {
    document.querySelectorAll('.luxury-card-glow').forEach(card => {
      card.removeEventListener('mousemove', handleMouseMove);
      card.addEventListener('mousemove', handleMouseMove);
    });
  };

  // Run on load
  initCardGlow();

  // Watch for dynamic DOM updates (like product list changes or pagination)
  const observer = new MutationObserver(() => {
    initCardGlow();
  });
  observer.observe(document.body, { childList: true, subtree: true });
});
