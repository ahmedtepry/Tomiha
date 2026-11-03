-- 0016: delivery fee, coupons, loyalty points, offline POS sale, payroll, audit log, password reset.

-- ---------- settings
insert into public.app_settings (key, value) values
  ('delivery', '{"fee": 0, "min_order": 0, "free_over": 0}'::jsonb),
  ('loyalty',  '{"enabled": true, "earn_every": 10, "point_value": 0.5, "min_redeem": 20}'::jsonb)
on conflict (key) do nothing;

-- ---------- columns
alter table public.orders
  add column if not exists delivery_fee numeric not null default 0,
  add column if not exists coupon_code text,
  add column if not exists coupon_discount numeric not null default 0,
  add column if not exists points_used int not null default 0,
  add column if not exists points_discount numeric not null default 0,
  add column if not exists points_earned int not null default 0,
  add column if not exists client_ref uuid;
create unique index if not exists orders_client_ref_idx on public.orders (client_ref) where client_ref is not null;

alter table public.profiles add column if not exists base_salary numeric not null default 0;

alter table public.staff_bonuses drop constraint if exists staff_bonuses_kind_check;
alter table public.staff_bonuses add constraint staff_bonuses_kind_check
  check (kind in ('early', 'commission', 'tip', 'manual', 'penalty', 'advance'));

-- ---------- coupons / points tables
create table if not exists public.coupons (
  code text primary key,
  kind text not null check (kind in ('pct', 'fixed')),
  value numeric not null check (value > 0),
  min_order numeric not null default 0,
  max_uses int,
  used int not null default 0,
  expires_at date,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.coupons enable row level security;
create policy "coupons owner" on public.coupons for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

create table if not exists public.coupon_uses (
  code text not null,
  customer_id uuid not null,
  order_id uuid not null,
  primary key (code, customer_id)
);
alter table public.coupon_uses enable row level security;
create policy "coupon uses owner" on public.coupon_uses for select to authenticated
  using (public.is_manager());

create table if not exists public.customer_points (
  customer_id uuid primary key,
  points int not null default 0 check (points >= 0)
);
alter table public.customer_points enable row level security;
create policy "points own" on public.customer_points for select to authenticated
  using (customer_id = (select auth.uid()) or public.is_manager());

-- ---------- helpers
create or replace function public._subtotal(p_items jsonb) returns numeric
language sql stable security definer set search_path to '' as $$
  select coalesce(sum(
    (dp.price + coalesce((
        select sum(a.price) from jsonb_array_elements_text(coalesce(i -> 'addon_ids', '[]'::jsonb)) x
        join public.addons a on a.id = x::uuid and a.active), 0))
    * greatest(1, least(coalesce((i ->> 'qty')::int, 1), 20))), 0)
  from jsonb_array_elements(p_items) i
  join public.drink_prices dp on dp.drink_id = (i ->> 'drink_id')::uuid and dp.size = i ->> 'size'
  join public.drinks d on d.id = dp.drink_id and d.active;
$$;

create or replace function public._coupon_value(p_code text, p_sub numeric, p_uid uuid) returns numeric
language plpgsql stable security definer set search_path to '' as $$
declare c public.coupons; v numeric;
begin
  select * into c from public.coupons where code = upper(trim(p_code)) and active;
  if not found or (c.expires_at is not null and c.expires_at < current_date)
     or (c.max_uses is not null and c.used >= c.max_uses) then
    raise exception 'coupon invalid';
  end if;
  if p_sub < c.min_order then raise exception 'coupon min'; end if;
  if p_uid is not null and exists (select 1 from public.coupon_uses where code = c.code and customer_id = p_uid) then
    raise exception 'coupon used';
  end if;
  v := case c.kind when 'pct' then round(p_sub * c.value / 100, 2) else c.value end;
  return least(v, p_sub);
end;
$$;

create or replace function public._delivery_fee(p_sub numeric) returns numeric
language plpgsql stable security definer set search_path to '' as $$
declare d jsonb := coalesce((select value from public.app_settings where key = 'delivery'), '{}'::jsonb);
        fee numeric := coalesce((d ->> 'fee')::numeric, 0); fo numeric := coalesce((d ->> 'free_over')::numeric, 0);
begin
  if fo > 0 and p_sub >= fo then return 0; end if;
  return fee;
end;
$$;

-- live quote for the cart screen
create or replace function public.order_quote(p_items jsonb, p_coupon text default null, p_points int default 0)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_sub numeric := public._subtotal(p_items);
  d jsonb := coalesce((select value from public.app_settings where key = 'delivery'), '{}'::jsonb);
  l jsonb := coalesce((select value from public.app_settings where key = 'loyalty'), '{}'::jsonb);
  v_min numeric := coalesce((d ->> 'min_order')::numeric, 0);
  v_fee numeric := public._delivery_fee(v_sub);
  v_cd numeric := 0; v_cerr text; v_bal int := 0; v_pu int := 0; v_pd numeric := 0;
  v_pv numeric := coalesce((l ->> 'point_value')::numeric, 0.5);
begin
  if nullif(trim(coalesce(p_coupon, '')), '') is not null then
    begin v_cd := public._coupon_value(p_coupon, v_sub, v_uid);
    exception when others then v_cerr := sqlerrm; v_cd := 0; end;
  end if;
  select points into v_bal from public.customer_points where customer_id = v_uid;
  v_bal := coalesce(v_bal, 0);
  if coalesce((l ->> 'enabled')::boolean, true) and p_points > 0
     and p_points >= coalesce((l ->> 'min_redeem')::int, 0) and v_pv > 0 then
    v_pu := least(p_points, v_bal, floor((v_sub - v_cd) / v_pv)::int);
    if v_pu < 0 then v_pu := 0; end if;
    v_pd := v_pu * v_pv;
  end if;
  return jsonb_build_object('subtotal', v_sub, 'fee', v_fee, 'coupon_discount', v_cd, 'coupon_error', v_cerr,
    'points_used', v_pu, 'points_discount', v_pd, 'balance', v_bal, 'min_order', v_min,
    'point_value', v_pv, 'min_redeem', coalesce((l ->> 'min_redeem')::int, 0),
    'loyalty', coalesce((l ->> 'enabled')::boolean, true),
    'total', v_sub + v_fee - v_cd - v_pd);
end;
$$;

-- customer order with fee, coupon and points
create or replace function public.place_order_v4(p_request_id uuid, p_items jsonb, p_address jsonb, p_pay_ref text,
  p_coupon text default null, p_points int default 0)
returns uuid language plpgsql security definer set search_path to '' as $$
declare
  v_uid uuid := (select auth.uid()); v_id uuid; v_sub numeric; v_fee numeric; v_cd numeric := 0; v_code text;
  v_min numeric; l jsonb; v_pv numeric; v_pu int := 0; v_pd numeric := 0; v_bal int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select id into v_id from public.orders where customer_id = v_uid and request_id = p_request_id;
  if v_id is not null then return v_id; end if;
  v_id := public.place_order_v3(p_request_id, p_items, p_address, p_pay_ref);
  select total into v_sub from public.orders where id = v_id;
  v_min := coalesce((select (value ->> 'min_order')::numeric from public.app_settings where key = 'delivery'), 0);
  if v_sub < v_min then raise exception 'below minimum'; end if;
  v_fee := public._delivery_fee(v_sub);
  if nullif(trim(coalesce(p_coupon, '')), '') is not null then
    v_code := upper(trim(p_coupon));
    v_cd := public._coupon_value(v_code, v_sub, v_uid);
    insert into public.coupon_uses (code, customer_id, order_id) values (v_code, v_uid, v_id);
    update public.coupons set used = used + 1 where code = v_code;
  end if;
  l := coalesce((select value from public.app_settings where key = 'loyalty'), '{}'::jsonb);
  v_pv := coalesce((l ->> 'point_value')::numeric, 0.5);
  if coalesce((l ->> 'enabled')::boolean, true) and p_points > 0 and v_pv > 0
     and p_points >= coalesce((l ->> 'min_redeem')::int, 0) then
    select points into v_bal from public.customer_points where customer_id = v_uid for update;
    v_pu := least(p_points, coalesce(v_bal, 0), floor((v_sub - v_cd) / v_pv)::int);
    if v_pu > 0 then
      update public.customer_points set points = points - v_pu where customer_id = v_uid;
      v_pd := v_pu * v_pv;
    else v_pu := 0; end if;
  end if;
  update public.orders set delivery_fee = v_fee, coupon_code = v_code, coupon_discount = v_cd,
    points_used = v_pu, points_discount = v_pd, total = v_sub + v_fee - v_cd - v_pd
    where id = v_id;
  return v_id;
end;
$$;

-- earn on delivery, give back on cancel
create or replace function public.orders_loyalty() returns trigger
language plpgsql security definer set search_path to '' as $$
declare l jsonb := coalesce((select value from public.app_settings where key = 'loyalty'), '{}'::jsonb);
        v_every numeric := coalesce((l ->> 'earn_every')::numeric, 10); v_p int;
begin
  if new.status = 'delivered' and old.status <> 'delivered' and new.source = 'app'
     and new.customer_id is not null and new.points_earned = 0
     and coalesce((l ->> 'enabled')::boolean, true) and v_every > 0 then
    v_p := floor((new.total - new.delivery_fee) / v_every)::int;
    if v_p > 0 then
      insert into public.customer_points (customer_id, points) values (new.customer_id, v_p)
        on conflict (customer_id) do update set points = public.customer_points.points + v_p;
      new.points_earned := v_p;
    end if;
  end if;
  if new.status = 'cancelled' and old.status <> 'cancelled' and new.customer_id is not null then
    if new.points_used > 0 then
      insert into public.customer_points (customer_id, points) values (new.customer_id, new.points_used)
        on conflict (customer_id) do update set points = public.customer_points.points + new.points_used;
    end if;
    if new.points_earned > 0 then
      update public.customer_points set points = greatest(points - new.points_earned, 0)
        where customer_id = new.customer_id;
    end if;
    if new.coupon_code is not null then
      delete from public.coupon_uses where order_id = new.id;
      update public.coupons set used = greatest(used - 1, 0) where code = new.coupon_code;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists orders_loyalty_trg on public.orders;
create trigger orders_loyalty_trg before update of status on public.orders
  for each row execute function public.orders_loyalty();

-- ---------- offline POS sale (idempotent)
create or replace function public.pos_sale(p_ref uuid, p_items jsonb, p_payment text, p_seller uuid,
  p_discount numeric, p_reason text, p_note text, p_at timestamptz)
returns uuid language plpgsql security definer set search_path to '' as $$
declare v_id uuid;
begin
  if not public.is_staff() then raise exception 'staff only'; end if;
  select id into v_id from public.orders where client_ref = p_ref;
  if v_id is not null then return v_id; end if;
  v_id := public.place_order(p_items, p_payment, null, 'pos');
  update public.orders set client_ref = p_ref where id = v_id;
  perform public.pos_finalize(v_id, p_seller, p_discount, p_reason, p_note);
  if p_at is not null and p_at between now() - interval '3 days' and now() then
    update public.orders set created_at = p_at where id = v_id;
  end if;
  return v_id;
end;
$$;

-- ---------- payroll
create or replace function public.owner_payroll(p_month date)
returns table (staff_id uuid, full_name text, staff_role text, base_salary numeric, days int,
               bonuses numeric, penalties numeric, advances numeric)
language plpgsql stable security definer set search_path to '' as $$
declare v_from date := date_trunc('month', p_month)::date; v_to date := (date_trunc('month', p_month) + interval '1 month')::date;
begin
  if not public.is_manager() then raise exception 'not allowed'; end if;
  return query
  select p.id, p.full_name, p.staff_role, p.base_salary,
    (select count(*)::int from public.attendance a where a.staff_id = p.id and a.day >= v_from and a.day < v_to and a.checked_in_at is not null),
    coalesce((select sum(b.amount) from public.staff_bonuses b where b.staff_id = p.id and b.kind not in ('penalty', 'advance')
       and (b.created_at at time zone 'Africa/Cairo')::date >= v_from and (b.created_at at time zone 'Africa/Cairo')::date < v_to), 0),
    coalesce((select sum(b.amount) from public.staff_bonuses b where b.staff_id = p.id and b.kind = 'penalty'
       and (b.created_at at time zone 'Africa/Cairo')::date >= v_from and (b.created_at at time zone 'Africa/Cairo')::date < v_to), 0),
    coalesce((select sum(b.amount) from public.staff_bonuses b where b.staff_id = p.id and b.kind = 'advance'
       and (b.created_at at time zone 'Africa/Cairo')::date >= v_from and (b.created_at at time zone 'Africa/Cairo')::date < v_to), 0)
  from public.profiles p
  where p.staff_role is not null and coalesce(p.active, true)
  order by p.full_name;
end;
$$;

create or replace function public.owner_set_salary(p_user uuid, p_salary numeric)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not public.is_manager() then raise exception 'not allowed'; end if;
  if p_salary < 0 then raise exception 'bad amount'; end if;
  update public.profiles set base_salary = p_salary where id = p_user;
end;
$$;

-- advances count as deductions in the owner report too
do $$
declare d text;
begin
  d := pg_get_functiondef('public.owner_report(date,date)'::regprocedure);
  d := replace(d, $q$case when kind = 'penalty' then -amount else amount end$q$,
                  $q$case when kind in ('penalty', 'advance') then -amount else amount end$q$);
  execute d;
end $$;

-- ---------- owner reset of a staff password
create or replace function public.owner_reset_password(p_user uuid, p_password text)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not public.is_manager() then raise exception 'not allowed'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'password short'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
    updated_at = now() where id = p_user;
  insert into public.audit_log (actor, actor_name, table_name, action, row_id)
  values ((select auth.uid()), 'owner', 'auth', 'reset_password', p_user::text);
end;
$$;

-- ---------- audit log
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor uuid,
  actor_name text,
  table_name text not null,
  action text not null,
  row_id text,
  old jsonb,
  new jsonb
);
alter table public.audit_log enable row level security;
create policy "audit owner read" on public.audit_log for select to authenticated using (public.is_manager());
create index if not exists audit_log_at_idx on public.audit_log (at desc);

create or replace function public.audit_row() returns trigger
language plpgsql security definer set search_path to '' as $$
declare v_uid uuid := (select auth.uid()); v_id text; v_name text;
begin
  if v_uid is null then return coalesce(new, old); end if;
  select full_name into v_name from public.profiles where id = v_uid;
  v_id := coalesce((to_jsonb(coalesce(new, old)) ->> 'id'), (to_jsonb(coalesce(new, old)) ->> 'key'), (to_jsonb(coalesce(new, old)) ->> 'code'));
  insert into public.audit_log (actor, actor_name, table_name, action, row_id, old, new)
  values (v_uid, v_name, tg_table_name, lower(tg_op),  v_id,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new, old);
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['drinks', 'drink_prices', 'addons', 'menu_categories', 'app_settings', 'coupons', 'staff_bonuses', 'expenses']
  loop
    execute format('drop trigger if exists audit_trg on public.%I', t);
    execute format('create trigger audit_trg after insert or update or delete on public.%I for each row execute function public.audit_row()', t);
  end loop;
end $$;

drop trigger if exists audit_trg on public.profiles;
create trigger audit_trg after update on public.profiles for each row
  when (old.staff_role is distinct from new.staff_role or old.active is distinct from new.active
        or old.base_salary is distinct from new.base_salary or old.role is distinct from new.role
        or old.shift_start is distinct from new.shift_start)
  execute function public.audit_row();

-- ---------- grants: signed-in only
revoke execute on function public._subtotal(jsonb), public._coupon_value(text, numeric, uuid), public._delivery_fee(numeric),
  public.order_quote(jsonb, text, int), public.place_order_v4(uuid, jsonb, jsonb, text, text, int),
  public.orders_loyalty(), public.pos_sale(uuid, jsonb, text, uuid, numeric, text, text, timestamptz),
  public.owner_payroll(date), public.owner_set_salary(uuid, numeric), public.owner_reset_password(uuid, text),
  public.audit_row() from public, anon;
grant execute on function public.order_quote(jsonb, text, int), public.place_order_v4(uuid, jsonb, jsonb, text, text, int),
  public.pos_sale(uuid, jsonb, text, uuid, numeric, text, text, timestamptz),
  public.owner_payroll(date), public.owner_set_salary(uuid, numeric), public.owner_reset_password(uuid, text)
  to authenticated;
