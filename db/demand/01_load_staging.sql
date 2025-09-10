-- 01_load_staging.sql
-- Purpose: clear staging, import CSVs (via UI), then normalize & quick-audit.

-- A) Clear staging (safe to re-run)
truncate table staging.demand_events_source;

-- ── Now IMPORT your CSVs ──────────────────────────────────────────────
-- In Supabase: Table Editor → staging.demand_events_source → Import.
-- Import each hotel CSV (append). Your headers should include at least:
--   hotel_code,event_name,start_date,end_date,timing,priority,
--   fnb_adjust_type,fnb_adjust_value,hall_adjust_type,hall_adjust_value,
--   allow_bot_discount,is_blackout,notes
-- Dates must be YYYY-MM-DD; booleans map to true/false or 1/0/yes/no.
-- ─────────────────────────────────────────────────────────────────────

-- B) Normalize light text/flags after import
update staging.demand_events_source
set
  event_name        = nullif(trim(event_name), ''),
  timing            = upper(trim(coalesce(timing,''))),
  notes             = nullif(trim(notes), ''),
  fnb_adjust_type   = nullif(upper(trim(fnb_adjust_type)), ''),
  hall_adjust_type  = nullif(upper(trim(hall_adjust_type)), '')
;

-- (Optional) enforce priority bounds 0–10 without failing the load
update staging.demand_events_source
set priority = case
  when priority is null then null
  when priority < 0 then 0
  when priority > 10 then 10
  else priority
end;

-- C) Quick audit: row counts & date span by hotel
select
  hotel_code,
  count(*)               as rows_loaded,
  min(start_date)        as min_start_date,
  max(end_date)          as max_end_date,
  sum(case when start_date > end_date then 1 else 0 end) as bad_ranges
from staging.demand_events_source
group by hotel_code
order by hotel_code;

-- D) Sanity: show any rows with bad date ranges (should be zero)
select *
from staging.demand_events_source
where start_date > end_date
order by hotel_code, start_date;
