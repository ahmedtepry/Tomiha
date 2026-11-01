-- Safe retries: the app sends a request id, so a retry after a dropped connection
-- returns the same order instead of creating a duplicate.
alter table public.orders add column request_id uuid;
create unique index orders_request_id_key
  on public.orders (customer_id, request_id) where request_id is not null;

create function public.place_order_v2(
  p_request_id uuid, p_items jsonb, p_payment text default 'cash',
  p_eta int default null, p_source text default 'app'
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select id into v_id from public.orders
    where customer_id = v_uid and request_id = p_request_id;
  if v_id is not null then return v_id; end if;
  v_id := public.place_order(p_items, p_payment, p_eta, p_source);
  update public.orders set request_id = p_request_id where id = v_id;
  return v_id;
end;
$$;
revoke execute on function public.place_order_v2(uuid, jsonb, text, int, text) from public, anon;
grant execute on function public.place_order_v2(uuid, jsonb, text, int, text) to authenticated;
