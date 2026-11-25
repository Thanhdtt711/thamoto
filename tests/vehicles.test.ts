import test from 'node:test';
import assert from 'node:assert/strict';
import {
  toSlug,
  formatCurrency,
  BRAND_CATALOG,
  calculateMatPrice,
  getBrandByQuery,
  getModelsWithMeta,
  findVehicleByParams,
  getFormsForVehicle
} from '../shared/utils/vehicles.ts';

test('toSlug: chuẩn hóa tiếng Việt có dấu, đ/Đ và ký tự đặc biệt', () => {
  assert.equal(toSlug('Thảm Lót Sàn Ô Tô 6D'), 'tham-lot-san-o-to-6d');
  assert.equal(toSlug('Đời xe 2025 - Fortuner!'), 'doi-xe-2025-fortuner');
  assert.equal(toSlug(''), '');
});

test('formatCurrency: định dạng tiền VNĐ dạng 1.500.000 đ', () => {
  assert.match(formatCurrency(1500000), /1[.,]500[.,]000 đ/);
  assert.equal(formatCurrency(0), '0 đ');
});

test('calculateMatPrice: tính đúng giá chất liệu + phụ phí ưu đãi', () => {
  const base6d = calculateMatPrice({ materialName: 'Thảm 6D Cao Cấp' });
  const withAddons = calculateMatPrice({
    materialName: 'Thảm 6D Cao Cấp',
    selectedAddonIds: ['tham-roi', 'lot-cop']
  });
  assert.equal(withAddons - base6d, 450000);

  // Fallback khi tên chất liệu không khớp
  assert.equal(calculateMatPrice({ materialName: 'Không tồn tại' }), base6d);
});

test('getBrandByQuery & getModelsWithMeta: trả đúng hãng và fallback về Toyota khi rỗng/sai', () => {
  assert.equal(getBrandByQuery('honda').slug, 'honda');
  assert.equal(getBrandByQuery('Mercedes-Benz').slug, 'mercedes-benz');
  assert.equal(getBrandByQuery().slug, BRAND_CATALOG[0]!.slug);
  assert.equal(getBrandByQuery('khong-ton-tai').slug, BRAND_CATALOG[0]!.slug);

  const toyotaModels = getModelsWithMeta('toyota');
  assert.ok(toyotaModels.length > 0);
  assert.equal(toyotaModels[0]!.brandSlug, 'toyota');
});

test('findVehicleByParams & getFormsForVehicle: tìm xe theo hãng+xe, chỉ theo xe, và sinh 2 form đời xe', () => {
  const fortuner = findVehicleByParams('toyota', 'fortuner');
  assert.ok(fortuner);
  assert.equal(fortuner.brandSlug, 'toyota');
  assert.equal(fortuner.modelSlug, 'fortuner');

  const byModelOnly = findVehicleByParams(undefined, 'cx-5');
  assert.ok(byModelOnly);
  assert.equal(byModelOnly.brandSlug, 'mazda');

  assert.equal(findVehicleByParams('khong-co', 'fortuner'), null);
  assert.equal(findVehicleByParams('toyota', 'khong-co'), null);
  assert.equal(findVehicleByParams(undefined, undefined), null);

  const forms = getFormsForVehicle('Toyota', 'Fortuner');
  assert.equal(forms.length, 2);
  assert.equal(forms[0]!.id, 'form-moi');
  assert.equal(forms[1]!.id, 'form-cu');
});
