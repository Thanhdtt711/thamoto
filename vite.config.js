import { defineConfig } from 'vite';
import { readFileSync, existsSync, writeFileSync } from 'fs';
import { resolve } from 'path';

function htmlPartialsPlugin() {
  return {
    name: 'html-partials',
    transformIndexHtml(html, ctx) {
      let content = html;
      const includeRegex = /<include\s+src="([^"]+)"\s*(?:\/>|><\/include>)/g;
      
      let match;
      let limit = 100; // prevent infinite loops
      while ((match = includeRegex.exec(content)) !== null && limit > 0) {
        limit--;
        const tag = match[0];
        const filePath = match[1];
        
        const currentDir = ctx.filename ? resolve(ctx.filename, '..') : resolve(process.cwd(), 'src');
        let fullPath = resolve(currentDir, filePath);
        if (!existsSync(fullPath)) {
          fullPath = resolve(process.cwd(), 'src', filePath);
        }
        
        if (existsSync(fullPath)) {
          const fileContent = readFileSync(fullPath, 'utf-8');
          content = content.replace(tag, fileContent);
          includeRegex.lastIndex = 0;
        } else {
          console.warn(`[html-partials] Warning: Include file not found at ${fullPath}`);
          content = content.replace(tag, `<!-- Include file not found: ${filePath} -->`);
          includeRegex.lastIndex = 0;
        }
      }
      return content;
    },
    handleHotUpdate({ file, server }) {
      if (file.includes('/partials/') || file.endsWith('.html')) {
        server.config.logger.info(`[html-partials] HTML changed: ${file}. Triggering full reload...`);
        server.ws.send({
          type: 'full-reload',
          path: '*'
        });
      }
    }
  };
}

function devRoutingPlugin() {
  return {
    name: 'dev-routing',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = req.url;
        const pathname = url.split('?')[0];
        
        if (pathname.startsWith('/san-pham/') && pathname.endsWith('.html')) {
          req.url = '/chi-tiet.html' + (url.includes('?') ? '?' + url.split('?')[1] : '');
        } else if (pathname.startsWith('/tin-tuc/') && pathname.endsWith('.html')) {
          req.url = '/chi-tiet-tin-tuc.html' + (url.includes('?') ? '?' + url.split('?')[1] : '');
        }
        next();
      });
    }
  };
}

function sitemapPlugin() {
  return {
    name: 'generate-sitemap',
    closeBundle() {
      const urls = [
        'https://thamoto.vercel.app/',
        'https://thamoto.vercel.app/gioi-thieu.html',
        'https://thamoto.vercel.app/san-pham.html',
        'https://thamoto.vercel.app/tin-tuc.html',
        'https://thamoto.vercel.app/lien-he.html',
        // Products
        'https://thamoto.vercel.app/san-pham/tham-da-carbon-cao-cap.html',
        'https://thamoto.vercel.app/san-pham/tham-nhua-tpe-duc-khuon.html',
        'https://thamoto.vercel.app/san-pham/tham-da-5d-qua-tram.html',
        'https://thamoto.vercel.app/san-pham/tham-da-6d-roi-da-tang.html',
        'https://thamoto.vercel.app/san-pham/tham-da-carbon-sport-red.html',
        'https://thamoto.vercel.app/san-pham/tham-nhua-tpe-eco-beige.html',
        'https://thamoto.vercel.app/san-pham/tham-da-5d-royal-cream.html',
        'https://thamoto.vercel.app/san-pham/tham-da-6d-nau-hoang-gia.html',
        'https://thamoto.vercel.app/san-pham/tham-cao-su-tu-nhien-fit.html',
        'https://thamoto.vercel.app/san-pham/tham-cao-su-to-ong-grey.html',
        'https://thamoto.vercel.app/san-pham/tham-da-carbon-luxury-grey.html',
        'https://thamoto.vercel.app/san-pham/tham-da-6d-full-360-do.html',
        // Articles
        'https://thamoto.vercel.app/tin-tuc/huong-dan-chon-tham-lot-san-phu-hop-cho-mua-mua.html',
        'https://thamoto.vercel.app/tin-tuc/tai-sao-tham-lot-san-nhua-tpe-la-xu-huong.html',
        'https://thamoto.vercel.app/tin-tuc/su-khac-biet-vuot-troi-giua-tham-da-carbon-va-tham-da-6d-truyen-thong.html',
        'https://thamoto.vercel.app/tin-tuc/trung-thanh-auto-khai-truong-showroom-quan-7.html',
        'https://thamoto.vercel.app/tin-tuc/huong-dan-tu-ve-sinh-tham-da-5d-tai-nha.html',
        'https://thamoto.vercel.app/tin-tuc/danh-gia-chuyen-gia-chat-luong-tham-tpe.html',
        'https://thamoto.vercel.app/tin-tuc/cach-bao-quan-tham-lot-san-da-luon-ben-dep.html'
      ];
      
      const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map(url => `  <url>
    <loc>${url}</loc>
    <lastmod>${new Date().toISOString().split('T')[0]}</lastmod>
    <changefreq>${url.endsWith('.html') ? (url.includes('/tin-tuc/') ? 'monthly' : 'weekly') : 'daily'}</changefreq>
    <priority>${url.endsWith('/') ? '1.0' : '0.8'}</priority>
  </url>`).join('\n')}
</urlset>
`;
      
      try {
        const publicPath = resolve(process.cwd(), 'src/public/sitemap.xml');
        writeFileSync(publicPath, sitemap, 'utf-8');
        
        const distPath = resolve(process.cwd(), 'dist/sitemap.xml');
        if (existsSync(resolve(process.cwd(), 'dist'))) {
          writeFileSync(distPath, sitemap, 'utf-8');
        }
        console.log('[generate-sitemap] Sitemap.xml updated successfully!');
      } catch (err) {
        console.error('[generate-sitemap] Error writing sitemap:', err);
      }
    }
  };
}

export default defineConfig({
  root: 'src',
  build: {
    outDir: '../dist',
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'src/index.html'),
        gioiThieu: resolve(__dirname, 'src/gioi-thieu.html'),
        sanPham: resolve(__dirname, 'src/san-pham.html'),
        chiTiet: resolve(__dirname, 'src/chi-tiet.html'),
        gioHang: resolve(__dirname, 'src/gio-hang.html'),
        thanhToan: resolve(__dirname, 'src/thanh-toan.html'),
        tinTuc: resolve(__dirname, 'src/tin-tuc.html'),
        chiTietTinTuc: resolve(__dirname, 'src/chi-tiet-tin-tuc.html'),
        lienHe: resolve(__dirname, 'src/lien-he.html')
      }
    }
  },
  plugins: [htmlPartialsPlugin(), devRoutingPlugin(), sitemapPlugin()]
});
