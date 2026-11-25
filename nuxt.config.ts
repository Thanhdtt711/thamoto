export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: false },

  modules: ['@nuxtjs/tailwindcss'],

  css: ['~/assets/css/main.css'],

  runtimeConfig: {
    public: {
      siteUrl: process.env.NUXT_PUBLIC_SITE_URL || 'https://thamoto.vercel.app',
      supabaseUrl: process.env.NUXT_PUBLIC_SUPABASE_URL || process.env.VITE_SUPABASE_URL || '',
      supabaseAnonKey: process.env.NUXT_PUBLIC_SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY || '',
      gaId: process.env.NUXT_PUBLIC_GA_ID || '',
      metaPixelId: process.env.NUXT_PUBLIC_META_PIXEL_ID || ''
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
        },
        { property: 'og:type', content: 'website' },
        { property: 'og:locale', content: 'vi_VN' },
        { property: 'og:site_name', content: 'Trung Thành Auto' },
        { property: 'og:title', content: 'Trung Thành Auto | Thảm Lót Sàn Ô Tô Chuẩn Phom Xe' },
        {
          property: 'og:description',
          content: 'Thảm lót sàn ô tô 6D, 360 độ, nhựa TPE nguyên sinh chuẩn phom theo từng đời xe. Bảo hành 24 tháng, đổi trả 1-1.'
        },
        { property: 'og:image', content: 'https://thamoto.vercel.app/assets/images/hero-mat.webp' },
        { name: 'twitter:card', content: 'summary_large_image' }
      ],
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        {
          rel: 'preload',
          as: 'style',
          href: 'https://fonts.googleapis.com/css2?family=Be+Vietnam+Pro:wght@400;500;600;700&display=swap'
        },
        {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Be+Vietnam+Pro:wght@400;500;600;700&display=swap'
        },
        { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' },
        { rel: 'alternate icon', type: 'image/png', href: '/favicon.png' }
      ]
    }
  },

  routeRules: {
    '/**': {
      headers: {
        'X-Frame-Options': 'SAMEORIGIN',
        'X-Content-Type-Options': 'nosniff',
        'Referrer-Policy': 'strict-origin-when-cross-origin',
        'Permissions-Policy': 'camera=(), microphone=(), geolocation=()'
      }
    },
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
