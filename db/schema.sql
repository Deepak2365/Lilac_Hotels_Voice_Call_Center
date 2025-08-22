/* Lilac Hotels — Non-Residential Meetings (NRM) Data Schema

Tables:
  1) dishes_master      — Canonical dish catalog with grammage and calories.
  2) menu_catalog       — Per hotel hall ("outlet") ordering of categories per meal period.
  3) package_constructs — Required counts per (city, hall, meal_period, package, category).
  4) menu_items         — Availability map: which dishes can be used per hall/period/category.

Contract & invariants:
  - meal_period ∈ {'DayDelegate','Evening','BreakfastMeeting'}
  - package ∈ {'Silver','Gold','Platinum'}
  - outlet == Hall name from hotel seeding (e.g., Lotus, Jasmine).
  - temple-town rule (Kumbakonam, Guruvayur): nonveg_count = 0 in package_constructs;
    menu_items entries marked 'Non-Veg' are omitted; Eggs excluded from BreakfastMeeting.
  - 'Breads' may have total_required > 0 with veg_count = nonveg_count = 0 (assorted basket).
  - dish_id is globally unique across all hotels.
  - Categories in package_constructs MUST exist in menu_catalog for the same (hall, period).

Change policy:
  - Non-breaking: add dishes; adjust counts upward; reorder categories.
  - Breaking: rename categories; add/remove meal periods/packages; change key fields.
    → requires migration notes in PR and minor/major version bump (see README).

Versioning:
  - See configs/menus/package_rules.json metadata for rules version alignment.
*/


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
