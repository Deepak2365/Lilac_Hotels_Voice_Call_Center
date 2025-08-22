/* Lilac NRM Loaders & Validations

Usage
- NOT a migration. Paste snippets into Supabase SQL Editor or save as a "Saved Query".
- If using psql: uncomment the \copy lines and run locally.
- If using Supabase Studio: use Table Editor → Import for CSVs; validations can be run here.

Import order (CSV -> tables)
-- \copy dishes_master      FROM 'csv/dishes_master.csv'      WITH CSV HEADER;
-- \copy menu_catalog       FROM 'csv/menu_catalog.csv'       WITH CSV HEADER;
-- \copy package_constructs FROM 'csv/package_constructs.csv' WITH CSV HEADER;
-- \copy menu_items         FROM 'csv/menu_items.csv'         WITH CSV HEADER;

----------------------------------------------------------------
-- VALIDATIONS
----------------------------------------------------------------

-- 1) Temple towns must be veg-only (no non-veg counts)
select city, outlet, meal_period, package, category, nonveg_count
from package_constructs
where city in ('Kumbakonam','Guruvayur') and nonveg_count > 0;

-- 2) BreakfastMeeting: Eggs allowed only in Bengaluru halls
select pc.city, pc.outlet, pc.package, pc.category
from package_constructs pc
where pc.meal_period = 'BreakfastMeeting'
  and pc.category = 'Eggs'
  and pc.city <> 'Bengaluru';

-- 3) Every construct category must exist in menu_catalog for the same hall & period
select pc.city, pc.outlet, pc.meal_period, pc.category
from package_constructs pc
left join menu_catalog mc
  on mc.hotel_code like '%' || pc.city || '%'
 and mc.outlet     = pc.outlet
 and mc.meal_period= pc.meal_period
 and mc.category   = pc.category
where mc.category is null;

-- 4) Dishes referenced by menu_items must exist in dishes_master
select mi.*
from menu_items mi
left join dishes_master d on d.dish_id = mi.dish_id
where d.dish_id is null;

-- 5) Category coverage per (period, package) — quick count
select meal_period, package, count(*) as categories
from package_constructs
group by 1,2
order by 1,2;

-- 6) Spot check: sample pool per hall/period/category
--    Replace values in WHERE as needed.
select hotel_code, outlet, meal_period, category, dish_id, veg_or_nonveg
from menu_items
where outlet = 'Lotus' and meal_period = 'Evening' and category = 'Appetizers';

