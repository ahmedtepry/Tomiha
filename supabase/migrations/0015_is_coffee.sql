-- Coffee products get the coffee sugar levels (سادة / على الريحة / مظبوط / زيادة);
-- every other drink uses بسيط / مظبوط / زيادة.
alter table public.drinks add column if not exists is_coffee boolean not null default false;
update public.drinks set is_coffee = true
  where name ~ '(قهوة|نسكافيه|نسكافية|كابتشينو|لاتيه|إسبريسو|اسبريسو|كوفي|موكا)';
