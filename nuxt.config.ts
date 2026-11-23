export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: false },

  modules: ['@nuxtjs/tailwindcss'],

  css: ['~/assets/css/main.css'],

  runtimeConfig: {
    public: {
      supabaseUrl: process.env.NUXT_PUBLIC_SUPABASE_URL || process.env.VITE_SUPABASE_URL || '',
      supabaseAnonKey: process.env.NUXT_PUBLIC_SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY || ''
    }
  },

  app: {
    head: {
      htmlAttrs: { lang: 'vi' },
      title: 'Trung Thành Auto | Thảm Lót Sàn Ô Tô Chuẩn Phom Xe',
      meta: [
        { charset: 'utf-8' },
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        {
          name: 'description',
          content: 'Tìm thảm lót sàn ô tô 6D, 360 độ, nhựa TPE chính xác theo hãng xe, dòng xe và năm sản xuất. Vừa vặn 100%, lắp tại nhà, đổi trả 1-1.'
        }
      ],
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Be+Vietnam+Pro:wght@400;500;600;700&display=swap' },
        { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' },
        { rel: 'alternate icon', type: 'image/png', href: '/favicon.png' }
      ]
    }
  },

  routeRules: {
    '/index.html': { redirect: '/' },
    '/san-pham.html': { redirect: '/san-pham' },
    '/chi-tiet.html': { redirect: '/chi-tiet' },
    '/gio-hang.html': { redirect: '/gio-hang' },
    '/thanh-toan.html': { redirect: '/thanh-toan' },
    '/gioi-thieu.html': { redirect: '/gioi-thieu' },
    '/tin-tuc.html': { redirect: '/tin-tuc' },
    '/lien-he.html': { redirect: '/lien-he' },
    '/cong-tac-vien.html': { redirect: '/cong-tac-vien' },
    '/ctv.html': { redirect: '/ctv' },
    '/admin.html': { redirect: '/admin' }
  }
});
