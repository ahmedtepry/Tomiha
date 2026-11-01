-- Nasya: signup helpers and server-side order logic.
-- Customers can no longer insert orders directly; prices are computed on the server.

-- New users get a customer profile and a confirmed email (no email round trip).
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)));
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.auto_confirm_user() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  return new;
end;
$$;
revoke execute on function public.auto_confirm_user() from public, anon, authenticated;
create trigger auto_confirm_before_insert before insert on auth.users
  for each row execute function public.auto_confirm_user();

-- Customers create orders only through place_order(); direct inserts are staff-only or closed.
alter policy "orders customer insert" on public.orders with check ((select public.is_staff()));
alter policy "items insert" on public.order_items with check (false);
alter policy "item addons insert" on public.order_item_addons with check (false);

-- place_order: items = [{drink_id, size, sugar, qty, addon_ids: [uuid]}]
create function public.place_order(
  p_items jsonb, p_payment text default 'cash', p_eta int default null, p_source text default 'app'
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_order uuid;
  v_item jsonb;
  v_item_id uuid;
  v_price numeric;
  v_aprice numeric;
  v_addon uuid;
  v_qty int;
  v_total numeric := 0;
  v_shift uuid;
  v_status text;
  v_pstatus text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_payment not in ('cash', 'wallet') then raise exception 'bad payment'; end if;
  if p_source not in ('app', 'pos') then raise exception 'bad source'; end if;
  if p_source = 'pos' and not public.is_staff() then raise exception 'staff only'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'empty order';
  end if;
  if jsonb_array_length(p_items) > 20 then raise exception 'too many items'; end if;

  if p_source = 'pos' then
    select id into v_shift from public.shifts
      where cashier_id = v_uid and closed_at is null order by opened_at desc limit 1;
    if v_shift is null then raise exception 'no open shift'; end if;
    v_status := 'delivered';
    v_pstatus := 'paid';
  else
    v_status := 'received';
    v_pstatus := 'unpaid';
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
      insert into public.order_item_addons (order_item_id, addon_id, price)
      values (v_item_id, v_addon, v_aprice);
      v_total := v_total + v_aprice * v_qty;
    end loop;
  end loop;

  update public.orders set total = v_total where id = v_order;
  return v_order;
end;
$$;

create function public.set_order_status(p_order uuid, p_status text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_shift uuid;
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  if p_status not in ('received', 'preparing', 'ready', 'delivered', 'cancelled') then
    raise exception 'bad status';
  end if;
  perform 1 from public.orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;

  if p_status = 'delivered' then
    select id into v_shift from public.shifts
      where cashier_id = (select auth.uid()) and closed_at is null order by opened_at desc limit 1;
    update public.orders
      set status = p_status, updated_at = now(),
          payment_status = case when payment_method = 'cash' then 'paid' else payment_status end,
          shift_id = coalesce(shift_id, v_shift)
      where id = p_order;
  else
    update public.orders set status = p_status, updated_at = now() where id = p_order;
  end if;
end;
$$;

create function public.set_order_paid(p_order uuid) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  update public.orders set payment_status = 'paid', updated_at = now() where id = p_order;
end;
$$;

create function public.shift_report(p_shift uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_s public.shifts;
  v_cash numeric;
  v_wallet numeric;
  v_cancel int;
  v_cups int;
  v_items jsonb;
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  select * into v_s from public.shifts where id = p_shift;
  if not found then raise exception 'shift not found'; end if;

  select coalesce(sum(total) filter (where payment_method = 'cash' and payment_status = 'paid'), 0),
         coalesce(sum(total) filter (where payment_method = 'wallet' and payment_status = 'paid'), 0),
         count(*) filter (where status = 'cancelled')
    into v_cash, v_wallet, v_cancel
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
    'expected_cash', v_s.opening_cash + v_cash, 'cups', v_cups, 'cancelled', v_cancel,
    'by_drink', v_items);
end;
$$;

create function public.close_shift(p_shift uuid, p_actual numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_r jsonb;
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  if not exists (select 1 from public.shifts where id = p_shift and closed_at is null) then
    raise exception 'shift not open';
  end if;
  v_r := public.shift_report(p_shift);
  update public.shifts
    set closed_at = now(), actual_cash = p_actual,
        expected_cash = (v_r ->> 'expected_cash')::numeric, note = p_note
    where id = p_shift;
  return v_r || jsonb_build_object('actual_cash', p_actual,
                                   'difference', p_actual - (v_r ->> 'expected_cash')::numeric);
end;
$$;

revoke execute on function public.place_order(jsonb, text, int, text) from public, anon;
revoke execute on function public.set_order_status(uuid, text) from public, anon;
revoke execute on function public.set_order_paid(uuid) from public, anon;
revoke execute on function public.shift_report(uuid) from public, anon;
revoke execute on function public.close_shift(uuid, numeric, text) from public, anon;
grant execute on function public.place_order(jsonb, text, int, text) to authenticated;
grant execute on function public.set_order_status(uuid, text) to authenticated;
grant execute on function public.set_order_paid(uuid) to authenticated;
grant execute on function public.shift_report(uuid) to authenticated;
grant execute on function public.close_shift(uuid, numeric, text) to authenticated;
