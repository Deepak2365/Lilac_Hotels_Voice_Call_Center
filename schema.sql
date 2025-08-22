
create table if not exists dishes_master (
  dish_id text primary key,
  dish_name text not null,
  category text not null,
  subcategory text,
  cuisine text,
  veg_flag boolean not null default true,
  contains_egg boolean not null default false,
  contains_allergens boolean not null default false,
  allergens text,
  grammage_g integer,
  calories_kcal integer,
  description text,
  active boolean not null default true
);
create table if not exists menu_catalog (
  hotel_code text not null,
  city text not null,
  outlet text not null,
  meal_period text not null,
  category text not null,
  display_order int not null,
  notes text,
  primary key (hotel_code, outlet, meal_period, category)
);
create table if not exists package_constructs (
  city text not null,
  outlet text not null,
  meal_period text not null,
  package text not null,
  category text not null,
  veg_count int not null default 0,
  nonveg_count int not null default 0,
  total_required int not null,
  notes text,
  primary key (city, outlet, meal_period, package, category)
);
create table if not exists menu_items (
  hotel_code text not null,
  outlet text not null,
  meal_period text not null,
  category text not null,
  dish_id text not null references dishes_master(dish_id),
  veg_or_nonveg text check (veg_or_nonveg in ('Veg','Non-Veg')),
  is_available boolean not null default true,
  primary key (hotel_code, outlet, meal_period, category, dish_id)
);
