-- ============================================================================
-- P2-6 (bổ sung): Đồng bộ tồn kho tự động khi đặt đơn & hoàn tồn kho khi hủy/hoàn
-- Lưu ý: Chỉ trừ/cộng khi products.stock_qty IS NOT NULL (NULL = không giới hạn)
-- Thứ tự chạy: 007 (sau 006)
-- Idempotent: Có
-- ============================================================================

alter table public.orders
  add column if not exists stock_restored boolean not null default false;

-- 1. Giảm tồn kho khi dòng sản phẩm (order_items) được tạo
create or replace function public.deduct_stock_on_order_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock int;
begin
  if new.product_id is null then
    return new;
  end if;

  select stock_qty into v_stock
  from public.products
  where id = new.product_id
  for update;

  if v_stock is not null then
    if v_stock < new.quantity then
      raise exception 'Sản phẩm % không đủ tồn kho (còn %)', coalesce(new.product_name, new.sku), v_stock;
    end if;
    update public.products
    set stock_qty = stock_qty - new.quantity, updated_at = now()
    where id = new.product_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_deduct_stock_on_order_item on public.order_items;
create trigger trg_deduct_stock_on_order_item
after insert on public.order_items
for each row execute function public.deduct_stock_on_order_item();

-- 2. Hoàn tồn kho 1 lần duy nhất (idempotent) khi đơn chuyển sang cancelled hoặc returned
create or replace function public.restore_stock_on_order_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('cancelled', 'returned')
     and old.status not in ('cancelled', 'returned')
     and coalesce(old.stock_restored, false) = false then
    update public.products p
    set stock_qty = p.stock_qty + oi.quantity,
        updated_at = now()
    from public.order_items oi
    where oi.order_id = new.id
      and oi.product_id = p.id
      and p.stock_qty is not null;

    update public.orders
    set stock_restored = true
    where id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_restore_stock_on_order_cancel on public.orders;
create trigger trg_restore_stock_on_order_cancel
after update of status on public.orders
for each row execute function public.restore_stock_on_order_cancel();

notify pgrst, 'reload schema';

-- ============================================================================
-- ROLLBACK (ghi chú):
--   drop trigger if exists trg_restore_stock_on_order_cancel on public.orders;
--   drop function if exists public.restore_stock_on_order_cancel();
--   drop trigger if exists trg_deduct_stock_on_order_item on public.order_items;
--   drop function if exists public.deduct_stock_on_order_item();
--   alter table public.orders drop column if exists stock_restored;
-- ============================================================================
