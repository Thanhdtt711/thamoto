import test from 'node:test';
import assert from 'node:assert/strict';
import {
  resolveCommissionRate,
  calculateOrderFinancials,
  recordOrderCommissionAccrual,
  applyCommissionReversal,
  validatePayoutRequest,
  resolveAttribution,
  canAccessResource,
  maskCustomerPii,
  canTransitionOrderStatus,
  applyOrderStockChange,
  transitionAffiliateStatus,
  settleAffiliatePayout,
  type AffiliateSnapshot,
  type LedgerEntry
} from '../shared/utils/commerce-rules.ts';

const ACTIVE_CTV: AffiliateSnapshot = {
  id: 'aff-ctv-a',
  userId: 'user-ctv-a',
  code: 'CTV01',
  email: 'ctv01@thamoto.vn',
  phone: '0963294492',
  role: 'ctv',
  status: 'active',
  commissionRate: 10
};

const ADMIN_USER: AffiliateSnapshot = {
  id: 'aff-admin',
  userId: 'user-admin',
  code: 'ADMIN01',
  email: 'admin@thamoto.vn',
  phone: '0900000001',
  role: 'admin',
  status: 'active',
  commissionRate: 0
};

const DEVELOP_USER: AffiliateSnapshot = {
  id: 'aff-dev',
  userId: 'user-dev',
  code: 'DEV01',
  email: 'dev@thamoto.vn',
  phone: '0900000000',
  role: 'develop',
  status: 'active',
  commissionRate: 0
};

// ============================================================================
// FOCUS AREA 1: TÍNH TIỀN & HOA HỒNG
// ============================================================================

test('1.1 resolveCommissionRate: ưu tiên quy tắc sản phẩm -> tỷ lệ CTV -> mặc định, kẹp trong [0, 50]', () => {
  assert.equal(resolveCommissionRate(15, 10, 8), 15);
  assert.equal(resolveCommissionRate(null, 12, 8), 12);
  assert.equal(resolveCommissionRate(undefined, undefined, 10), 10);
  assert.equal(resolveCommissionRate(80, 10, 10), 50);
  assert.equal(resolveCommissionRate(null, -5, 10), 10);
});

test('1.2 calculateOrderFinancials: tính hoa hồng trên giá SAU giảm giá coupon và làm tròn xuống (floor)', () => {
  // Subtotal = 1.350.000 + 150.000 = 1.500.000
  // Coupon GIAM5 (5%) => discount = 75.000, total = 1.425.000
  // Line 1 (MAT-6D): 1.350.000 - 67.500 = 1.282.500 * 12% (product rule) = 153.900
  // Line 2 (ADDON): 150.000 - 7.500 = 142.500 * 10% (CTV rate) = 14.250
  const res = calculateOrderFinancials(
    [
      { sku: 'MAT-6D', unitPrice: 1350000, quantity: 1, productRuleRate: 12 },
      { sku: 'ADDON-THAM-ROI', unitPrice: 150000, quantity: 1 }
    ],
    { code: 'GIAM5', discountType: 'percent', discountValue: 5, isActive: true },
    ACTIVE_CTV
  );

  assert.equal(res.subtotal, 1500000);
  assert.equal(res.discount, 75000);
  assert.equal(res.total, 1425000);
  assert.equal(res.couponApplied, true);
  assert.equal(res.commissionAmount, 153900 + 14250);
});

test('1.2b calculateOrderFinancials: làm tròn xuống với số lẻ, coupon fixed, coupon maxDiscount, coupon hết hạn/không đủ minOrder', () => {
  // 333.333 * 10% = 33.333,3 -> floor = 33.333
  const oddRes = calculateOrderFinancials(
    [{ sku: 'TEST', unitPrice: 333333, quantity: 1 }],
    null,
    ACTIVE_CTV
  );
  assert.equal(oddRes.commissionAmount, 33333);

  // Coupon percent với maxDiscount = 100.000
  const capped = calculateOrderFinancials(
    [{ sku: 'MAT-360', unitPrice: 2200000, quantity: 1 }],
    { code: 'BIG20', discountType: 'percent', discountValue: 20, maxDiscount: 100000, isActive: true },
    ACTIVE_CTV
  );
  assert.equal(capped.discount, 100000);
  assert.equal(capped.total, 2100000);
  assert.equal(capped.commissionAmount, 210000);

  // Coupon fixed lớn hơn subtotal -> discount kẹp ở subtotal, total = 0, commission = 0
  const fixedOver = calculateOrderFinancials(
    [{ sku: 'ADDON', unitPrice: 150000, quantity: 1 }],
    { code: 'FREE500', discountType: 'fixed', discountValue: 500000, isActive: true },
    ACTIVE_CTV
  );
  assert.equal(fixedOver.total, 0);
  assert.equal(fixedOver.commissionAmount, 0);

  // Coupon hết hạn hoặc không đủ minOrder -> không áp dụng
  const expired = calculateOrderFinancials(
    [{ sku: 'MAT-6D', unitPrice: 1350000, quantity: 1 }],
    { code: 'OLD', discountType: 'fixed', discountValue: 100000, isActive: true, expiresAt: 1000 },
    ACTIVE_CTV,
    10,
    2000
  );
  assert.equal(expired.couponApplied, false);
  assert.equal(expired.discount, 0);

  // Giỏ rỗng hoặc số lượng <= 0 -> ném lỗi
  assert.throws(() => calculateOrderFinancials([], null, ACTIVE_CTV));
  assert.throws(() => calculateOrderFinancials([{ sku: 'X', unitPrice: 100, quantity: 0 }], null, ACTIVE_CTV));
});

test('1.3 recordOrderCommissionAccrual: một đơn không bị tính hoa hồng trùng (idempotent)', () => {
  const first = recordOrderCommissionAccrual([], 'comm-1', 'ord-1', 150000);
  assert.equal(first.created, true);
  assert.equal(first.ledger.length, 1);

  const duplicate = recordOrderCommissionAccrual(first.ledger, 'comm-1', 'ord-1', 150000);
  assert.equal(duplicate.created, false);
  assert.equal(duplicate.ledger.length, 1);

  const zeroAmt = recordOrderCommissionAccrual([], 'comm-2', 'ord-2', 0);
  assert.equal(zeroAmt.created, false);
});

test('1.4 applyCommissionReversal: hủy/hoàn đơn thu hồi hoa hồng đúng và KHÔNG trừ 2 lần', () => {
  const initial: LedgerEntry[] = [];

  // Đơn đang holding -> hủy: tạo reversal balanceImpact = 0
  const revHolding = applyCommissionReversal(initial, 'comm-1', 'ord-1', 'holding', 150000);
  assert.equal(revHolding.reversed, true);
  assert.equal(revHolding.nextStatus, 'reversed');
  assert.equal(revHolding.ledger[0]!.entryType, 'reversal');
  assert.equal(revHolding.ledger[0]!.balanceImpact, 0);

  // Gọi hủy lần 2 -> idempotent, KHÔNG trừ lần 2
  const revAgain = applyCommissionReversal(revHolding.ledger, 'comm-1', 'ord-1', 'holding', 150000);
  assert.equal(revAgain.reversed, false);
  assert.equal(revAgain.ledger.length, 1);

  // Đơn đã chi trả (paid) -> hoàn hàng: tạo clawback âm trừ vào số dư khả dụng
  const clawback = applyCommissionReversal([], 'comm-2', 'ord-2', 'paid', 200000);
  assert.equal(clawback.reversed, true);
  assert.equal(clawback.ledger[0]!.entryType, 'clawback');
  assert.equal(clawback.ledger[0]!.balanceImpact, -200000);

  // Đã reversed sẵn -> bỏ qua
  const alreadyReversed = applyCommissionReversal(clawback.ledger, 'comm-2', 'ord-2', 'reversed', 200000);
  assert.equal(alreadyReversed.reversed, false);
});

test('1.5 validatePayoutRequest: chặn rút quá số dư, chặn khi có yêu cầu đang mở, chặn dưới mức tối thiểu hoặc chưa xác minh ngân hàng', () => {
  // Hợp lệ
  assert.equal(
    validatePayoutRequest({
      affiliateStatus: 'active',
      bankStatus: 'verified',
      hasOpenRequest: false,
      availableBalance: 500000,
      minPayoutAmount: 200000,
      requestedAmount: 300000
    }).ok,
    true
  );

  // Vượt quá số dư
  assert.equal(
    validatePayoutRequest({
      affiliateStatus: 'active',
      bankStatus: 'verified',
      hasOpenRequest: false,
      availableBalance: 250000,
      minPayoutAmount: 200000,
      requestedAmount: 300000
    }).ok,
    false
  );

  // Đang có yêu cầu chờ duyệt
  assert.equal(
    validatePayoutRequest({
      affiliateStatus: 'active',
      bankStatus: 'verified',
      hasOpenRequest: true,
      availableBalance: 500000,
      minPayoutAmount: 200000,
      requestedAmount: 200000
    }).ok,
    false
  );

  // Dưới mức tối thiểu / chưa xác minh ngân hàng / CTV bị khóa
  assert.equal(validatePayoutRequest({ affiliateStatus: 'active', bankStatus: 'verified', hasOpenRequest: false, availableBalance: 500000, minPayoutAmount: 200000, requestedAmount: 100000 }).ok, false);
  assert.equal(validatePayoutRequest({ affiliateStatus: 'active', bankStatus: 'pending', hasOpenRequest: false, availableBalance: 500000, minPayoutAmount: 200000, requestedAmount: 200000 }).ok, false);
  assert.equal(validatePayoutRequest({ affiliateStatus: 'suspended', bankStatus: 'verified', hasOpenRequest: false, availableBalance: 500000, minPayoutAmount: 200000, requestedAmount: 200000 }).ok, false);
});

// ============================================================================
// FOCUS AREA 2: ATTRIBUTION (GHI NHẬN CTV)
// ============================================================================

test('2.1 resolveAttribution: mã hợp lệ -> gắn đúng CTV; mã sai / CTV khóa / chờ duyệt / hết hạn cookie / tự mua -> không tính HH', () => {
  const now = 1_700_000_000_000;

  // Hợp lệ
  const ok = resolveAttribution({
    refCode: 'ctv01',
    refExpiresAt: now + 86400_000,
    nowMs: now,
    affiliate: ACTIVE_CTV,
    buyerPhone: '0911111111'
  });
  assert.equal(ok.attributedAffiliateId, ACTIVE_CTV.id);
  assert.equal(ok.eligibleForCommission, true);
  assert.equal(ok.selfReferral, false);

  // Hết hạn cookie (> 30 ngày)
  const expired = resolveAttribution({
    refCode: 'CTV01',
    refExpiresAt: now - 1,
    nowMs: now,
    affiliate: ACTIVE_CTV,
    buyerPhone: '0911111111'
  });
  assert.equal(expired.eligibleForCommission, false);
  assert.equal(expired.reason, 'cookie_expired');

  // Mã sai / không tồn tại
  const invalid = resolveAttribution({ refCode: 'KHONGTONTAI', affiliate: null });
  assert.equal(invalid.eligibleForCommission, false);
  assert.equal(invalid.reason, 'invalid_code');

  // CTV chưa duyệt hoặc bị khóa
  const pending = resolveAttribution({
    refCode: 'CTV01',
    affiliate: { ...ACTIVE_CTV, status: 'pending' },
    buyerPhone: '0911111111'
  });
  assert.equal(pending.eligibleForCommission, false);
  assert.equal(pending.reason, 'affiliate_not_active');

  // Tự mua (khớp SĐT, khớp userId, hoặc khớp email) -> selfReferral = true, commission = 0
  const selfPhone = resolveAttribution({ refCode: 'CTV01', affiliate: ACTIVE_CTV, buyerPhone: '0963 294 492' });
  assert.equal(selfPhone.selfReferral, true);
  assert.equal(selfPhone.eligibleForCommission, false);

  const selfUser = resolveAttribution({ refCode: 'CTV01', affiliate: ACTIVE_CTV, buyerUserId: 'user-ctv-a' });
  assert.equal(selfUser.selfReferral, true);
  assert.equal(selfUser.eligibleForCommission, false);

  const selfEmail = resolveAttribution({ refCode: 'CTV01', affiliate: ACTIVE_CTV, buyerEmail: 'CTV01@thamoto.vn' });
  assert.equal(selfEmail.selfReferral, true);
  assert.equal(selfEmail.eligibleForCommission, false);

  // Không có mã giới thiệu
  const noCode = resolveAttribution({ refCode: '', affiliate: null });
  assert.equal(noCode.attributedAffiliateId, null);
});

// ============================================================================
// FOCUS AREA 3: PHÂN QUYỀN (RBAC) & CHE DỮ LIỆU KHÁCH HÀNG (PII)
// ============================================================================

test('3.1 canAccessResource: CTV A không xem được đơn CTV B (403); CTV gọi API admin bị chặn (403); CTV khóa bị chặn (403)', () => {
  // Chưa đăng nhập -> 401
  assert.equal(canAccessResource(null, 'ctv:view_orders').statusCode, 401);

  // CTV A xem đơn của chính mình -> 200
  assert.equal(canAccessResource(ACTIVE_CTV, 'ctv:view_orders', 'aff-ctv-a').allowed, true);

  // CTV A xem đơn của CTV B -> 403
  const crossCtv = canAccessResource(ACTIVE_CTV, 'ctv:view_orders', 'aff-ctv-b');
  assert.equal(crossCtv.allowed, false);
  assert.equal(crossCtv.statusCode, 403);

  // CTV gọi API admin -> 403
  assert.equal(canAccessResource(ACTIVE_CTV, 'admin:manage_orders').statusCode, 403);
  assert.equal(canAccessResource(ACTIVE_CTV, 'admin:pay_commissions').statusCode, 403);

  // CTV chưa duyệt / bị khóa -> 403
  assert.equal(canAccessResource({ ...ACTIVE_CTV, status: 'pending' }, 'ctv:view_orders', 'aff-ctv-a').statusCode, 403);
  assert.equal(canAccessResource({ ...ACTIVE_CTV, status: 'suspended' }, 'ctv:view_orders', 'aff-ctv-a').statusCode, 403);

  // Admin không được gọi quyền riêng của Develop
  assert.equal(canAccessResource(ADMIN_USER, 'develop:set_role').statusCode, 403);
  assert.equal(canAccessResource(DEVELOP_USER, 'develop:set_role').allowed, true);

  // Staff chỉ được vào quyền đã cấp
  const staff: AffiliateSnapshot = { ...ACTIVE_CTV, role: 'staff', permissions: { orders: true, payouts: false } };
  assert.equal(canAccessResource(staff, 'admin:manage_orders').allowed, true);
  assert.equal(canAccessResource(staff, 'admin:pay_commissions').statusCode, 403);
});

test('3.2 maskCustomerPii: che tên, SĐT, email và loại bỏ hoàn toàn địa chỉ', () => {
  const masked = maskCustomerPii({
    name: 'Nguyễn Văn Hùng',
    phone: '0963 294 492',
    email: 'hung.nguyen@gmail.com',
    address: '123 Yên Lãng, Đống Đa, Hà Nội'
  });

  assert.equal(masked.customer_name_masked, 'Nguyễn ***');
  assert.equal(masked.customer_phone_masked, '096****492');
  assert.equal(masked.customer_email_masked, 'h***@gmail.com');
  assert.equal('address' in masked, false);

  // Edge cases: rỗng / ngắn
  const empty = maskCustomerPii({});
  assert.equal(empty.customer_name_masked, 'Khách ***');
  assert.equal(empty.customer_phone_masked, '***');
  assert.equal(empty.customer_email_masked, '***');
});

// ============================================================================
// FOCUS AREA 4: LUỒNG TRẠNG THÁI ĐƠN HÀNG & TỒN KHO
// ============================================================================

test('4.1 canTransitionOrderStatus: cho phép luồng hợp lệ và chặn chuyển ngược/sai', () => {
  assert.equal(canTransitionOrderStatus('new', 'confirmed'), true);
  assert.equal(canTransitionOrderStatus('confirmed', 'shipping'), true);
  assert.equal(canTransitionOrderStatus('shipping', 'completed'), true);
  assert.equal(canTransitionOrderStatus('completed', 'returned'), true);
  assert.equal(canTransitionOrderStatus('new', 'new'), true);

  // Chặn chuyển sai
  assert.equal(canTransitionOrderStatus('completed', 'new'), false);
  assert.equal(canTransitionOrderStatus('cancelled', 'confirmed'), false);
  assert.equal(canTransitionOrderStatus('returned', 'completed'), false);
  assert.equal(canTransitionOrderStatus('new', 'completed'), false);
});

test('4.2 applyOrderStockChange: giảm tồn kho khi đặt, hoàn lại khi hủy, không hoàn 2 lần, giữ NULL không giới hạn', () => {
  const initialStock: Record<string, number | null> = { 'MAT-TPE': 10, 'MAT-6D': null };

  // Đặt 2 bộ MAT-TPE + 1 bộ MAT-6D (unlimited)
  const afterCreate = applyOrderStockChange(
    initialStock,
    [{ sku: 'MAT-TPE', quantity: 2 }, { sku: 'MAT-6D', quantity: 1 }],
    'order_created'
  );
  assert.equal(afterCreate.changed, true);
  assert.equal(afterCreate.stockMap['MAT-TPE'], 8);
  assert.equal(afterCreate.stockMap['MAT-6D'], null);

  // Đặt quá tồn kho -> ném lỗi
  assert.throws(() =>
    applyOrderStockChange(afterCreate.stockMap, [{ sku: 'MAT-TPE', quantity: 20 }], 'order_created')
  );

  // Hủy đơn -> hoàn lại đúng 2 bộ
  const afterCancel = applyOrderStockChange(
    afterCreate.stockMap,
    [{ sku: 'MAT-TPE', quantity: 2 }],
    'order_cancelled',
    false
  );
  assert.equal(afterCancel.stockMap['MAT-TPE'], 10);

  // Hủy lần 2 (alreadyRestored = true) -> idempotent, không cộng thêm
  const cancelAgain = applyOrderStockChange(
    afterCancel.stockMap,
    [{ sku: 'MAT-TPE', quantity: 2 }],
    'order_cancelled',
    true
  );
  assert.equal(cancelAgain.changed, false);
  assert.equal(cancelAgain.stockMap['MAT-TPE'], 10);
});

// ============================================================================
// FOCUS AREA 5: ADMIN (DUYỆT/KHÓA CTV + AUDIT LOG + CHI TRẢ RÚT TIỀN)
// ============================================================================

test('5.1 transitionAffiliateStatus: duyệt/khóa CTV đổi đúng trạng thái, ghi audit log, bắt buộc lý do khi khóa', () => {
  const pendingCtv: AffiliateSnapshot = { ...ACTIVE_CTV, status: 'pending' };

  // Admin duyệt CTV
  const approved = transitionAffiliateStatus(ADMIN_USER, pendingCtv, 'active');
  assert.equal(approved.updated.status, 'active');
  assert.equal(approved.auditLog.action, 'admin_update_affiliate');
  assert.equal(approved.auditLog.old_data.status, 'pending');
  assert.equal(approved.auditLog.new_data.status, 'active');

  // Khóa không có lý do -> lỗi
  assert.throws(() => transitionAffiliateStatus(ADMIN_USER, ACTIVE_CTV, 'suspended', ''));

  // Khóa có lý do -> thành công + ghi lý do vào audit log
  const suspended = transitionAffiliateStatus(ADMIN_USER, ACTIVE_CTV, 'suspended', 'Vi phạm tự mua');
  assert.equal(suspended.updated.status, 'suspended');
  assert.equal(suspended.auditLog.reason, 'Vi phạm tự mua');

  // CTV thường không được duyệt / Admin không được tự khóa chính mình
  assert.throws(() => transitionAffiliateStatus(ACTIVE_CTV, pendingCtv, 'active'));
  assert.throws(() => transitionAffiliateStatus(ADMIN_USER, ADMIN_USER, 'suspended', 'test'));
});

test('5.2 settleAffiliatePayout: chi trả trừ đúng số dư khả dụng, cộng tổng đã trả, và idempotent', () => {
  const processed = new Set<string>();

  const paid = settleAffiliatePayout({
    availableBalance: 500000,
    paidTotal: 100000,
    payoutAmount: 300000,
    idempotencyKey: 'payout_req:001',
    processedKeys: processed
  });
  assert.equal(paid.idempotentHit, false);
  assert.equal(paid.availableBalance, 200000);
  assert.equal(paid.paidTotal, 400000);

  // Gọi lại cùng idempotencyKey -> không trừ lần 2
  const replay = settleAffiliatePayout({
    availableBalance: paid.availableBalance,
    paidTotal: paid.paidTotal,
    payoutAmount: 300000,
    idempotencyKey: 'payout_req:001',
    processedKeys: processed
  });
  assert.equal(replay.idempotentHit, true);
  assert.equal(replay.availableBalance, 200000);

  // Chi trả vượt số dư -> lỗi
  assert.throws(() =>
    settleAffiliatePayout({
      availableBalance: 200000,
      paidTotal: 400000,
      payoutAmount: 250000,
      idempotencyKey: 'payout_req:002',
      processedKeys: processed
    })
  );
});
