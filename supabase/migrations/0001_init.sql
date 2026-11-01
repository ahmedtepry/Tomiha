-- Nasya: initial schema (menu, orders, shifts) with row level security.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  role text not null default 'customer' check (role in ('customer', 'cashier', 'manager')),
  created_at timestamptz not null default now()
);

create table public.drinks (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  base_cost numeric(10, 2) not null default 0,
  active boolean not null default true,
  sort_order int not null default 0
);

create table public.drink_prices (
  drink_id uuid not null references public.drinks (id) on delete cascade,
  size text not null check (size in ('small', 'medium', 'large')),
  price numeric(10, 2) not null check (price >= 0),
  primary key (drink_id, size)
);

create table public.addons (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  kind text not null check (kind in ('biscuit', 'chocolate', 'sandwich')),
  price numeric(10, 2) not null check (price >= 0),
  cost numeric(10, 2) not null default 0,
  active boolean not null default true
);

create table public.shifts (
  id uuid primary key default gen_random_uuid(),
  cashier_id uuid not null references public.profiles (id),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  opening_cash numeric(10, 2) not null default 0,
  expected_cash numeric(10, 2),
  actual_cash numeric(10, 2),
  note text
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_no bigint generated always as identity,
  customer_id uuid references public.profiles (id),
  shift_id uuid references public.shifts (id),
  source text not null default 'app' check (source in ('app', 'pos')),
  status text not null default 'received'
    check (status in ('received', 'preparing', 'ready', 'delivered', 'cancelled')),
  payment_method text not null default 'cash' check (payment_method in ('cash', 'wallet')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'paid', 'refunded')),
  eta_minutes int check (eta_minutes between 0 and 120),
  total numeric(10, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  drink_id uuid not null references public.drinks (id),
  size text not null check (size in ('small', 'medium', 'large')),
  sugar text not null default 'normal' check (sugar in ('none', 'light', 'normal', 'extra')),
  qty int not null default 1 check (qty > 0),
  unit_price numeric(10, 2) not null check (unit_price >= 0)
);

create table public.order_item_addons (
  order_item_id uuid not null references public.order_items (id) on delete cascade,
  addon_id uuid not null references public.addons (id),
  price numeric(10, 2) not null check (price >= 0),
  primary key (order_item_id, addon_id)
);

create index orders_customer_idx on public.orders (customer_id, created_at desc);
create index orders_status_idx on public.orders (status, created_at desc);
create index order_items_order_idx on public.order_items (order_id);
create index shifts_cashier_idx on public.shifts (cashier_id, opened_at desc);

-- Staff check used by policies. Not callable by anonymous users.
create function public.is_staff() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role in ('cashier', 'manager')
  );
$$;
revoke execute on function public.is_staff() from public, anon;
grant execute on function public.is_staff() to authenticated;

alter table public.profiles enable row level security;
alter table public.drinks enable row level security;
alter table public.drink_prices enable row level security;
alter table public.addons enable row level security;
alter table public.shifts enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_item_addons enable row level security;

-- Menu: everyone reads, staff manage.
create policy "menu readable" on public.drinks for select using (true);
create policy "menu staff write" on public.drinks for all to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));
create policy "prices readable" on public.drink_prices for select using (true);
create policy "prices staff write" on public.drink_prices for all to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));
create policy "addons readable" on public.addons for select using (true);
create policy "addons staff write" on public.addons for all to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));

-- Profiles: own row, staff see all.
create policy "profile own read" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_staff()));
create policy "profile own insert" on public.profiles for insert to authenticated
  with check (id = (select auth.uid()) and role = 'customer');
create policy "profile own update" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()) and role = 'customer');

-- Shifts: staff only.
create policy "shifts staff all" on public.shifts for all to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));

-- Orders: customers see and create their own app orders, staff see and manage all.
create policy "orders customer read" on public.orders for select to authenticated
  using (customer_id = (select auth.uid()) or (select public.is_staff()));
create policy "orders customer insert" on public.orders for insert to authenticated
  with check (
    (customer_id = (select auth.uid()) and source = 'app' and status = 'received')
    or (select public.is_staff())
  );
create policy "orders staff update" on public.orders for update to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));

create policy "items read" on public.order_items for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and (o.customer_id = (select auth.uid()) or (select public.is_staff()))
  ));
create policy "items insert" on public.order_items for insert to authenticated
  with check (exists (
    select 1 from public.orders o
    where o.id = order_id and (o.customer_id = (select auth.uid()) or (select public.is_staff()))
  ));

create policy "item addons read" on public.order_item_addons for select to authenticated
  using (exists (
    select 1 from public.order_items i join public.orders o on o.id = i.order_id
    where i.id = order_item_id and (o.customer_id = (select auth.uid()) or (select public.is_staff()))
  ));
create policy "item addons insert" on public.order_item_addons for insert to authenticated
  with check (exists (
    select 1 from public.order_items i join public.orders o on o.id = i.order_id
    where i.id = order_item_id and (o.customer_id = (select auth.uid()) or (select public.is_staff()))
  ));

-- Live updates for the cashier screen and the customer's tracking screen.
alter publication supabase_realtime add table public.orders;

-- Starter menu (estimates, edit from the manager dashboard).
insert into public.drinks (name, base_cost, sort_order) values
  ('قهوة تركي', 6, 1), ('نسكافيه', 7, 2), ('شاي', 2.5, 3),
  ('كابتشينو', 13, 4), ('لاتيه', 15, 5), ('هوت شوكولاتة', 14, 6);

insert into public.drink_prices (drink_id, size, price)
select d.id, v.size, v.price
from public.drinks d
join (values
  ('قهوة تركي', 'small', 30), ('قهوة تركي', 'medium', 38), ('قهوة تركي', 'large', 46),
  ('نسكافيه', 'small', 35), ('نسكافيه', 'medium', 44), ('نسكافيه', 'large', 52),
  ('شاي', 'small', 20), ('شاي', 'medium', 25), ('شاي', 'large', 30),
  ('كابتشينو', 'small', 50), ('كابتشينو', 'medium', 62), ('كابتشينو', 'large', 74),
  ('لاتيه', 'small', 55), ('لاتيه', 'medium', 68), ('لاتيه', 'large', 80),
  ('هوت شوكولاتة', 'small', 45), ('هوت شوكولاتة', 'medium', 56), ('هوت شوكولاتة', 'large', 68)
) as v(name, size, price) on v.name = d.name;

insert into public.addons (name, kind, price, cost) values
  ('بسكويت', 'biscuit', 8, 4),
  ('بسكويت سيكولاتة', 'biscuit', 12, 6),
  ('شوكولاتة', 'chocolate', 10, 5),
  ('سندوتش جبنة', 'sandwich', 30, 16),
  ('سندوتش تونة', 'sandwich', 40, 24);
