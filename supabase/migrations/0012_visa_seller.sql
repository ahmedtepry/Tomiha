-- Visa payments, seller per order, visa total in the shift report.
alter table public.orders add column if not exists seller_id uuid;

alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders add constraint orders_payment_method_check
  check (payment_method in ('cash', 'wallet', 'visa'));

create or replace function public.place_order(p_items jsonb, p_payment text default 'cash', p_eta integer default null, p_source text default 'app')
returns uuid language plpgsql security definer set search_path to '' as $function$
declare
  v_uid uuid := (select auth.uid());
  v_order uuid; v_item jsonb; v_item_id uuid; v_price numeric; v_aprice numeric;
  v_addon uuid; v_qty int; v_total numeric := 0; v_shift uuid; v_status text; v_pstatus text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_payment not in ('cash', 'wallet', 'visa') then raise exception 'bad payment'; end if;
  if p_payment = 'visa' and p_source <> 'pos' then raise exception 'bad payment'; end if;
  if p_source not in ('app', 'pos') then raise exception 'bad source'; end if;
  if p_source = 'pos' and not public.is_staff() then raise exception 'staff only'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'empty order'; end if;
  if jsonb_array_length(p_items) > 20 then raise exception 'too many items'; end if;

  if p_source = 'pos' then
    select id into v_shift from public.shifts
      where cashier_id = v_uid and closed_at is null order by opened_at desc limit 1;
    if v_shift is null then raise exception 'no open shift'; end if;
    v_status := 'delivered'; v_pstatus := 'paid';
  else
    v_status := 'received'; v_pstatus := 'unpaid';
  end if;

  insert into public.orders (customer_id, shift_id, source, status, payment_method, payment_status, eta_minutes)
  values (case when p_source = 'app' then v_uid else null end, v_shift, p_source, v_status, p_payment, v_pstatus, p_eta)
  returning id into v_order;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := greatest(1, least(coalesce((v_item ->> 'qty')::int, 1), 20));
    v_price := null;
    select dp.price into v_price
      from public.drink_prices dp join public.drinks d on d.id = dp.drink_id
      where dp.drink_id = (v_item ->> 'drink_id')::uuid and dp.size = v_item ->> 'size' and d.active;
    if v_price is null then raise exception 'unknown drink or size'; end if;

    insert into public.order_items (order_id, drink_id, size, sugar, qty, unit_price)
    values (v_order, (v_item ->> 'drink_id')::uuid, v_item ->> 'size',
            coalesce(v_item ->> 'sugar', 'normal'), v_qty, v_price)
    returning id into v_item_id;
    v_total := v_total + v_price * v_qty;

    for v_addon in
      select value::uuid from jsonb_array_elements_text(coalesce(v_item -> 'addon_ids', '[]'::jsonb))
    loop
      v_aprice := null;
      select price into v_aprice from public.addons where id = v_addon and active;
      if v_aprice is null then raise exception 'unknown addon'; end if;
      insert into public.order_item_addons (order_item_id, addon_id, price) values (v_item_id, v_addon, v_aprice);
      v_total := v_total + v_aprice * v_qty;
    end loop;
  end loop;

  update public.orders set total = v_total where id = v_order;
  return v_order;
end;
$function$;

create or replace function public.set_order_seller(p_order uuid, p_seller uuid)
returns void language plpgsql security definer set search_path to '' as $function$
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  update public.orders set seller_id = p_seller
    where id = p_order and source = 'pos'
      and shift_id in (select id from public.shifts where cashier_id = (select auth.uid()));
end;
$function$;

create or replace function public.shift_report(p_shift uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare
  v_s public.shifts; v_cash numeric; v_wallet numeric; v_visa numeric;
  v_cancel int; v_cups int; v_items jsonb;
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  select * into v_s from public.shifts where id = p_shift;
  if not found then raise exception 'shift not found'; end if;

  select coalesce(sum(total) filter (where payment_method = 'cash' and payment_status = 'paid'), 0),
         coalesce(sum(total) filter (where payment_method = 'wallet' and payment_status = 'paid'), 0),
         coalesce(sum(total) filter (where payment_method = 'visa' and payment_status = 'paid'), 0),
         count(*) filter (where status = 'cancelled')
    into v_cash, v_wallet, v_visa, v_cancel
    from public.orders where shift_id = p_shift;

  select coalesce(sum(i.qty), 0) into v_cups
    from public.order_items i join public.orders o on o.id = i.order_id
    where o.shift_id = p_shift and o.status <> 'cancelled';

  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'cups', t.cups) order by t.cups desc), '[]'::jsonb)
    into v_items
    from (
      select d.name, sum(i.qty)::int as cups
      from public.order_items i
      join public.orders o on o.id = i.order_id
      join public.drinks d on d.id = i.drink_id
      where o.shift_id = p_shift and o.status <> 'cancelled'
      group by d.name
    ) t;

  return jsonb_build_object(
    'opening_cash', v_s.opening_cash, 'cash_sales', v_cash, 'wallet_sales', v_wallet,
    'visa_sales', v_visa, 'expected_cash', v_s.opening_cash + v_cash,
    'cups', v_cups, 'cancelled', v_cancel, 'by_drink', v_items);
end;
$function$;
