-- Owner-managed menu categories (replaces the fixed list).
create table if not exists public.menu_categories (
  id text primary key,
  name text not null,
  icon text not null default 'restaurant',
  sort_order int not null default 0,
  active boolean not null default true
);
alter table public.menu_categories enable row level security;
create policy "categories readable" on public.menu_categories for select using (true);
create policy "categories owner write" on public.menu_categories for all
  using ((select public.is_manager())) with check ((select public.is_manager()));

insert into public.menu_categories (id, name, icon, sort_order) values
  ('hot', 'مشروبات ساخنة', 'coffee', 1), ('cold', 'مشروبات باردة', 'drink', 2),
  ('chocolate', 'كورنر الشوكولاتة', 'icecream', 3), ('snacks', 'سناكس', 'cookie', 4),
  ('crackers', 'مقرمشات', 'bakery', 5), ('sandwiches', 'سندوتشات', 'lunch', 6)
on conflict (id) do nothing;

alter table public.drinks drop constraint if exists drinks_category_check;
