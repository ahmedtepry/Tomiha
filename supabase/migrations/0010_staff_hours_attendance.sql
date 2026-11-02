-- Store hours (owner controlled), staff roles, employee numbers, attendance, bonuses.
alter table public.profiles
  add column staff_role text check (staff_role in ('seller', 'barista', 'delivery', 'reception')),
  add column employee_no text unique,
  add column shift_start time,
  add column active boolean not null default true;

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.profiles (id),
  day date not null,
  scheduled_start time,
  checked_in_at timestamptz not null default now(),
  checked_out_at timestamptz,
  delta_minutes int not null default 0, -- positive = late, negative = early
  unique (staff_id, day)
);

create table public.staff_bonuses (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.profiles (id),
  amount numeric(10, 2) not null,
  kind text not null check (kind in ('early', 'commission', 'tip', 'manual', 'penalty')),
  note text,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

alter table public.attendance enable row level security;
alter table public.staff_bonuses enable row level security;
create policy "attendance own or manager" on public.attendance for select to authenticated
  using (staff_id = (select auth.uid()) or (select public.is_manager()));
create policy "attendance manager write" on public.attendance for all to authenticated
  using ((select public.is_manager())) with check ((select public.is_manager()));
create policy "bonuses own or manager" on public.staff_bonuses for select to authenticated
  using (staff_id = (select auth.uid()) or (select public.is_manager()));
create policy "bonuses manager write" on public.staff_bonuses for all to authenticated
  using ((select public.is_manager())) with check ((select public.is_manager()));

insert into public.app_settings (key, value) values
  ('hours', jsonb_build_object('open_min', 570, 'close_min', 1440, 'enforce', true, 'force_closed', false)),
  ('incentives', jsonb_build_object('enabled', true, 'early_bonus_min', 10, 'early_bonus_max', 20, 'early_threshold_min', 5))
on conflict (key) do nothing;

-- Open or closed right now (Cairo time). Minutes since midnight; close 1440 = midnight.
create function public.store_status() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v jsonb := coalesce((select value from public.app_settings where key = 'hours'), '{}'::jsonb);
  o int := coalesce((v ->> 'open_min')::int, 570);
  c int := coalesce((v ->> 'close_min')::int, 1440);
  n timestamp := now() at time zone 'Africa/Cairo';
  m int := extract(hour from n)::int * 60 + extract(minute from n)::int;
  is_open boolean;
begin
  if coalesce((v ->> 'force_closed')::boolean, false) then
    is_open := false;
  elsif not coalesce((v ->> 'enforce')::boolean, true) then
    is_open := true;
  elsif o < c then
    is_open := m >= o and m < c;
  else
    is_open := m >= o or m < c;
  end if;
  return jsonb_build_object('open', is_open, 'open_min', o, 'close_min', c,
    'force_closed', coalesce((v ->> 'force_closed')::boolean, false));
end;
$$;
grant execute on function public.store_status() to anon, authenticated;

create function public.my_staff_role() returns text
language sql stable security definer set search_path = ''
as $$
  select case when role = 'manager' then 'manager' else coalesce(staff_role, 'any') end
  from public.profiles where id = (select auth.uid())
$$;
grant execute on function public.my_staff_role() to authenticated;

-- Owner turns an account into an employee: role, shift start, random 2-digit number.
create function public.owner_set_staff(p_user uuid, p_staff_role text, p_shift_start time)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_no text;
  v_try int := 0;
begin
  if not public.is_manager() then raise exception 'not allowed'; end if;
  if p_staff_role not in ('seller', 'barista', 'delivery', 'reception') then
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
        staff_role = p_staff_role, shift_start = p_shift_start,
        employee_no = v_no, active = true
    where id = p_user;
  return v_no;
end;
$$;
revoke execute on function public.owner_set_staff(uuid, text, time) from public, anon;
grant execute on function public.owner_set_staff(uuid, text, time) to authenticated;

-- Employee opens the day: records arrival and a random early bonus when due.
create function public.staff_check_in() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_p public.profiles;
  v_now timestamp := now() at time zone 'Africa/Cairo';
  v_day date := (now() at time zone 'Africa/Cairo')::date;
  v_delta int := 0;
  v_row public.attendance;
  v_inc jsonb := coalesce((select value from public.app_settings where key = 'incentives'), '{}'::jsonb);
  v_bonus numeric := 0;
  v_min int := coalesce((v_inc ->> 'early_bonus_min')::int, 10);
  v_max int := coalesce((v_inc ->> 'early_bonus_max')::int, 20);
  v_th int := coalesce((v_inc ->> 'early_threshold_min')::int, 5);
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  select * into v_p from public.profiles where id = v_uid;
  if v_p.role = 'manager' then
    return jsonb_build_object('skipped', true, 'name', v_p.full_name);
  end if;
  select * into v_row from public.attendance where staff_id = v_uid and day = v_day;
  if found then
    return jsonb_build_object('already', true, 'name', v_p.full_name, 'employee_no', v_p.employee_no,
      'delta_minutes', v_row.delta_minutes, 'bonus', 0);
  end if;
  if v_p.shift_start is not null then
    v_delta := round(extract(epoch from (v_now::time - v_p.shift_start)) / 60)::int;
    if v_delta > 720 then v_delta := v_delta - 1440; end if;
    if v_delta < -720 then v_delta := v_delta + 1440; end if;
  end if;
  insert into public.attendance (staff_id, day, scheduled_start, delta_minutes)
    values (v_uid, v_day, v_p.shift_start, v_delta);
  if coalesce((v_inc ->> 'enabled')::boolean, true) and v_delta <= -v_th and v_max >= v_min then
    v_bonus := v_min + floor(random() * (v_max - v_min + 1));
    insert into public.staff_bonuses (staff_id, amount, kind, note)
      values (v_uid, v_bonus, 'early', 'حضور مبكر');
  end if;
  return jsonb_build_object('name', v_p.full_name, 'employee_no', v_p.employee_no,
    'delta_minutes', v_delta, 'bonus', v_bonus);
end;
$$;
revoke execute on function public.staff_check_in() from public, anon;
grant execute on function public.staff_check_in() to authenticated;

-- Order steps are limited by job: reception confirms and cancels, barista prepares,
-- delivery ships, seller can do preparation and hand-over. Accounts without a job keep full access.
create or replace function public.set_order_status(p_order uuid, p_status text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_shift uuid;
  v_r text := public.my_staff_role();
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  if p_status not in ('received', 'preparing', 'ready', 'on_the_way', 'delivered', 'cancelled') then
    raise exception 'bad status';
  end if;
  if not (
    v_r in ('manager', 'any')
    or (v_r = 'reception' and p_status in ('received', 'cancelled'))
    or (v_r = 'barista' and p_status in ('preparing', 'ready'))
    or (v_r = 'delivery' and p_status in ('on_the_way', 'delivered'))
    or (v_r = 'seller' and p_status in ('preparing', 'ready', 'delivered'))
  ) then
    raise exception 'not allowed';
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

create or replace function public.confirm_order_payment(p_order uuid) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  if public.my_staff_role() not in ('manager', 'any', 'reception', 'seller') then
    raise exception 'not allowed';
  end if;
  update public.orders
    set status = 'received', payment_status = 'paid', updated_at = now()
    where id = p_order and status = 'pending_payment';
  if not found then raise exception 'order is not waiting for payment'; end if;
end;
$$;

create or replace function public.place_order_v3(
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
  if not coalesce((public.store_status() ->> 'open')::boolean, true) then
    raise exception 'store_closed';
  end if;
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
