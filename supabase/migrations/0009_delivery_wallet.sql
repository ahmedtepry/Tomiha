-- App orders: delivery address, wallet-only payment confirmed by the cashier.
alter table public.orders
  add column address_text text,
  add column lat double precision,
  add column lng double precision,
  add column maps_url text,
  add column pay_ref text;

alter table public.orders drop constraint orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in ('pending_payment', 'received', 'preparing', 'ready', 'on_the_way', 'delivered', 'cancelled'));

alter table public.profiles add column default_address jsonb;

create or replace function public.set_order_status(p_order uuid, p_status text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_shift uuid;
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  if p_status not in ('received', 'preparing', 'ready', 'on_the_way', 'delivered', 'cancelled') then
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

-- Cashier saw the transfer: the order is confirmed and paid.
create function public.confirm_order_payment(p_order uuid) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  update public.orders
    set status = 'received', payment_status = 'paid', updated_at = now()
    where id = p_order and status = 'pending_payment';
  if not found then raise exception 'order is not waiting for payment'; end if;
end;
$$;
revoke execute on function public.confirm_order_payment(uuid) from public, anon;
grant execute on function public.confirm_order_payment(uuid) to authenticated;

create function public.place_order_v3(
  p_request_id uuid, p_items jsonb, p_address jsonb, p_pay_ref text
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
  v_text text := nullif(trim(coalesce(p_address ->> 'text', '')), '');
  v_url text := nullif(trim(coalesce(p_address ->> 'url', '')), '');
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select id into v_id from public.orders
    where customer_id = v_uid and request_id = p_request_id;
  if v_id is not null then return v_id; end if;
  if v_text is null then raise exception 'address required'; end if;
  if nullif(trim(coalesce(p_pay_ref, '')), '') is null then raise exception 'payment reference required'; end if;
  v_id := public.place_order(p_items, 'wallet', null, 'app');
  update public.orders set
    request_id = p_request_id,
    status = 'pending_payment',
    address_text = left(v_text, 300),
    lat = nullif(p_address ->> 'lat', '')::double precision,
    lng = nullif(p_address ->> 'lng', '')::double precision,
    maps_url = left(v_url, 500),
    pay_ref = left(trim(p_pay_ref), 100)
  where id = v_id;
  return v_id;
end;
$$;
revoke execute on function public.place_order_v3(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function public.place_order_v3(uuid, jsonb, jsonb, text) to authenticated;

insert into public.app_settings (key, value)
values ('payment', jsonb_build_object('wallet_number', '', 'wallet_name', ''))
on conflict (key) do nothing;
