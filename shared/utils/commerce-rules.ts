export type OrderStatus = 'new' | 'confirmed' | 'shipping' | 'completed' | 'cancelled' | 'returned';
export type AffiliateRole = 'ctv' | 'staff' | 'admin' | 'develop';
export type AffiliateStatus = 'pending' | 'active' | 'suspended' | 'cancelled';
export type CommissionStatus = 'pending' | 'holding' | 'available' | 'paid' | 'reversed';

export interface OrderLineInput {
  sku: string;
  unitPrice: number;
  quantity: number;
  productRuleRate?: number | null;
}

export interface CouponInput {
  code: string;
  discountType: 'percent' | 'fixed';
  discountValue: number;
  minOrder?: number;
  maxDiscount?: number | null;
  isActive: boolean;
  expiresAt?: number | null;
}

export interface AffiliateSnapshot {
  id: string;
  userId?: string | null;
  code: string;
  email?: string | null;
  phone?: string | null;
  role: AffiliateRole;
  status: AffiliateStatus;
  commissionRate: number;
  permissions?: Record<string, boolean>;
}

export interface LedgerEntry {
  idempotencyKey: string;
  commissionId: string;
  orderId: string;
  entryType: 'accrual' | 'release' | 'reversal' | 'clawback' | 'payout_debit';
  amount: number;
  balanceImpact: number;
}

export const ORDER_TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  new: ['confirmed', 'cancelled'],
  confirmed: ['shipping', 'completed', 'cancelled'],
  shipping: ['completed', 'cancelled', 'returned'],
  completed: ['returned'],
  cancelled: [],
  returned: []
};

export function normalizePhone(phone: string | null | undefined): string {
  return String(phone || '').replace(/[^0-9]/g, '');
}

/**
 * 1.1. Quy tắc ưu tiên tỷ lệ hoa hồng (Q1):
 * (1) Quy tắc theo sản phẩm -> (2) Tỷ lệ riêng của CTV -> (3) Mặc định hệ thống (10%)
 */
export function resolveCommissionRate(
  productRuleRate: number | null | undefined,
  affiliateRate: number | null | undefined,
  defaultRate = 10
): number {
  if (productRuleRate !== null && productRuleRate !== undefined && productRuleRate >= 0) {
    return Math.min(50, Math.max(0, Number(productRuleRate)));
  }
  if (affiliateRate !== null && affiliateRate !== undefined && affiliateRate >= 0) {
    return Math.min(50, Math.max(0, Number(affiliateRate)));
  }
  return Math.min(50, Math.max(0, Number(defaultRate)));
}

/**
 * 1.2. Tính tổng tiền, giảm giá coupon phân bổ theo từng dòng, và hoa hồng trên giá SAU giảm (Q1).
 * Làm tròn xuống (Math.floor) về số nguyên VNĐ.
 */
export function calculateOrderFinancials(
  items: OrderLineInput[],
  coupon: CouponInput | null,
  affiliate: Pick<AffiliateSnapshot, 'status' | 'commissionRate'> | null,
  defaultRate = 10,
  nowMs = Date.now()
) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error('Đơn hàng phải có ít nhất 1 sản phẩm');
  }

  const normalizedItems = items.map((item) => {
    const qty = Math.floor(Number(item.quantity || 0));
    const price = Math.floor(Number(item.unitPrice || 0));
    if (qty <= 0 || price < 0) {
      throw new Error(`Số lượng hoặc đơn giá không hợp lệ cho ${item.sku}`);
    }
    return { ...item, quantity: qty, unitPrice: price, lineSubtotal: qty * price };
  });

  const subtotal = normalizedItems.reduce((sum, it) => sum + it.lineSubtotal, 0);

  let discount = 0;
  let couponApplied = false;
  if (coupon && coupon.isActive) {
    const notExpired = !coupon.expiresAt || coupon.expiresAt >= nowMs;
    const meetsMin = !coupon.minOrder || subtotal >= coupon.minOrder;
    if (notExpired && meetsMin && subtotal > 0) {
      if (coupon.discountType === 'percent') {
        discount = Math.floor((subtotal * Math.min(100, Math.max(0, coupon.discountValue))) / 100);
        if (coupon.maxDiscount && coupon.maxDiscount > 0) {
          discount = Math.min(discount, Math.floor(coupon.maxDiscount));
        }
      } else {
        discount = Math.floor(Math.max(0, coupon.discountValue));
      }
      discount = Math.min(discount, subtotal);
      couponApplied = discount > 0;
    }
  }

  const total = Math.max(0, subtotal - discount);

  // Phân bổ giảm giá theo tỷ lệ từng dòng để tính hoa hồng trên giá trị thực thu sau giảm
  const activeAffiliate = affiliate && affiliate.status === 'active' ? affiliate : null;
  let remainingDiscount = discount;
  let totalCommission = 0;

  const lineResults = normalizedItems.map((it, idx) => {
    let lineDiscount = 0;
    if (discount > 0 && subtotal > 0) {
      if (idx === normalizedItems.length - 1) {
        lineDiscount = remainingDiscount;
      } else {
        lineDiscount = Math.floor((it.lineSubtotal * discount) / subtotal);
        remainingDiscount -= lineDiscount;
      }
    }
    const lineNet = Math.max(0, it.lineSubtotal - lineDiscount);
    const rate = activeAffiliate
      ? resolveCommissionRate(it.productRuleRate, activeAffiliate.commissionRate, defaultRate)
      : 0;
    const lineCommission = activeAffiliate ? Math.floor((lineNet * rate) / 100) : 0;
    totalCommission += lineCommission;
    return {
      sku: it.sku,
      lineSubtotal: it.lineSubtotal,
      lineDiscount,
      lineNet,
      commissionRate: rate,
      lineCommission
    };
  });

  return {
    subtotal,
    discount,
    total,
    couponApplied,
    commissionAmount: totalCommission,
    lines: lineResults
  };
}

/**
 * 1.3. Ghi nhận hoa hồng idempotent: mỗi đơn chỉ tạo tối đa 1 bút toán accrual.
 */
export function recordOrderCommissionAccrual(
  ledger: LedgerEntry[],
  commissionId: string,
  orderId: string,
  amount: number
): { ledger: LedgerEntry[]; created: boolean } {
  const key = `accrual:${orderId}`;
  if (ledger.some((e) => e.idempotencyKey === key) || amount <= 0) {
    return { ledger, created: false };
  }
  return {
    created: true,
    ledger: [
      ...ledger,
      { idempotencyKey: key, commissionId, orderId, entryType: 'accrual', amount, balanceImpact: 0 }
    ]
  };
}

/**
 * 1.4. Thu hồi hoa hồng khi hủy/hoàn đơn (idempotent — tuyệt đối không trừ 2 lần).
 * - Nếu đã 'paid': tạo bút toán 'clawback' âm trừ vào số dư khả dụng (Q3).
 * - Nếu đang 'available': tạo bút toán 'reversal' âm trừ phần khả dụng.
 * - Nếu đang 'pending'/'holding': tạo bút toán 'reversal' với balanceImpact = 0.
 */
export function applyCommissionReversal(
  ledger: LedgerEntry[],
  commissionId: string,
  orderId: string,
  currentStatus: CommissionStatus,
  amount: number
): { ledger: LedgerEntry[]; reversed: boolean; nextStatus: CommissionStatus } {
  if (currentStatus === 'reversed' || amount <= 0) {
    return { ledger, reversed: false, nextStatus: 'reversed' };
  }
  const entryType = currentStatus === 'paid' ? 'clawback' : 'reversal';
  const key = `${entryType}:${commissionId}`;
  if (ledger.some((e) => e.idempotencyKey === key || e.idempotencyKey === `reversal:${commissionId}` || e.idempotencyKey === `clawback:${commissionId}`)) {
    return { ledger, reversed: false, nextStatus: 'reversed' };
  }

  const balanceImpact = currentStatus === 'paid' || currentStatus === 'available' ? -Math.abs(amount) : 0;
  return {
    reversed: true,
    nextStatus: 'reversed',
    ledger: [
      ...ledger,
      {
        idempotencyKey: key,
        commissionId,
        orderId,
        entryType,
        amount: -Math.abs(amount),
        balanceImpact
      }
    ]
  };
}

/**
 * 1.5. Kiểm tra điều kiện tạo yêu cầu rút tiền (Q5).
 */
export function validatePayoutRequest(params: {
  affiliateStatus: AffiliateStatus;
  bankStatus: 'none' | 'pending' | 'verified' | 'rejected';
  hasOpenRequest: boolean;
  availableBalance: number;
  minPayoutAmount: number;
  requestedAmount: number;
}): { ok: boolean; error?: string } {
  if (params.affiliateStatus !== 'active') {
    return { ok: false, error: 'Tài khoản CTV chưa được kích hoạt' };
  }
  if (params.bankStatus !== 'verified') {
    return { ok: false, error: 'Tài khoản ngân hàng chưa được Admin xác minh' };
  }
  if (params.hasOpenRequest) {
    return { ok: false, error: 'Đang có yêu cầu rút tiền chờ xử lý' };
  }
  if (!Number.isFinite(params.requestedAmount) || params.requestedAmount < params.minPayoutAmount) {
    return { ok: false, error: `Số tiền rút tối thiểu là ${params.minPayoutAmount}` };
  }
  if (params.requestedAmount > params.availableBalance) {
    return { ok: false, error: 'Số tiền vượt quá số dư khả dụng' };
  }
  return { ok: true };
}

/**
 * 2. Attribution: xác thực mã CTV, hạn cookie 30 ngày, trạng thái active, chống tự mua (self-referral).
 */
export function resolveAttribution(params: {
  refCode: string | null | undefined;
  refExpiresAt?: number | null;
  nowMs?: number;
  affiliate: AffiliateSnapshot | null;
  buyerUserId?: string | null;
  buyerPhone?: string | null;
  buyerEmail?: string | null;
}): {
  attributedAffiliateId: string | null;
  attributedCode: string | null;
  eligibleForCommission: boolean;
  selfReferral: boolean;
  reason?: string;
} {
  const code = String(params.refCode || '').trim().toUpperCase();
  const now = params.nowMs ?? Date.now();
  if (!code) {
    return { attributedAffiliateId: null, attributedCode: null, eligibleForCommission: false, selfReferral: false };
  }
  if (params.refExpiresAt && params.refExpiresAt < now) {
    return { attributedAffiliateId: null, attributedCode: null, eligibleForCommission: false, selfReferral: false, reason: 'cookie_expired' };
  }
  if (!params.affiliate || params.affiliate.code.toUpperCase() !== code) {
    return { attributedAffiliateId: null, attributedCode: null, eligibleForCommission: false, selfReferral: false, reason: 'invalid_code' };
  }
  if (params.affiliate.status !== 'active') {
    return { attributedAffiliateId: null, attributedCode: null, eligibleForCommission: false, selfReferral: false, reason: 'affiliate_not_active' };
  }

  const sameUser = Boolean(params.buyerUserId && params.affiliate.userId && params.buyerUserId === params.affiliate.userId);
  const buyerPhoneNorm = normalizePhone(params.buyerPhone);
  const affPhoneNorm = normalizePhone(params.affiliate.phone);
  const samePhone = Boolean(buyerPhoneNorm.length >= 9 && buyerPhoneNorm === affPhoneNorm);
  const sameEmail = Boolean(
    params.buyerEmail && params.affiliate.email &&
    params.buyerEmail.trim().toLowerCase() === params.affiliate.email.trim().toLowerCase()
  );

  if (sameUser || samePhone || sameEmail) {
    return {
      attributedAffiliateId: params.affiliate.id,
      attributedCode: params.affiliate.code,
      eligibleForCommission: false,
      selfReferral: true,
      reason: 'self_referral'
    };
  }

  return {
    attributedAffiliateId: params.affiliate.id,
    attributedCode: params.affiliate.code,
    eligibleForCommission: true,
    selfReferral: false
  };
}

/**
 * 3.1. Phân quyền RBAC cho CTV / Staff / Admin / Develop.
 */
export function canAccessResource(
  actor: AffiliateSnapshot | null,
  action: 'ctv:view_orders' | 'admin:manage_orders' | 'admin:manage_affiliates' | 'admin:pay_commissions' | 'develop:set_role',
  targetAffiliateId?: string | null
): { allowed: boolean; statusCode: 200 | 401 | 403 } {
  if (!actor) return { allowed: false, statusCode: 401 };
  if (actor.status !== 'active') return { allowed: false, statusCode: 403 };

  if (action === 'ctv:view_orders') {
    if (actor.role === 'admin' || actor.role === 'develop') return { allowed: true, statusCode: 200 };
    if (targetAffiliateId && targetAffiliateId !== actor.id) return { allowed: false, statusCode: 403 };
    return { allowed: true, statusCode: 200 };
  }

  if (action === 'develop:set_role') {
    return actor.role === 'develop' ? { allowed: true, statusCode: 200 } : { allowed: false, statusCode: 403 };
  }

  if (actor.role === 'admin' || actor.role === 'develop') {
    return { allowed: true, statusCode: 200 };
  }

  if (actor.role === 'staff') {
    const perms = actor.permissions || {};
    if (action === 'admin:manage_orders' && perms.orders) return { allowed: true, statusCode: 200 };
    if (action === 'admin:manage_affiliates' && perms.affiliates) return { allowed: true, statusCode: 200 };
    if (action === 'admin:pay_commissions' && perms.payouts) return { allowed: true, statusCode: 200 };
  }

  return { allowed: false, statusCode: 403 };
}

/**
 * 3.2. Che thông tin cá nhân khách hàng (PII) trước khi trả về CTV.
 */
export function maskCustomerPii(customer: {
  name?: string | null;
  phone?: string | null;
  email?: string | null;
  address?: string | null;
}) {
  const cleanName = String(customer.name || '').trim();
  const firstWord = cleanName ? cleanName.split(/\s+/)[0] : 'Khách';
  const maskedName = `${firstWord} ***`;

  const digits = normalizePhone(customer.phone);
  const maskedPhone = digits.length >= 7 ? `${digits.slice(0, 3)}****${digits.slice(-3)}` : '***';

  const rawEmail = String(customer.email || '').trim();
  let maskedEmail = '***';
  if (rawEmail.includes('@')) {
    const [local, domain] = rawEmail.split('@');
    maskedEmail = `${(local || '').slice(0, 1)}***@${domain}`;
  }

  return {
    customer_name_masked: maskedName,
    customer_phone_masked: maskedPhone,
    customer_email_masked: maskedEmail
    // address cố tình KHÔNG trả về cho CTV
  };
}

/**
 * 4.1. Kiểm tra chuyển trạng thái đơn hàng hợp lệ.
 */
export function canTransitionOrderStatus(from: OrderStatus, to: OrderStatus): boolean {
  if (from === to) return true;
  return (ORDER_TRANSITIONS[from] || []).includes(to);
}

/**
 * 4.2. Đồng bộ tồn kho khi đặt đơn (giảm) và khi hủy/hoàn đơn (hoàn lại, idempotent).
 * stockQty === null nghĩa là không giới hạn tồn kho (hàng may đo).
 */
export function applyOrderStockChange(
  stockMap: Record<string, number | null>,
  items: Array<{ sku: string; quantity: number }>,
  event: 'order_created' | 'order_cancelled',
  alreadyRestored = false
): { stockMap: Record<string, number | null>; changed: boolean } {
  if (event === 'order_cancelled' && alreadyRestored) {
    return { stockMap, changed: false };
  }
  const next = { ...stockMap };
  let changed = false;

  for (const item of items) {
    const current = next[item.sku];
    if (current === null || current === undefined) continue;
    const qty = Math.max(0, Math.floor(item.quantity));
    if (event === 'order_created') {
      if (current < qty) {
        throw new Error(`Sản phẩm ${item.sku} không đủ tồn kho (còn ${current})`);
      }
      next[item.sku] = current - qty;
      changed = true;
    } else {
      next[item.sku] = current + qty;
      changed = true;
    }
  }
  return { stockMap: next, changed };
}

/**
 * 5.1. Admin duyệt / từ chối / khóa CTV + tạo bản ghi audit log.
 */
export function transitionAffiliateStatus(
  actor: AffiliateSnapshot,
  target: AffiliateSnapshot,
  nextStatus: AffiliateStatus,
  reason?: string | null
) {
  if (!canAccessResource(actor, 'admin:manage_affiliates').allowed) {
    throw new Error('Không có quyền cập nhật trạng thái CTV');
  }
  if (actor.id === target.id && nextStatus !== 'active') {
    throw new Error('Không thể tự khóa tài khoản của chính mình');
  }
  if ((nextStatus === 'suspended' || nextStatus === 'cancelled') && String(reason || '').trim().length < 3) {
    throw new Error('Vui lòng nhập lý do khi khóa hoặc hủy CTV');
  }

  return {
    updated: { ...target, status: nextStatus },
    auditLog: {
      actor_id: actor.userId || actor.id,
      actor_role: actor.role,
      action: 'admin_update_affiliate',
      table_name: 'affiliates',
      record_id: target.id,
      old_data: { status: target.status },
      new_data: { status: nextStatus },
      reason: reason ? reason.trim() : null
    }
  };
}

/**
 * 5.2. Admin duyệt hoa hồng & thanh toán rút tiền (cập nhật số dư, idempotent).
 */
export function settleAffiliatePayout(params: {
  availableBalance: number;
  paidTotal: number;
  payoutAmount: number;
  idempotencyKey: string;
  processedKeys: Set<string>;
}) {
  if (params.processedKeys.has(params.idempotencyKey)) {
    return {
      idempotentHit: true,
      availableBalance: params.availableBalance,
      paidTotal: params.paidTotal
    };
  }
  if (params.payoutAmount <= 0 || params.payoutAmount > params.availableBalance) {
    throw new Error('Số tiền chi trả không hợp lệ hoặc vượt quá số dư khả dụng');
  }
  params.processedKeys.add(params.idempotencyKey);
  return {
    idempotentHit: false,
    availableBalance: params.availableBalance - params.payoutAmount,
    paidTotal: params.paidTotal + params.payoutAmount
  };
}
