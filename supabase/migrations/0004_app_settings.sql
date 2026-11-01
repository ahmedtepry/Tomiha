-- Owner-editable app settings (welcome screen cup + quotes).
create table public.app_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;

create function public.is_manager() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'manager'
  )
$$;
revoke execute on function public.is_manager() from public, anon;
grant execute on function public.is_manager() to authenticated;

create policy "settings readable" on public.app_settings
  for select using (true);
create policy "settings manager write" on public.app_settings
  for all to authenticated
  using ((select public.is_manager())) with check ((select public.is_manager()));

insert into public.app_settings (key, value) values ('welcome', jsonb_build_object(
  'cup', 'finjan',
  'show_quote', true,
  'quotes', jsonb_build_array(
    'القهوة مش مجرد مشروب، دي لحظة هدوء في نص الزحمة.',
    'أول رشفة بتظبّط اليوم كله.',
    'يوم من غير قهوة زي حكاية من غير نهاية.',
    'الصباح الحلو بيبدأ بريحة بن.',
    'على مهلك، القهوة بتحب اللي بيستنّاها.',
    'فنجان قهوة وكلمة طيبة، والدنيا تتعدل.',
    'ريحة القهوة نص الصباح.',
    'اشرب قهوتك وانت مبسوط، طعمها بيفرق.',
    'كل فنجان بيبدأ بحكاية وبينتهي بابتسامة.',
    'مفيش حاجة تتحل أحسن من قهوة مظبوطة.'
  )
));
