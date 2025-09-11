# Lilac Hotels — NRM Backend & Voice Agent (Monika)

This README is the single source of truth for configuring **Non‑Residential Meetings (NRM)** across the Lilac Hotels stack (Supabase + Retell + n8n) so that the voice agent **Monika** can quote availability, construct menus, apply demand‑tier SLAs, and send holds & confirmations.

> **You can commit this file now.** All scripts referenced below are safe to run multiple times in Supabase.

---

## 0) Repository layout (convention)

```
repo-root/
├─ db/
│  ├─ schema.sql                      # base schema you imported to Supabase
│  ├─ loaders/
│  │  └─ loaders.sql                  # generic loaders you keep in the repo
│  └─ demand/                         # demand events + calendar pipeline
│     ├─ 00_init_demand_events.sql
│     ├─ 01_load_staging.sql
│     ├─ 02_upsert_demand_events.sql
│     ├─ 03_refresh_demand_calendar.sql
│     └─ 04_audit.sql
├─ data/
│  └─ demand/
│     ├─ BLR3_demand_events_2025_2026.csv
│     ├─ BLR5_demand_events_2025_2026.csv
│     ├─ GUR_demand_events_2025_2026.csv
│     └─ KUM_demand_events_2025_2026.csv
└─ README.md (this file)
```

> If your repo already has other folders/files (e.g., prior README sections, SLA templates, hotel menus), keep them. The **db/demand/** folder is additive.

---

## 1) Supabase storage (control‑plane files)

* **Bucket:** `configs`

  * **Path:** `menus/package_rules.json`
    Control plane for NRM menu rules (counts per category, min/max live stations by meal period, priorities, guardrails, etc.). A copy may also live in the repo for versioning.
* **Bucket:** `hotel_menus`
  Four folders: `BLR3/`, `BLR5/`, `GUR/`, `KUM/`. Each hotel owns its CSVs/JSON (e.g., `menu_items.csv`, `menu_catalog.csv`, `dishes_master.csv`).

> Monika reads policy from **package\_rules.json**, then combines with hotel‑specific catalogs to propose menus.

---

## 2) High‑level data model (NRM)

**Core:**

* `hotels` (id **bigint** PK, `code` = BLR3/BLR5/GUR/KUM, `name`, `city`, …)
* `halls` (capacity, seating styles, hotel\_id FK)
* `menu_catalog`, `menu_items`, `dishes_master` (menu constructs & item pools per hotel/meal period)

**Demand & SLA (this README):**

* `demand_events` — hotel‑scoped event ranges with tier (HIGH/NORMAL/LOW), blackout & pricing flags
* `demand_calendar_by_hotel` — **one row per (hotel × date)** materialized from events

> The voice flow always **resolves by hotel first** (via `hotel_id`), then checks availability, then composes menus within the active policy (demand tier + SLA window).

---

## 3) Saved Queries in Supabase (names & order)

Create these six saved queries under **SQL Editor**:

1. **Demand / 00 – Create staging table**
   Creates `staging.demand_events_source` (matches your CSV headers).
2. **Demand / 01 – Truncate staging** *(optional)*
   Clears staging before each import.
3. **Demand / 10 – One‑time: Canonical tables (types + events + calendar)**
   Creates enums & canonical tables (`demand_events`, `demand_calendar_by_hotel`). Safe to re‑run.
4. **Demand / 20 – Upsert from staging → demand\_events**
   Maps `hotel_code → hotel_id`, derives `demand_tier`, upserts events.
5. **Demand / 30 – Rebuild demand\_calendar\_by\_hotel**
   Expands event ranges into per‑day rows with blackout/discount/adjust flags.
6. **Demand / 40 – Quick audits**
   Read‑only health checks across events & calendar.

> These names align with the SQL files you keep in `db/demand/`.

---

## 4) Demand Events Import Checklist (NRM)

**CSV file format** (one per hotel, multi‑year OK):

```csv
hotel_code,hotel_name,event_name,start_date,end_date,timing,priority,fnb_adjust_type,fnb_adjust_value,hall_adjust_type,hall_adjust_value,allow_bot_discount,is_blackout,notes
```

**Rules:**

* `hotel_code` **required**: one of **BLR3, BLR5, GUR, KUM**. `hotel_name` is optional.
* Dates: **YYYY‑MM‑DD**.
* `priority` numeric **1–10** (10 highest). Tier mapping:
  **≥8 → HIGH**, **5–7 → NORMAL**, **≤4 → LOW**.
  Words **HIGH/PEAK/WEDDING** anywhere in *priority/timing/event\_name* also force **HIGH**.
* Booleans: `true/false` (also accepts 1/0, yes/no).
* Adjust types: `ABS` (absolute) or `PCT` (percent). Leave blank to skip.
* **Do not include `hotel_id`** in CSVs; it’s resolved at import.

**Run sequence (every time):**

1. (Optional) **Demand / 01 – Truncate staging**
2. **Import CSVs** → Table Editor → `staging.demand_events_source` (Append mode; all 4 hotels)
3. **Demand / 20 – Upsert from staging → demand\_events**
4. **Demand / 30 – Rebuild demand\_calendar\_by\_hotel**
5. **Demand / 40 – Quick audits** (fix & repeat as needed)

**What gets created/updated:**

* `demand_events` — canonical, hotel‑scoped policy rows (ranges & flags)
* `demand_calendar_by_hotel` — daily materialization (tier, blackout, discount, adjust fields, source codes)

**Common pitfalls & fixes:**

* Bad dates → ensure ISO; re‑import and re‑run *20 → 30*.
* Unknown `hotel_code` → must be exactly **BLR3/BLR5/GUR/KUM**.
* Invalid adjust types → only **ABS/PCT**.
* Blackout days allowing discounts → set `allow_bot_discount=false` on the event and rebuild.
* Missing days vs horizon → re‑run **30 – Rebuild calendar**; check **B5** in audits.

---

## 5) How Monika uses this data (NRM slice)

1. **Identify property** → resolve `hotel_id` from the call context or caller choice.
2. **Capacity filter** → match halls by seating style & pax; if none, offer alternate dates/hotels.
3. **Demand tier** → `get_demand_tier(hotel_code, event_date)` via the calendar (HIGH/NORMAL/LOW).
4. **SLA window** → compute days‑to‑event and pick the correct bucket (e.g., `D_90_119`, `D_2_TRANSFER`).
5. **Policy fetch** → pull hold/extension/approval timers using *(hotel\_code, demand\_tier, window\_code)*.
6. **Menu compose** → apply `package_rules.json` + hotel menu pools to generate A/B/C options or a chef preset.
7. **Hold & follow‑ups** → place a timed hold, send email with menus, trigger SLA timers and escalations as configured.

---

## 6) Commit messages (suggested)

* `feat(demand): init hotel‑scoped demand events schema`
  *(for 00\_init)*
* `chore(demand): load per‑hotel CSVs into staging`
  *(for 01\_load\_staging)*
* `feat(demand): upsert from staging to canonical and derive demand_tier`
  *(for 02\_upsert\_demand\_events)*
* `feat(demand): regenerate demand_calendar (blackouts & discounts)`
  *(for 03\_refresh\_demand\_calendar)*
* `feat(demand): add comprehensive audits for demand events & calendar`
  *(for 04\_audit)*

Include a brief extended description (bullets) per commit describing what the script creates/updates and any assumptions.

---

## 7) Troubleshooting

* **Dates look garbled** in Excel: ensure UTF‑8 CSV and use ASCII hyphens ("-") in labels; avoid smart dashes.
* **Nothing appears in calendar** after rebuild: verify events loaded (step 20), check audit **B5** for missing days.
* **Wrong tier** on a specific day: inspect that day’s source via `source_codes` in `demand_calendar_by_hotel`, then adjust the event or priority and rebuild.
* **Blackout but discount still applied**: audit **B4**; set `allow_bot_discount=false` on the event and rebuild.

---

## 8) Appendix — Field reference (events)

* `event_name` — human label (e.g., "Wedding Saya W2")
* `timing` — optional tag (e.g., BREAKFAST/DAY/EVENING or free text)
* `priority` — 1..10 (10 = highest). Tier bands: ≥8 HIGH, 5–7 NORMAL, ≤4 LOW.
  Keywords HIGH/PEAK/WEDDING in *priority/timing/event\_name* → force HIGH.
* `is_blackout` — hard block for new holds (still recorded in calendar)
* `allow_bot_discount` — if false, bot will not apply discount logic on those days
* `fnb_adjust_type/value` — ABS or PCT adjustments applied to F\&B pricing/quotes
* `hall_adjust_type/value` — ABS or PCT adjustments applied to hall pricing

---

## 9) Ops runbook (quick)

1. Edit hotel CSV(s) in `data/demand/` (multi‑year OK).
2. **01 – Truncate staging** (optional) → Import CSVs → **20 – Upsert** → **30 – Rebuild calendar**.
3. **40 – Audits** → resolve any critical findings (A1/A2/A6/B2/B4/B5) → re‑run 20/30.
4. Proceed to Retell/n8n tests for NRM booking flows.

---

**Owner:** You (project lead).
**Last consolidated:** *keep this line when you update the README next.* 11-09-2025
