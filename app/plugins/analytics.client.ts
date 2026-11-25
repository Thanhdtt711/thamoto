// P2-2: Tích hợp GA4 & Meta Pixel không phụ thuộc thư viện ngoài.
// Chỉ kích hoạt khi cấu hình NUXT_PUBLIC_GA_ID hoặc NUXT_PUBLIC_META_PIXEL_ID trong biến môi trường.
export default defineNuxtPlugin(() => {
  const config = useRuntimeConfig();
  const gaId = String(config.public.gaId || '').trim();
  const pixelId = String(config.public.metaPixelId || '').trim();

  if (gaId) {
    const s = document.createElement('script');
    s.async = true;
    s.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(gaId)}`;
    document.head.appendChild(s);

    const w = window as any;
    w.dataLayer = w.dataLayer || [];
    w.gtag = function gtag(...args: any[]) {
      w.dataLayer.push(args);
    };
    w.gtag('js', new Date());
    w.gtag('config', gaId);
  }

  if (pixelId) {
    const w = window as any;
    if (!w.fbq) {
      const n: any = function (...args: any[]) {
        n.callMethod ? n.callMethod(...args) : n.queue.push(args);
      };
      n.queue = [];
      n.loaded = true;
      n.version = '2.0';
      w.fbq = n;
      const s = document.createElement('script');
      s.async = true;
      s.src = 'https://connect.facebook.net/en_US/fbevents.js';
      document.head.appendChild(s);
    }
    w.fbq('init', pixelId);
    w.fbq('track', 'PageView');
  }
});
