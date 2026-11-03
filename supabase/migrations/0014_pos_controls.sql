-- Hardening + POS controls: discounts, cancel/refund with reason, stock, supervisor role, reports.
alter table public.orders
  add column if not exists discount numeric not null default 0,
  add column if not exists discount_reason text,
  add column if not exists note text,
  add column if not exists cancel_reason text,
  add column if not exists cancelled_by uuid;
alter table public.drinks
  add column if not exists stock_qty int,
  add column if not exists sold_out boolean not null default false;

-- Staff could edit totals and shifts directly through the API. Only the owner may now.
create policy "orders insert owner only" on public.orders as restrictive for insert
  with check ((select public.is_manager()));
create policy "orders update owner only" on public.orders as restrictive for update
  using ((select public.is_manager())) with check ((select public.is_manager()));
create policy "shifts update owner only" on public.shifts as restrictive for update
  using ((select public.is_manager())) with check ((select public.is_manager()));
create policy "shifts delete owner only" on public.shifts as restrictive for delete
  using ((select public.is_manager()));
create policy "shifts insert own" on public.shifts as restrictive for insert
  with check (cashier_id = (select auth.uid()) or (select public.is_manager()));

-- Supervisor (مدير): a staff member with extra powers, below the owner.
alter table public.profiles drop constraint if exists profiles_staff_role_check;
alter table public.profiles add constraint profiles_staff_role_check
  check (staff_role in ('seller', 'barista', 'delivery', 'reception', 'manager'));

create or replace function public.is_supervisor() returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.profiles p
    where p.id = (select auth.uid()) and (p.role = 'manager' or p.staff_role = 'manager'));
$$;

create policy "expenses supervisor" on public.expenses for all
  using ((select public.is_supervisor())) with check ((select public.is_supervisor()));
create policy "attendance supervisor read" on public.attendance for select
  using ((select public.is_supervisor()));
create policy "bonuses supervisor read" on public.staff_bonuses for select
  using ((select public.is_supervisor()));
create policy "gear supervisor read" on public.gear for select
  using ((select public.is_supervisor()));

create or replace function public.owner_set_staff(p_user uuid, p_staff_role text, p_shift_start time)
returns text language plpgsql security definer set search_path to '' as $function$
declare v_no text; v_try int := 0;
begin
  if not public.is_manager() then raise exception 'not allowed'; end if;
  if p_staff_role not in ('seller', 'barista', 'delivery', 'reception', 'manager') then
    raise exception 'bad role';
  end if;
  select employee_no into v_no from public.profiles where id = p_user;
  if v_no is null then
    loop
      v_no := (10 + floor(random() * 90))::int::text;
      exit when not exists (select 1 from public.profiles where employee_no = v_no);
      v_try := v_try + 1;
      if v_try > 200 then raise exception 'no free employee number'; end if;
    end loop;
  end if;
  update public.profiles
    set role = case when role = 'manager' then role else 'cashier' end,
        staff_role = p_staff_role, shift_start = p_shift_start, employee_no = v_no, active = true
    where id = p_user;
  return v_no;
end;
$function$;

create or replace function public.confirm_order_payment(p_order uuid)
returns void language plpgsql security definer set search_path to '' as $function$
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  if public.my_staff_role() not in ('manager', 'any', 'reception', 'seller') then
    raise exception 'not allowed';
  end if;
  update public.orders set status = 'received', payment_status = 'paid', updated_at = now()
    where id = p_order and status = 'pending_payment';
  if not found then raise exception 'order is not waiting for payment'; end if;
end;
$function$;

-- Place order now respects stock and "sold out".
create or replace function public.place_order(p_items jsonb, p_payment text default 'cash', p_eta integer default null, p_source text default 'app')
returns uuid language plpgsql security definer set search_path to '' as $function$
declare
  v_uid uuid := (select auth.uid());
  v_order uuid; v_item jsonb; v_item_id uuid; v_price numeric; v_aprice numeric;
  v_addon uuid; v_qty int; v_total numeric := 0; v_shift uuid; v_status text; v_pstatus text;
  v_left int; v_drink uuid;
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
    v_drink := (v_item ->> 'drink_id')::uuid;
    v_price := null;
    select dp.price into v_price
      from public.drink_prices dp join public.drinks d on d.id = dp.drink_id
      where dp.drink_id = v_drink and dp.size = v_item ->> 'size' and d.active;
    if v_price is null then raise exception 'unknown drink or size'; end if;
    if exists (select 1 from public.drinks where id = v_drink and sold_out) then raise exception 'out_of_stock'; end if;
    update public.drinks set stock_qty = stock_qty - v_qty
      where id = v_drink and stock_qty is not null returning stock_qty into v_left;
    if found and v_left < 0 then raise exception 'out_of_stock'; end if;

    insert into public.order_items (order_id, drink_id, size, sugar, qty, unit_price)
    values (v_order, v_drink, v_item ->> 'size', coalesce(v_item ->> 'sugar', 'normal'), v_qty, v_price)
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

create or replace function public.restore_stock(p_order uuid) returns void
language sql security definer set search_path to '' as $$
  update public.drinks d set stock_qty = d.stock_qty + x.q
    from (select drink_id, sum(qty)::int q from public.order_items where order_id = p_order group by drink_id) x
    where d.id = x.drink_id and d.stock_qty is not null;
$$;
revoke execute on function public.restore_stock(uuid) from public, anon, authenticated;

-- Cancel / void with a reason. A paid order becomes "refunded".
create or replace function public.cancel_order(p_order uuid, p_reason text)
returns void language plpgsql security definer set search_path to '' as $function$
declare v_o public.orders; v_r text := public.my_staff_role(); v_uid uuid := (select auth.uid());
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  select * into v_o from public.orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;
  if v_o.status = 'cancelled' then raise exception 'already cancelled'; end if;
  if not (
    v_r in ('manager', 'any')
    or (v_r = 'reception' and v_o.source = 'app' and v_o.status <> 'delivered')
    or (v_r = 'seller' and v_o.source = 'pos' and v_o.shift_id in
        (select id from public.shifts where cashier_id = v_uid and closed_at is null))
  ) then raise exception 'not allowed'; end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'reason required'; end if;
  update public.orders
    set status = 'cancelled',
        payment_status = case when payment_status = 'paid' then 'refunded' else payment_status end,
        cancel_reason = left(trim(p_reason), 200), cancelled_by = v_uid, updated_at = now()
    where id = p_order;
  perform public.restore_stock(p_order);
end;
$function$;

create or replace function public.customer_cancel_order(p_order uuid)
returns void language plpgsql security definer set search_path to '' as $function$
declare v_uid uuid := (select auth.uid());
begin
  update public.orders
    set status = 'cancelled', cancel_reason = 'العميل ألغى الأوردر', cancelled_by = v_uid, updated_at = now()
    where id = p_order and customer_id = v_uid and status = 'pending_payment';
  if not found then raise exception 'cannot cancel'; end if;
  perform public.restore_stock(p_order);
end;
$function$;

-- After a POS sale: who sold it, optional discount (limited unless supervisor), optional note.
create or replace function public.pos_finalize(p_order uuid, p_seller uuid, p_discount numeric, p_reason text, p_note text)
returns void language plpgsql security definer set search_path to '' as $function$
declare
  v_o public.orders; v_uid uuid := (select auth.uid());
  v_max numeric; v_disc numeric := greatest(coalesce(p_discount, 0), 0);
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  select * into v_o from public.orders
    where id = p_order and source = 'pos'
      and shift_id in (select id from public.shifts where cashier_id = v_uid and closed_at is null)
    for update;
  if not found then raise exception 'order not found'; end if;
  if v_o.discount > 0 then raise exception 'already discounted'; end if;
  v_max := coalesce((select (value ->> 'max_discount_pct')::numeric from public.app_settings where key = 'pos'), 10);
  if v_disc > v_o.total then raise exception 'discount too high'; end if;
  if v_disc > 0 then
    if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'reason required'; end if;
    if not public.is_supervisor() and v_disc > round(v_o.total * v_max / 100, 2) then
      raise exception 'discount too high';
    end if;
  end if;
  update public.orders set
    seller_id = case when exists (select 1 from public.profiles
                  where id = p_seller and coalesce(active, true) and (staff_role is not null or role = 'manager'))
                then p_seller else seller_id end,
    discount = v_disc,
    discount_reason = case when v_disc > 0 then left(trim(p_reason), 200) end,
    note = left(nullif(trim(coalesce(p_note, '')), ''), 200),
    total = total - v_disc
    where id = p_order;
end;
$function$;

create or replace function public.set_sold_out(p_drink uuid, p_sold boolean)
returns void language plpgsql security definer set search_path to '' as $function$
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  if public.my_staff_role() not in ('manager', 'any', 'seller', 'barista') then raise exception 'not allowed'; end if;
  update public.drinks set sold_out = p_sold where id = p_drink;
end;
$function$;

create or replace function public.shift_report(p_shift uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare
  v_s public.shifts; v_cash numeric; v_wallet numeric; v_visa numeric;
  v_cancel int; v_cups int; v_items jsonb; v_disc numeric; v_refund numeric;
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  select * into v_s from public.shifts where id = p_shift;
  if not found then raise exception 'shift not found'; end if;

  select coalesce(sum(total) filter (where payment_method = 'cash' and payment_status = 'paid' and status <> 'cancelled'), 0),
         coalesce(sum(total) filter (where payment_method = 'wallet' and payment_status = 'paid' and status <> 'cancelled'), 0),
         coalesce(sum(total) filter (where payment_method = 'visa' and payment_status = 'paid' and status <> 'cancelled'), 0),
         count(*) filter (where status = 'cancelled'),
         coalesce(sum(discount) filter (where status <> 'cancelled'), 0),
         coalesce(sum(total) filter (where status = 'cancelled' and payment_status = 'refunded'), 0)
    into v_cash, v_wallet, v_visa, v_cancel, v_disc, v_refund
    from public.orders where shift_id = p_shift;

  select coalesce(sum(i.qty), 0) into v_cups
    from public.order_items i join public.orders o on o.id = i.order_id
    where o.shift_id = p_shift and o.status <> 'cancelled';

  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'cups', t.cups) order by t.cups desc), '[]'::jsonb)
    into v_items
    from (select d.name, sum(i.qty)::int as cups
      from public.order_items i
      join public.orders o on o.id = i.order_id
      join public.drinks d on d.id = i.drink_id
      where o.shift_id = p_shift and o.status <> 'cancelled'
      group by d.name) t;

  return jsonb_build_object(
    'opening_cash', v_s.opening_cash, 'cash_sales', v_cash, 'wallet_sales', v_wallet,
    'visa_sales', v_visa, 'expected_cash', v_s.opening_cash + v_cash,
    'cups', v_cups, 'cancelled', v_cancel, 'discounts', v_disc, 'refunds', v_refund,
    'by_drink', v_items);
end;
$function$;

create or replace function public.owner_report(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare r jsonb;
begin
  if not public.is_supervisor() then raise exception 'not allowed'; end if;
  with o as (
    select * from public.orders
    where status = 'delivered'
      and (created_at at time zone 'Africa/Cairo')::date between p_from and p_to
  ),
  e as (select coalesce(sum(amount), 0) s from public.expenses where day between p_from and p_to),
  b as (
    select coalesce(sum(case when kind = 'penalty' then -amount else amount end), 0) s
    from public.staff_bonuses
    where (created_at at time zone 'Africa/Cairo')::date between p_from and p_to
  )
  select jsonb_build_object(
    'sales', coalesce((select sum(total) from o), 0),
    'orders', (select count(*) from o),
    'cash', coalesce((select sum(total) from o where payment_method = 'cash'), 0),
    'visa', coalesce((select sum(total) from o where payment_method = 'visa'), 0),
    'wallet', coalesce((select sum(total) from o where payment_method = 'wallet'), 0),
    'discounts', coalesce((select sum(discount) from o), 0),
    'cancelled', (select count(*) from public.orders where status = 'cancelled'
        and (created_at at time zone 'Africa/Cairo')::date between p_from and p_to),
    'expenses', (select s from e),
    'bonuses', (select s from b),
    'net', coalesce((select sum(total) from o), 0) - (select s from e) - (select s from b),
    'pending_transfers', (select count(*) from public.orders where status = 'pending_payment'),
    'by_day', coalesce((select jsonb_agg(x order by x.day) from (
        select (created_at at time zone 'Africa/Cairo')::date as day, count(*) n, sum(total) total
        from o group by 1) x), '[]'::jsonb),
    'top_items', coalesce((select jsonb_agg(x) from (
        select d.name, sum(oi.qty) qty, sum(oi.unit_price * oi.qty) revenue
        from public.order_items oi join o on o.id = oi.order_id join public.drinks d on d.id = oi.drink_id
        group by d.name order by sum(oi.qty) desc limit 8) x), '[]'::jsonb),
    'by_staff', coalesce((select jsonb_agg(x) from (
        select p.full_name name, p.employee_no, count(*) n, sum(o.total) total
        from o left join public.shifts s on s.id = o.shift_id
        join public.profiles p on p.id = coalesce(o.seller_id, s.cashier_id)
        group by p.full_name, p.employee_no order by sum(o.total) desc) x), '[]'::jsonb),
    'low_stock', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'left', stock_qty))
        from public.drinks where active and stock_qty is not null and stock_qty <= 5), '[]'::jsonb)
  ) into r;
  return r;
end;
$function$;

create or replace function public.owner_customers()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if not public.is_supervisor() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(x order by x.spent desc) from (
    select p.full_name as name, count(o.id) filter (where o.status = 'delivered') as orders,
           coalesce(sum(o.total) filter (where o.status = 'delivered'), 0) as spent,
           max(o.created_at) as last_order
    from public.profiles p join public.orders o on o.customer_id = p.id
    where p.role = 'customer' group by p.id, p.full_name
    order by 3 desc limit 200) x), '[]'::jsonb);
end;
$function$;
