-- Owner dashboard: expenses, gear (custody), gapless invoice numbers, commissions,
-- employee accounts created by the owner, reports, product management by the owner only.

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  day date not null default ((now() at time zone 'Africa/Cairo')::date),
  category text not null default 'other',
  title text not null,
  amount numeric(10, 2) not null check (amount > 0),
  paid_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create table public.gear (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.profiles (id),
  item text not null,
  qty int not null default 1 check (qty > 0),
  given_at timestamptz not null default now(),
  returned_at timestamptz,
  note text
);
create table public.counters (name text primary key, value bigint not null);
insert into public.counters values ('invoice', 0);

alter table public.expenses enable row level security;
alter table public.gear enable row level security;
alter table public.counters enable row level security;
create policy "expenses manager" on public.expenses for all to authenticated
  using ((select public.is_manager())) with check ((select public.is_manager()));
create policy "gear manager" on public.gear for all to authenticated
  using ((select public.is_manager())) with check ((select public.is_manager()));
create policy "gear own read" on public.gear for select to authenticated
  using (staff_id = (select auth.uid()));

-- Products are managed by the owner only.
drop policy "menu staff write" on public.drinks;
drop policy "prices staff write" on public.drink_prices;
create policy "menu manager write" on public.drinks for all to authenticated
  using ((select public.is_manager())) with check ((select public.is_manager()));
create policy "prices manager write" on public.drink_prices for all to authenticated
  using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists "addons staff write" on public.addons;
create policy "addons manager write" on public.addons for all to authenticated
  using ((select public.is_manager())) with check ((select public.is_manager()));

-- Invoice numbers: sequential, no gaps, no repeats (assigned when an order is delivered).
alter table public.orders add column invoice_no bigint unique;
create function public.orders_assign_invoice() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v bigint;
begin
  if new.status = 'delivered' and new.invoice_no is null then
    update public.counters set value = value + 1 where name = 'invoice' returning value into v;
    new.invoice_no := v;
  end if;
  return new;
end;
$$;
create trigger orders_invoice before insert or update of status on public.orders
  for each row execute function public.orders_assign_invoice();
with n as (
  select id, row_number() over (order by created_at) rn from public.orders where status = 'delivered'
)
update public.orders o set invoice_no = n.rn from n where o.id = n.id;
update public.counters set value = (select coalesce(max(invoice_no), 0) from public.orders) where name = 'invoice';

-- Commissions (owner sets the rates; zero until set).
insert into public.app_settings (key, value)
values ('commission', jsonb_build_object('seller_pct', 0, 'delivery_flat', 0))
on conflict (key) do nothing;

create function public.orders_commission() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  c jsonb := coalesce((select value from public.app_settings where key = 'commission'), '{}'::jsonb);
  pct numeric := coalesce((c ->> 'seller_pct')::numeric, 0);
  flat numeric := coalesce((c ->> 'delivery_flat')::numeric, 0);
  uid uuid := (select auth.uid());
  r text;
  amt numeric := 0;
begin
  if uid is null then return null; end if;
  select staff_role into r from public.profiles where id = uid;
  if new.source = 'pos' and new.status = 'delivered' and old.total = 0 and new.total > 0 and pct > 0 then
    amt := round(new.total * pct / 100, 2);
  elsif new.source = 'app' and new.status = 'delivered' and old.status <> 'delivered'
        and r = 'delivery' and flat > 0 then
    amt := flat;
  end if;
  if amt > 0 then
    insert into public.staff_bonuses (staff_id, amount, kind, note)
      values (uid, amt, 'commission', 'عمولة أوردر #' || new.order_no);
  end if;
  return null;
end;
$$;
create trigger orders_commission_trg after update on public.orders
  for each row execute function public.orders_commission();

-- Owner creates an employee login (username + password) with job, start time and number.
create function public.owner_create_staff(
  p_username text, p_password text, p_name text, p_staff_role text, p_shift_start time
) returns text
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := gen_random_uuid();
  v_email text := lower(trim(p_username)) || '@bonnaya.app';
begin
  if not public.is_manager() then raise exception 'not allowed'; end if;
  if lower(trim(p_username)) !~ '^[a-z0-9_]{3,20}$' then raise exception 'bad username'; end if;
  if length(p_password) < 6 then raise exception 'password should be at least 6'; end if;
  if exists (select 1 from auth.users where email = v_email) then raise exception 'username taken'; end if;
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', trim(p_name)), now(), now(), '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text,
    jsonb_build_object('sub', uid::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now());
  return public.owner_set_staff(uid, p_staff_role, p_shift_start);
end;
$$;
revoke execute on function public.owner_create_staff(text, text, text, text, time) from public, anon;
grant execute on function public.owner_create_staff(text, text, text, text, time) to authenticated;

create function public.owner_set_active(p_user uuid, p_active boolean) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_manager() then raise exception 'not allowed'; end if;
  update public.profiles set active = p_active where id = p_user and role <> 'manager';
end;
$$;
revoke execute on function public.owner_set_active(uuid, boolean) from public, anon;
grant execute on function public.owner_set_active(uuid, boolean) to authenticated;

-- Reports for a range of Cairo days.
create function public.owner_report(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  r jsonb;
begin
  if not public.is_manager() then raise exception 'not allowed'; end if;
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
    'wallet', coalesce((select sum(total) from o where payment_method = 'wallet'), 0),
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
        from o join public.shifts s on s.id = o.shift_id join public.profiles p on p.id = s.cashier_id
        group by p.full_name, p.employee_no order by sum(o.total) desc) x), '[]'::jsonb)
  ) into r;
  return r;
end;
$$;
revoke execute on function public.owner_report(date, date) from public, anon;
grant execute on function public.owner_report(date, date) to authenticated;
