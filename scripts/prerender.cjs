const fs = require('fs');
const path = require('path');

// Vietnamese Accent Remover & Slug Generator
function toSlug(str) {
  return str
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[đĐ]/g, 'd')
    .replace(/[^a-z0-9\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

// HTML optimization: Inject meta tags, preconnects, manifest, and image lazy loading
function optimizeHtml(html) {
  const optMeta = `
  <meta name="theme-color" content="#0D2C54" />
  <link rel="manifest" href="/manifest.json" />
  <link rel="preconnect" href="https://cdn.tailwindcss.com" />
  <link rel="dns-prefetch" href="https://cdn.tailwindcss.com" />
  <link rel="preconnect" href="https://unpkg.com" />
  <link rel="dns-prefetch" href="https://unpkg.com" />`;
  
  if (html.includes('<meta charset="UTF-8">')) {
    html = html.replace('<meta charset="UTF-8">', '<meta charset="UTF-8">' + optMeta);
  } else if (html.includes('<meta charset="utf-8">')) {
    html = html.replace('<meta charset="utf-8">', '<meta charset="utf-8">' + optMeta);
  }

  // Automatically add loading="lazy" to non-hero off-screen images
  html = html.replace(/<img\s+([^>]*?)>/g, (match, p1) => {
    if (p1.includes('loading=')) return match;
    if (p1.includes('hero') || p1.includes('logo') || p1.includes('banner')) return match;
    return `<img ${p1} loading="lazy">`;
  });

  return html;
}

// 12 Products Database
const productsData = [
  { id: 1, name: "Thảm Da Carbon Cao Cấp", price: 1490000, material: "Carbon", colors: ["Đen"], image: "./assets/images/mat-carbon-gold.webp", isBestSeller: true, isNew: false, sku: "TM-001" },
  { id: 2, name: "Thảm Nhựa TPE Đúc Khuôn", price: 1890000, material: "TPE", colors: ["Đen"], image: "./assets/images/mat-tpe-black.webp", isBestSeller: false, isNew: false, sku: "TM-002" },
  { id: 3, name: "Thảm Da 5D Quả Trám", price: 1250000, material: "5D", colors: ["Nâu"], image: "./assets/images/mat-5d-brown.webp", isBestSeller: true, isNew: false, sku: "TM-003" },
  { id: 4, name: "Thảm Da 6D Rối Đa Tầng", price: 1650000, material: "6D", colors: ["Đỏ"], image: "./assets/images/mat-6d-red.webp", isBestSeller: false, isNew: true, sku: "TM-004" },
  { id: 5, name: "Thảm Da Carbon Sport Red", price: 1490000, material: "Carbon", colors: ["Đen", "Đỏ"], image: "./assets/images/mat-carbon-gold.webp", isBestSeller: false, isNew: true, sku: "TM-005" },
  { id: 6, name: "Thảm Nhựa TPE Eco Beige", price: 1990000, material: "TPE", colors: ["Kem"], image: "./assets/images/mat-tpe-black.webp", isBestSeller: false, isNew: true, sku: "TM-006" },
  { id: 7, name: "Thảm Da 5D Royal Cream", price: 1250000, material: "5D", colors: ["Kem"], image: "./assets/images/mat-5d-brown.webp", isBestSeller: true, isNew: false, sku: "TM-007" },
  { id: 8, name: "Thảm Da 6D Nâu Hoàng Gia", price: 1650000, material: "6D", colors: ["Nâu"], image: "./assets/images/mat-6d-red.webp", isBestSeller: false, isNew: false, sku: "TM-008" },
  { id: 9, name: "Thảm Cao Su Tự Nhiên Fit", price: 690000, material: "CaoSu", colors: ["Đen"], image: "./assets/images/mat-tpe-black.webp", isBestSeller: false, isNew: false, sku: "TM-009" },
  { id: 10, name: "Thảm Cao Su Tổ Ong Grey", price: 750000, material: "CaoSu", colors: ["Xám"], image: "./assets/images/mat-tpe-black.webp", isBestSeller: false, isNew: false, sku: "TM-010" },
  { id: 11, name: "Thảm Da Carbon Luxury Grey", price: 1590000, material: "Carbon", colors: ["Xám"], image: "./assets/images/mat-carbon-gold.webp", isBestSeller: false, isNew: true, sku: "TM-011" },
  { id: 12, name: "Thảm Da 6D Full 360 độ", price: 2490000, material: "6D", colors: ["Đen"], image: "./assets/images/mat-6d-red.webp", isBestSeller: false, isNew: false, sku: "TM-012" }
];

// 7 Articles Database
const articlesData = [
  {
    id: 1,
    title: "Bí quyết chọn thảm lót sàn ô tô phù hợp cho mùa mưa gió bão bùng",
    desc: "Mùa mưa bão sắp tới mang theo nỗi lo bùn đất bám vào nỉ sàn xe hơi gây nấm mốc, bốc mùi hôi thối khó chịu. Khám phá ngay các dòng thảm đúc khuôn nhựa TPE nguyên sinh hoặc thảm rối da 6D chống thấm, dễ xịt rửa vệ sinh tốt nhất cho chiếc xe hơi của bạn.",
    image: "./assets/images/news-featured.webp",
    slug: "bi-quyet-chon-tham-lot-san-o-to-phu-hop-cho-mua-mua-gio-bao-bung"
  },
  {
    id: 2,
    title: "Tại sao thảm lót sàn nhựa TPE lại trở thành xu hướng năm 2026?",
    desc: "Lý giải sức hút từ vật liệu nhựa TPE nguyên sinh đúc khuôn tràn viền: Độ bền vượt trội trên 10 năm, hoàn toàn không sinh mùi hôi độc hại khi đỗ xe nắng và chống nước tuyệt đối.",
    image: "./assets/images/news-featured.webp",
    slug: "tai-sao-tham-lot-san-nhua-tpe-la-xu-huong"
  },
  {
    id: 3,
    title: "Sự khác biệt vượt trội giữa thảm da carbon và thảm da 6D truyền thống",
    desc: "So sánh chi tiết về tính thẩm mỹ, độ bền chỉ may và khả năng chống bám bụi của hai dòng thảm da bán chạy nhất thị trường hiện nay. Nên lựa chọn loại nào cho phân khúc xế sang?",
    image: "./assets/images/news-featured.webp",
    slug: "su-khac-biet-vuot-troi-giua-tham-da-carbon-va-tham-da-6d-truyen-thong"
  },
  {
    id: 4,
    title: "Trung Thành Auto khai trương showroom trưng bày và dịch vụ lắp đặt mới tại Quận 7",
    desc: "Không gian showroom mới rộng rãi với đầy đủ bộ phom mẫu thảm thực tế giúp khách hàng dễ dàng sờ thử chất liệu da vân carbon, thảm rối và trải nghiệm quy trình quét 3D laser trực quan.",
    image: "./assets/images/about-workshop.webp",
    slug: "trung-thanh-auto-khai-truong-showroom-quan-7"
  },
  {
    id: 5,
    title: "Hướng dẫn tự vệ sinh thảm da 5D tại nhà cực nhanh trong 10 phút",
    desc: "Mẹo nhỏ sử dụng khăn ẩm vi sợi và dung dịch vệ sinh nội thất da chuyên dụng giúp làm sạch nhanh bụi đất dính kẹt trong các đường chỉ trám chéo mà không làm nổ da thảm.",
    image: "./assets/images/news-featured.webp",
    slug: "huong-dan-tu-ve-sinh-tham-da-5d-tai-nha"
  },
  {
    id: 6,
    title: "Đánh giá của các chuyên gia ô tô về chất lượng thảm đúc khuôn TPE Trung Thành Auto",
    desc: "Các reviewer đánh giá cao độ ôm khít chân phanh, mép thành thảm dựng đứng giữ nước đổ nghiêng, bảo vệ tuyệt hảo lớp nỉ sàn của dòng xe Toyota Camry và Ford Everest đời mới.",
    image: "./assets/images/news-featured.webp",
    slug: "danh-gia-chuyen-gia-chat-luong-tham-tpe"
  },
  {
    id: 7,
    title: "Cách bảo quản thảm lót sàn da luôn bền đẹp sáng bóng như ngày đầu",
    desc: "Tránh phơi thảm trực tiếp dưới trời nắng gắt nhiệt độ cao, hạn chế giặt ngâm nước toàn bộ đối với các dòng thảm da PU có lõi đệm mút xốp xơ bông để tránh rã keo bên trong.",
    image: "./assets/images/news-featured.webp",
    slug: "cach-bao-quan-tham-lot-san-da-luon-ben-dep"
  }
];

// Slugs generated dynamically for products
productsData.forEach(p => {
  p.slug = toSlug(p.name);
});

// Paths setup
const DIST_DIR = path.resolve(__dirname, '../dist');
const PRODUCT_TEMPLATE_PATH = path.join(DIST_DIR, 'chi-tiet.html');
const ARTICLE_TEMPLATE_PATH = path.join(DIST_DIR, 'chi-tiet-tin-tuc.html');

if (!fs.existsSync(DIST_DIR)) {
  console.error("Dist directory does not exist! Run build first.");
  process.exit(1);
}

// Ensure output directories exist
const SAN_PHAM_DIR = path.join(DIST_DIR, 'san-pham');
const TIN_TUC_DIR = path.join(DIST_DIR, 'tin-tuc');
if (!fs.existsSync(SAN_PHAM_DIR)) fs.mkdirSync(SAN_PHAM_DIR, { recursive: true });
if (!fs.existsSync(TIN_TUC_DIR)) fs.mkdirSync(TIN_TUC_DIR, { recursive: true });

console.log("Starting static site generation (SSG)...");

// --- Generate Product Pages ---
if (fs.existsSync(PRODUCT_TEMPLATE_PATH)) {
  const template = fs.readFileSync(PRODUCT_TEMPLATE_PATH, 'utf8');

  productsData.forEach(product => {
    let html = optimizeHtml(template);

    // Inject active product ID
    const injectScript = `<script>window.ACTIVE_PRODUCT_ID = ${product.id};</script>\n</head>`;
    html = html.replace('</head>', injectScript);

    // Replace canonical link
    const canonicalRegex = /<link\s+rel="canonical"\s+href="[^"]*"\s*\/?>/gi;
    const newCanonical = `<link rel="canonical" href="https://thamoto.vercel.app/san-pham/${product.slug}.html" />`;
    html = html.replace(canonicalRegex, newCanonical);

    // Replace Title
    html = html.replace(/<title>.*?<\/title>/gi, `<title>${product.name} - Trung Thành Auto</title>`);

    // Replace Description
    const descRegex = /<meta\s+name="description"\s+content="[^"]*"\s*\/?>/gi;
    const newDesc = `<meta name="description" content="${product.name} cao cấp, may đo thiết kế chuẩn khít phom xe 100%. Trung Thành Auto phân phối độc quyền chính hãng toàn quốc." />`;
    html = html.replace(descRegex, newDesc);

    // Replace Open Graph Tags
    html = html.replace(/property="og:title"\s+content="[^"]*"/gi, `property="og:title" content="${product.name} - Trung Thành Auto"`);
    html = html.replace(/property="og:description"\s+content="[^"]*"/gi, `property="og:description" content="${product.name} cao cấp, may đo chuẩn khít phom xe 100%."`);
    html = html.replace(/property="og:url"\s+content="[^"]*"/gi, `property="og:url" content="https://thamoto.vercel.app/san-pham/${product.slug}.html"`);
    html = html.replace(/property="og:image"\s+content="[^"]*"/gi, `property="og:image" content="https://thamoto.vercel.app/${product.image.replace(/^\.\//, '')}"`);

    // Replace Twitter Tags
    html = html.replace(/name="twitter:title"\s+content="[^"]*"/gi, `name="twitter:title" content="${product.name} - Trung Thành Auto"`);
    html = html.replace(/name="twitter:description"\s+content="[^"]*"/gi, `name="twitter:description" content="${product.name} cao cấp, may đo chuẩn khít phom xe 100%."`);
    html = html.replace(/name="twitter:image"\s+content="[^"]*"/gi, `name="twitter:image" content="https://thamoto.vercel.app/${product.image.replace(/^\.\//, '')}"`);

    // Inject Product JSON-LD Schema
    const schema = `
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "Product",
    "name": "${product.name}",
    "image": "https://thamoto.vercel.app/${product.image.replace(/^\.\//, '')}",
    "description": "${product.name} cao cấp chuẩn khít phom xe 100% từ Trung Thành Auto.",
    "sku": "${product.sku || 'TM-0' + product.id}",
    "brand": {
      "@type": "Brand",
      "name": "Trung Thành Auto"
    },
    "offers": {
      "@type": "Offer",
      "url": "https://thamoto.vercel.app/san-pham/${product.slug}.html",
      "priceCurrency": "VND",
      "price": "${product.price}",
      "availability": "https://schema.org/InStock",
      "itemCondition": "https://schema.org/NewCondition"
    }
  }
  </script>
  </head>`;
    html = html.replace('</head>', schema);

    const outPath = path.join(SAN_PHAM_DIR, `${product.slug}.html`);
    fs.writeFileSync(outPath, html, 'utf8');
    console.log(`Generated product page: /san-pham/${product.slug}.html`);
  });
} else {
  console.warn("Product template chi-tiet.html not found in dist!");
}

// --- Generate Article Pages ---
if (fs.existsSync(ARTICLE_TEMPLATE_PATH)) {
  const template = fs.readFileSync(ARTICLE_TEMPLATE_PATH, 'utf8');

  articlesData.forEach(article => {
    let html = optimizeHtml(template);

    // Inject active article ID
    const injectScript = `<script>window.ACTIVE_ARTICLE_ID = ${article.id};</script>\n</head>`;
    html = html.replace('</head>', injectScript);

    // Replace canonical link
    const canonicalRegex = /<link\s+rel="canonical"\s+href="[^"]*"\s*\/?>/gi;
    const newCanonical = `<link rel="canonical" href="https://thamoto.vercel.app/tin-tuc/${article.slug}.html" />`;
    html = html.replace(canonicalRegex, newCanonical);

    // Replace Title
    html = html.replace(/<title>.*?<\/title>/gi, `<title>${article.title} - Trung Thành Auto</title>`);

    // Replace Description
    const descRegex = /<meta\s+name="description"\s+content="[^"]*"\s*\/?>/gi;
    const newDesc = `<meta name="description" content="${article.desc}" />`;
    html = html.replace(descRegex, newDesc);

    // Replace Open Graph Tags
    html = html.replace(/property="og:title"\s+content="[^"]*"/gi, `property="og:title" content="${article.title} - Trung Thành Auto"`);
    html = html.replace(/property="og:description"\s+content="[^"]*"/gi, `property="og:description" content="${article.desc}"`);
    html = html.replace(/property="og:url"\s+content="[^"]*"/gi, `property="og:url" content="https://thamoto.vercel.app/tin-tuc/${article.slug}.html"`);
    html = html.replace(/property="og:image"\s+content="[^"]*"/gi, `property="og:image" content="https://thamoto.vercel.app/${article.image.replace(/^\.\//, '')}"`);

    // Replace Twitter Tags
    html = html.replace(/name="twitter:title"\s+content="[^"]*"/gi, `name="twitter:title" content="${article.title} - Trung Thành Auto"`);
    html = html.replace(/name="twitter:description"\s+content="[^"]*"/gi, `name="twitter:description" content="${article.desc}"`);
    html = html.replace(/name="twitter:image"\s+content="[^"]*"/gi, `name="twitter:image" content="https://thamoto.vercel.app/${article.image.replace(/^\.\//, '')}"`);

    // Inject NewsArticle JSON-LD Schema
    const schema = `
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "NewsArticle",
    "headline": "${article.title}",
    "image": [
      "https://thamoto.vercel.app/${article.image.replace(/^\.\//, '')}"
    ],
    "datePublished": "2026-06-15T08:00:00+07:00",
    "dateModified": "2026-06-15T08:00:00+07:00",
    "author": {
      "@type": "Organization",
      "name": "Trung Thành Auto",
      "url": "https://thamoto.vercel.app"
    },
    "publisher": {
      "@type": "Organization",
      "name": "Trung Thành Auto",
      "logo": {
        "@type": "ImageObject",
        "url": "https://thamoto.vercel.app/assets/images/trung-thanh-logo.png"
      }
    },
    "description": "${article.desc}"
  }
  </script>
  </head>`;
    html = html.replace('</head>', schema);

    const outPath = path.join(TIN_TUC_DIR, `${article.slug}.html`);
    fs.writeFileSync(outPath, html, 'utf8');
    console.log(`Generated article page: /tin-tuc/${article.slug}.html`);
  });
} else {
  console.warn("Article template chi-tiet-tin-tuc.html not found in dist!");
}

// --- Recursive Link Rewriter ---
console.log("Rewriting dynamic links in all built HTML files...");

function rewriteLinksInDir(dirPath) {
  const files = fs.readdirSync(dirPath);

  files.forEach(file => {
    const fullPath = path.join(dirPath, file);
    const stat = fs.statSync(fullPath);

    if (stat.isDirectory()) {
      rewriteLinksInDir(fullPath);
    } else if (file.endsWith('.html')) {
      let content = fs.readFileSync(fullPath, 'utf8');
      let originalContent = content;

      // Apply HTML Head and Image optimizations
      content = optimizeHtml(content);

      // Replace product links: chi-tiet.html?id=X and /chi-tiet.html?id=X
      productsData.forEach(product => {
        const regexes = [
          new RegExp(`(?<=href=["'])(?:\\/)?chi-tiet\\.html\\?id=${product.id}(?=["'])`, 'g'),
          new RegExp(`(?<=href=["'])(?:\\.\\/)?chi-tiet\\.html\\?id=${product.id}(?=["'])`, 'g')
        ];
        regexes.forEach(regex => {
          content = content.replace(regex, `/san-pham/${product.slug}.html`);
        });
      });

      // Replace article links: chi-tiet-tin-tuc.html?id=Y and /chi-tiet-tin-tuc.html?id=Y
      articlesData.forEach(article => {
        const regexes = [
          new RegExp(`(?<=href=["'])(?:\\/)?chi-tiet-tin-tuc\\.html\\?id=${article.id}(?=["'])`, 'g'),
          new RegExp(`(?<=href=["'])(?:\\.\\/)?chi-tiet-tin-tuc\\.html\\?id=${article.id}(?=["'])`, 'g')
        ];
        regexes.forEach(regex => {
          content = content.replace(regex, `/tin-tuc/${article.slug}.html`);
        });
      });

      if (content !== originalContent) {
        fs.writeFileSync(fullPath, content, 'utf8');
        console.log(`Rewrote links in: ${path.relative(DIST_DIR, fullPath)}`);
      }
    }
  });
}

rewriteLinksInDir(DIST_DIR);
console.log("Static Site Generation & Link Rewriting Completed Successfully!");
