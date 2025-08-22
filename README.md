NRM Menus – How to run:

# Lilac Hotels — Voice Call Center (NRM Menus)

Back-end data model and configs for **Monika** (AI Voice Agent) to manage **Non-Residential Meetings** across Lilac Hotels.

## Repo Layout


.
├─ db/
│ ├─ schema.sql # Postgres DDL (tables)
│ └─ loaders/
│ └─ loaders.sql # import snippets + validation queries (not a migration)
├─ configs/
│ └─ menus/
│ └─ package_rules.json # rules for counts per package/category
└─ README.md


## 1) Create Tables (once)
Run `db/schema.sql` in Supabase **SQL Editor** (or via psql).

Tables created:
- `dishes_master` — canonical dishes with grammage & calories
- `menu_catalog` — per-hall ordering of categories per meal period
- `package_constructs` — required counts per (city, hall, meal_period, package, category)
- `menu_items` — availability pool per hall/period/category (what can be picked)

**Meal periods:** `DayDelegate`, `Evening`, `BreakfastMeeting`  
**Packages:** `Silver`, `Gold`, `Platinum`

## 2) Load Seed Data (CSV)
Load the four CSVs in this order:

1. `dishes_master.csv`
2. `menu_catalog.csv`
3. `package_constructs.csv`
4. `menu_items.csv`

> Supabase Studio → Table Editor → *Import data* (UTF-8), or use psql `\copy` (see `db/loaders/loaders.sql`).

## 3) Save Validations (optional but recommended)
Open **db/loaders/loaders.sql** → paste into Supabase **SQL Editor** → **Save** as “NRM Loaders & Validations”.  
Run its checks anytime after imports.

### Key validations
- Temple towns are **veg-only**:
  ```sql
  select city, outlet, meal_period, package, category, nonveg_count
  from package_constructs
  where city in ('Kumbakonam','Guruvayur') and nonveg_count > 0;


BreakfastMeeting Eggs only in Bengaluru:

select pc.city, pc.outlet, pc.package, pc.category
from package_constructs pc
where pc.meal_period = 'BreakfastMeeting'
  and pc.category = 'Eggs'
  and pc.city <> 'Bengaluru';


Every construct category exists in the catalog for the same hall/period:

select pc.city, pc.outlet, pc.meal_period, pc.category
from package_constructs pc
left join menu_catalog mc
  on mc.hotel_code like '%' || pc.city || '%'
 and mc.outlet = pc.outlet
 and mc.meal_period = pc.meal_period
 and mc.category = pc.category
where mc.category is null;


All menu_items refer to known dishes:

select mi.* from menu_items mi
left join dishes_master d on d.dish_id = mi.dish_id
where d.dish_id is null;

4) package_rules.json (control plane)

Purpose: Validation/auto-composition for Monika and n8n flows.
Key: rules["<city>:<hall>:<meal_period>"][<package>][<category>] → { veg, nonveg, total }.

Storage options

Supabase Storage (recommended at runtime):

Bucket: configs (private) → path: menus/package_rules.json

Example (Node/TS):

const { data } = await supabase
  .storage
  .from('configs')
  .download('menus/package_rules.json');

const rules = JSON.parse(await data.text());


GitHub: keep canonical copy for PR reviews (this repo under configs/menus/).

Invariants

Temple towns (Kumbakonam, Guruvayur) are veg-only (counts and pools enforce this).

BreakfastMeeting (Bengaluru only): Eggs is present and counts as non-veg; temple towns exclude Eggs.

Breads may use total=1 with veg=0 & nonveg=0 = “Assorted basket”.

Versioning

package_rules.json includes a metadata block:

{
  "metadata": {
    "rules_version": "3.0.0",
    "schema_version": "1.0.0",
    "generated_at": "YYYY-MM-DDTHH:mm:ssZ",
    "notes": ["Temple-town veg-only; Eggs excluded in temple towns for BreakfastMeeting"]
  }
}


Bump rules_version for any change to counts/categories.

Bump schema_version only if the JSON shape changes.

5) How Monika uses the data (NRM scope)

Caller selects hotel/hall/date/meal_period/package.

Backend fetches rule block for city:hall:period + package.

Query menu_items pool for that hall/period/category; pick veg & nonveg counts to compose a suggested menu.

Confirm with caller → issue quote/hold → send email/SMS via n8n.

6) Troubleshooting

Import errors: Ensure CSVs are UTF-8. If using psql \copy, run from a path where files exist.

Missing categories: Run validation #3; fix menu_catalog.csv or package_constructs.csv.

Temple-town non-veg showing up: Check both package_constructs counts and menu_items availability for that hall.
