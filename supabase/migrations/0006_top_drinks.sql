create or replace function public.top_drinks(p_limit int default 8)
returns table(drink_id uuid)
language sql stable security definer set search_path = public as $$
  select oi.drink_id
  from public.order_items oi
  join public.drinks d on d.id = oi.drink_id and d.active
  group by oi.drink_id
  order by sum(oi.qty) desc
  limit p_limit
$$;
grant execute on function public.top_drinks(int) to anon, authenticated;
