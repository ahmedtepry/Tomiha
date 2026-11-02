-- Menu categories and starter products (prices are estimates; edit from drink_prices).
alter table public.drinks
  add column category text not null default 'hot'
  check (category in ('snacks', 'crackers', 'hot', 'cold', 'sandwiches', 'chocolate'));

update public.drinks set category = 'chocolate' where name like '%شوكولات%';

insert into public.drinks (name, base_cost, sort_order, category) values
  ('إسبريسو', 8, 7, 'hot'), ('قهوة فرنساوي', 9, 8, 'hot'), ('شاي بالنعناع', 3, 9, 'hot'),
  ('ينسون', 2.5, 10, 'hot'), ('سحلب', 10, 11, 'hot'),
  ('آيس كوفي', 9, 20, 'cold'), ('آيس لاتيه', 12, 21, 'cold'), ('آيس موكا', 14, 22, 'cold'),
  ('ليمون بالنعناع', 6, 23, 'cold'), ('موهيتو', 9, 24, 'cold'), ('شاي مثلج', 5, 25, 'cold'),
  ('بطاطس مقرمشة', 8, 30, 'snacks'), ('فشار بالكراميل', 8, 31, 'snacks'),
  ('مكسرات مشكلة', 14, 32, 'snacks'), ('كيك شوكولاتة', 12, 33, 'snacks'),
  ('كوكيز', 10, 34, 'snacks'), ('دونتس', 12, 35, 'snacks'), ('براوني', 14, 36, 'snacks'),
  ('بسكويت سادة', 3, 40, 'crackers'), ('بسكويت بالشوكولاتة', 6, 41, 'crackers'),
  ('ويفر', 4, 42, 'crackers'), ('كراكرز بالجبنة', 5, 43, 'crackers'),
  ('بقسماط', 4, 44, 'crackers'), ('شيبس ملح', 7, 45, 'crackers'),
  ('سندوتش جبنة', 16, 50, 'sandwiches'), ('سندوتش تونة', 24, 51, 'sandwiches'),
  ('سندوتش فراخ', 26, 52, 'sandwiches'), ('سندوتش جبنة رومي', 22, 53, 'sandwiches'),
  ('سندوتش حلاوة', 9, 54, 'sandwiches'), ('ميني برجر', 28, 55, 'sandwiches'),
  ('شوكولاتة ساخنة', 12, 60, 'chocolate'), ('شوكولاتة باردة', 13, 61, 'chocolate'),
  ('فوندو شوكولاتة', 20, 62, 'chocolate'), ('ميلك شيك شوكولاتة', 16, 63, 'chocolate'),
  ('فراولة بالشوكولاتة', 18, 64, 'chocolate'), ('موز بالشوكولاتة', 14, 65, 'chocolate'),
  ('وافل بالشوكولاتة', 22, 66, 'chocolate'), ('كريب نوتيلا', 22, 67, 'chocolate');

insert into public.drink_prices (drink_id, size, price)
select d.id, v.size, v.price
from public.drinks d
join (values
  ('إسبريسو', 'small', 35), ('إسبريسو', 'medium', 42), ('إسبريسو', 'large', 50),
  ('قهوة فرنساوي', 'small', 40), ('قهوة فرنساوي', 'medium', 50), ('قهوة فرنساوي', 'large', 60),
  ('شاي بالنعناع', 'small', 20), ('شاي بالنعناع', 'medium', 25), ('شاي بالنعناع', 'large', 30),
  ('ينسون', 'small', 18), ('ينسون', 'medium', 22), ('ينسون', 'large', 26),
  ('سحلب', 'small', 40), ('سحلب', 'medium', 50), ('سحلب', 'large', 60),
  ('آيس كوفي', 'small', 55), ('آيس كوفي', 'medium', 66), ('آيس كوفي', 'large', 78),
  ('آيس لاتيه', 'small', 60), ('آيس لاتيه', 'medium', 72), ('آيس لاتيه', 'large', 85),
  ('آيس موكا', 'small', 65), ('آيس موكا', 'medium', 78), ('آيس موكا', 'large', 90),
  ('ليمون بالنعناع', 'small', 35), ('ليمون بالنعناع', 'medium', 45), ('ليمون بالنعناع', 'large', 55),
  ('موهيتو', 'small', 45), ('موهيتو', 'medium', 55), ('موهيتو', 'large', 65),
  ('شاي مثلج', 'small', 30), ('شاي مثلج', 'medium', 38), ('شاي مثلج', 'large', 46),
  ('بطاطس مقرمشة', 'medium', 20), ('فشار بالكراميل', 'medium', 25),
  ('مكسرات مشكلة', 'medium', 35), ('كيك شوكولاتة', 'medium', 30),
  ('كوكيز', 'medium', 25), ('دونتس', 'medium', 30), ('براوني', 'medium', 35),
  ('بسكويت سادة', 'medium', 8), ('بسكويت بالشوكولاتة', 'medium', 12),
  ('ويفر', 'medium', 10), ('كراكرز بالجبنة', 'medium', 12),
  ('بقسماط', 'medium', 10), ('شيبس ملح', 'medium', 15),
  ('شوكولاتة ساخنة', 'small', 35), ('شوكولاتة ساخنة', 'medium', 45), ('شوكولاتة ساخنة', 'large', 55),
  ('شوكولاتة باردة', 'small', 40), ('شوكولاتة باردة', 'medium', 50), ('شوكولاتة باردة', 'large', 60),
  ('فوندو شوكولاتة', 'medium', 60), ('ميلك شيك شوكولاتة', 'medium', 55),
  ('فراولة بالشوكولاتة', 'medium', 50), ('موز بالشوكولاتة', 'medium', 40),
  ('وافل بالشوكولاتة', 'medium', 60), ('كريب نوتيلا', 'medium', 60),
  ('سندوتش جبنة', 'medium', 30), ('سندوتش تونة', 'medium', 40),
  ('سندوتش فراخ', 'medium', 45), ('سندوتش جبنة رومي', 'medium', 38),
  ('سندوتش حلاوة', 'medium', 20), ('ميني برجر', 'medium', 50)
) as v(name, size, price) on v.name = d.name;
