export interface CarModel {
  name: string;
  segment: 'SUV / CUV / MPV' | 'SEDAN / HATCHBACK';
  years: string[];
  image: string;
}

export interface CarBrand {
  name: string;
  slug: string;
  code: string;
  logo: string;
  models: CarModel[];
}

export interface CarModelWithMeta extends CarModel {
  brand: string;
  brandSlug: string;
  slug: string;
}

export function toSlug(str: string): string {
  return String(str || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[đĐ]/g, 'd')
    .replace(/[^a-z0-9\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

export function formatCurrency(amount: number): string {
  return `${Math.round(Number(amount || 0)).toLocaleString('vi-VN')} đ`;
}

export const BRAND_CATALOG: CarBrand[] = [
  {
    name: 'Toyota',
    slug: 'toyota',
    code: 'TOYOTA',
    logo: '/assets/images/brands/toyota.png',
    models: [
      { name: 'Fortuner', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017', '2016', '2015'], image: '/assets/images/cars/fortuner.webp' },
      { name: 'Corolla Cross', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/corolla-cross.webp' },
      { name: 'Innova', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017', '2016'], image: '/assets/images/cars/innova.webp' },
      { name: 'Raize', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021'], image: '/assets/images/cars/raize.webp' },
      { name: 'Veloz Cross', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022'], image: '/assets/images/cars/veloz-cross.webp' },
      { name: 'Vios', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017', '2016'], image: '/assets/images/cars/vios.webp' },
      { name: 'Camry', segment: 'SEDAN / HATCHBACK', years: ['2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/camry.webp' },
      { name: 'Corolla Altis', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/corolla-altis.webp' }
    ]
  },
  {
    name: 'Honda',
    slug: 'honda',
    code: 'HONDA',
    logo: '/assets/images/brands/honda.png',
    models: [
      { name: 'CR-V', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/cr-v.webp' },
      { name: 'HR-V', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019'], image: '/assets/images/cars/hr-v.webp' },
      { name: 'BR-V', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023'], image: '/assets/images/cars/br-v.webp' },
      { name: 'City', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/city.webp' },
      { name: 'Civic', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017'], image: '/assets/images/cars/civic.webp' },
      { name: 'Accord', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/accord.webp' }
    ]
  },
  {
    name: 'Mazda',
    slug: 'mazda',
    code: 'MAZDA',
    logo: '/assets/images/brands/mazda.png',
    models: [
      { name: 'CX-5', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/cx-5.webp' },
      { name: 'CX-8', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019'], image: '/assets/images/cars/cx-8.webp' },
      { name: 'CX-30', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021'], image: '/assets/images/cars/cx-30.webp' },
      { name: 'Mazda 3', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/mazda-3.webp' },
      { name: 'Mazda 6', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/mazda-6.webp' }
    ]
  },
  {
    name: 'Hyundai',
    slug: 'hyundai',
    code: 'HYUNDAI',
    logo: '/assets/images/brands/hyundai.png',
    models: [
      { name: 'SantaFe', segment: 'SUV / CUV / MPV', years: ['2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019'], image: '/assets/images/cars/santafe.webp' },
      { name: 'Tucson', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/tucson.webp' },
      { name: 'Creta', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/creta.webp' },
      { name: 'Accent', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/accent.webp' },
      { name: 'Elantra', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/elantra.webp' }
    ]
  },
  {
    name: 'Kia',
    slug: 'kia',
    code: 'KIA',
    logo: '/assets/images/brands/kia.png',
    models: [
      { name: 'Seltos', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/seltos.webp' },
      { name: 'Sorento', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/sorento.webp' },
      { name: 'Carnival', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021'], image: '/assets/images/cars/carnival.webp' },
      { name: 'K3', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022'], image: '/assets/images/cars/k3.webp' },
      { name: 'Morning', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017', '2016'], image: '/assets/images/cars/morning.webp' }
    ]
  },
  {
    name: 'Ford',
    slug: 'ford',
    code: 'FORD',
    logo: '/assets/images/brands/ford.png',
    models: [
      { name: 'Everest', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/everest.webp' },
      { name: 'Territory', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022'], image: '/assets/images/cars/territory.webp' },
      { name: 'Ranger', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/ranger.webp' }
    ]
  },
  {
    name: 'VinFast',
    slug: 'vinfast',
    code: 'VINFAST',
    logo: '/assets/images/brands/vinfast.png',
    models: [
      { name: 'VF 8', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022'], image: '/assets/images/cars/vf-8.webp' },
      { name: 'VF 7', segment: 'SUV / CUV / MPV', years: ['2025', '2024'], image: '/assets/images/cars/vf-7.webp' },
      { name: 'VF 6', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023'], image: '/assets/images/cars/vf-6.webp' },
      { name: 'VF 5', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023'], image: '/assets/images/cars/vf-5.webp' },
      { name: 'Lux A2.0', segment: 'SEDAN / HATCHBACK', years: ['2022', '2021', '2020', '2019'], image: '/assets/images/cars/lux-a20.webp' }
    ]
  },
  {
    name: 'Mitsubishi',
    slug: 'mitsubishi',
    code: 'MITSU',
    logo: '/assets/images/brands/mitsubishi.png',
    models: [
      { name: 'Xpander', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019'], image: '/assets/images/cars/xpander.webp' },
      { name: 'Xforce', segment: 'SUV / CUV / MPV', years: ['2025', '2024'], image: '/assets/images/cars/xforce.webp' },
      { name: 'Outlander', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/outlander.webp' },
      { name: 'Attrage', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/attrage.webp' }
    ]
  },
  {
    name: 'Mercedes-Benz',
    slug: 'mercedes-benz',
    code: 'MERCEDES',
    logo: '/assets/images/brands/mercedes-benz.png',
    models: [
      { name: 'GLC 200 / 300', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/glc-200-300.webp' },
      { name: 'C-Class (C200 / C300)', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018'], image: '/assets/images/cars/c-class-c200-c300.webp' },
      { name: 'E-Class (E200 / E300)', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019'], image: '/assets/images/cars/e-class-e200-e300.webp' }
    ]
  },
  {
    name: 'BMW',
    slug: 'bmw',
    code: 'BMW',
    logo: '/assets/images/brands/bmw.png',
    models: [
      { name: 'X3', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019'], image: '/assets/images/cars/x3.webp' },
      { name: 'X5', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/x5.webp' },
      { name: '3 Series (320i / 330i)', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019'], image: '/assets/images/cars/3-series-320i-330i.webp' }
    ]
  },
  {
    name: 'Lexus',
    slug: 'lexus',
    code: 'LEXUS',
    logo: '/assets/images/brands/lexus.png',
    models: [
      { name: 'RX 350', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019'], image: '/assets/images/cars/rx-350.webp' },
      { name: 'NX 350', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022'], image: '/assets/images/cars/nx-350.webp' },
      { name: 'ES 250', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/es-250.webp' }
    ]
  },
  {
    name: 'Audi',
    slug: 'audi',
    code: 'AUDI',
    logo: '/assets/images/brands/audi.png',
    models: [
      { name: 'Q5', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020', '2019'], image: '/assets/images/cars/q5.webp' },
      { name: 'Q7', segment: 'SUV / CUV / MPV', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/q7.webp' },
      { name: 'A4 / A6', segment: 'SEDAN / HATCHBACK', years: ['2025', '2024', '2023', '2022', '2021', '2020'], image: '/assets/images/cars/a4-a6.webp' }
    ]
  }
];

export const MAT_PRICING = {
  materials: {
    'Thảm 6D Cao Cấp': { basePrice: 1350000, image: '/assets/images/mat-6d-red.webp' },
    'Thảm 360 Full Xe': { basePrice: 2200000, image: '/assets/images/mat-carbon-gold.webp' },
    'Thảm Nhựa TPE Đúc Khuôn': { basePrice: 1890000, image: '/assets/images/mat-tpe-black.webp' },
    'Thảm Da 5D Quả Trám': { basePrice: 1250000, image: '/assets/images/mat-5d-brown.webp' }
  } as Record<string, { basePrice: number; image: string }>,
  addons: [
    { id: 'tham-roi', label: 'Tặng thảm rối chống bẩn (+150k)', shortLabel: 'Thảm rối chống bẩn', price: 150000, defaultChecked: true },
    { id: 'lot-cop', label: 'Mua thêm thảm lót cốp (+300k)', shortLabel: 'Thảm lót cốp', price: 300000, defaultChecked: false }
  ],
  colors: [
    { name: 'Đen chỉ đỏ', hex: '#18181B', ring: '#C81E2B' },
    { name: 'Nâu cafe', hex: '#5C3A21', ring: '#5C3A21' },
    { name: 'Kem', hex: '#E5D3B3', ring: '#CBD5E1' }
  ]
};

export function calculateMatPrice({ materialName, selectedAddonIds = [] }: { materialName: string; selectedAddonIds?: string[] }): number {
  const mat = MAT_PRICING.materials[materialName] || MAT_PRICING.materials['Thảm 6D Cao Cấp']!;
  const addonTotal = MAT_PRICING.addons
    .filter((a) => selectedAddonIds.includes(a.id))
    .reduce((sum, a) => sum + a.price, 0);
  return mat.basePrice + addonTotal;
}

export function getBrandByQuery(brandOrSlug?: string): CarBrand {
  if (!brandOrSlug) return BRAND_CATALOG[0]!;
  const target = toSlug(brandOrSlug);
  return BRAND_CATALOG.find((b) => b.slug === target || toSlug(b.name) === target) || BRAND_CATALOG[0]!;
}

export function getModelsWithMeta(brandOrSlug?: string): CarModelWithMeta[] {
  const found = getBrandByQuery(brandOrSlug);
  return found.models.map((m) => ({
    ...m,
    brand: found.name,
    brandSlug: found.slug,
    slug: toSlug(m.name)
  }));
}

export function findVehicleByParams(hangSlug?: string, xeSlug?: string) {
  if (hangSlug) {
    const target = toSlug(hangSlug);
    const brandObj = BRAND_CATALOG.find((b) => b.slug === target || toSlug(b.name) === target);
    if (!brandObj) return null;
    if (xeSlug) {
      const m = brandObj.models.find((item) => toSlug(item.name) === toSlug(xeSlug));
      if (m) return { brand: brandObj.name, brandSlug: brandObj.slug, model: m.name, modelSlug: toSlug(m.name), years: m.years, image: m.image };
    }
    return null;
  }
  if (xeSlug) {
    for (const b of BRAND_CATALOG) {
      const m = b.models.find((item) => toSlug(item.name) === toSlug(xeSlug));
      if (m) return { brand: b.name, brandSlug: b.slug, model: m.name, modelSlug: toSlug(m.name), years: m.years, image: m.image };
    }
  }
  return null;
}

export function getFormsForVehicle(brand: string, model: string) {
  const b = BRAND_CATALOG.find((x) => x.name === brand || x.slug === toSlug(brand));
  const m = b?.models.find((x) => x.name === model || toSlug(x.name) === toSlug(model));
  const years = m?.years || [];
  const maxYear = years.length ? parseInt(years[0]!, 10) : 2024;
  const minYear = years.length ? parseInt(years[years.length - 1]!, 10) : 2016;
  const splitYear = Math.max(minYear + 2, Math.min(2017, maxYear - 1));
  return [
    {
      id: 'form-moi',
      label: `ĐỜI ${splitYear} - ${maxYear} (Form Mới)`,
      minYear: splitYear,
      maxYear,
      image: '/assets/images/floor-after.webp'
    },
    {
      id: 'form-cu',
      label: `ĐỜI ${Math.min(2009, minYear)} - ${splitYear - 1} (Form Cũ)`,
      minYear: Math.min(2009, minYear),
      maxYear: splitYear - 1,
      image: '/assets/images/mat-5d-brown.webp'
    }
  ];
}
