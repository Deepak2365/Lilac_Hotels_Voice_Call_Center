-- 04_audit.sql
-- Non-destructive audits for demand_events & demand_calendar

-- ====== Parameters (horizon you want to audit) =========================
with params as (
  select
    current_date::date                                 as today,
    (current_date + interval '730 days')::date         as horizon_end, -- ~24 months
    array['BREAKFAST','DAY','EVENING']::text[]         as allowed_timings
),

-- ====== Helpers ========================================================
cal as (
  select c.*, h.code as hotel_code, h.name as hotel_name, h.city
  from demand_calendar c
  join hotels h on h.id = c.hotel_id
  join params p on true
  where c.d between p.today and p.horizon_end
),
ev as (
  select e.*, h.code as hotel_code, h.name as hotel_name, h.city
  from demand_events e
  join hotels h on h.id = e.hotel_id
),

-- ====== A. Integrity checks on events =================================
events_bad_ranges as (
  select *
  from ev
  where start_date > end_date
),
events_missing_hotel as (
  select *
  from demand_events
  where hotel_id is null
),
events_priority_out_of_bounds as (
  select *
  from ev
  where priority is not null and (priority < 0 or priority > 10)
),
events_timing_invalid as (
  select e.*
  from ev e, params p
  where e.timing is not null
    and upper(e.timing) <> any(p.allowed_timings)
),

-- Duplicates: same hotel, name, dates, timing
events_exact_duplicates as (
  select hotel_id, event_name, start_date, end_date, coalesce(upper(timing),'') as timing_key,
         count(*) as dup_count, min(id) as sample_id
  from demand_events
  group by 1,2,3,4,5
  having count(*) > 1
),

-- Overlaps inside the same hotel (date ranges intersect)
events_overlaps as (
  select a.hotel_id, h.code as hotel_code, a.id as event_id_a, b.id as event_id_b,
         a.event_name as event_a, b.event_name as event_b,
         a.start_date as a_start, a.end_date as a_end,
         b.start_date as b_start, b.end_date as b_end
  from demand_events a
  join demand_events b
    on b.hotel_id = a.hotel_id
   and b.id <> a.id
   and daterange(a.start_date, a.end_date, '[]') && daterange(b.start_date, b.end_date, '[]')
  join hotels h on h.id = a.hotel_id
  where (a.id < b.id)  -- prevent double-listing
),

-- ====== B. Calendar sanity ============================================
-- Coverage per hotel and month by tier & blackouts
calendar_monthly as (
  select
    hotel_id, hotel_code, hotel_name, city,
    date_trunc('month', d)::date as month,
    sum(case when demand_tier = 'HIGH'   then 1 else 0 end) as days_high,
    sum(case when demand_tier = 'NORMAL' then 1 else 0 end) as days_normal,
    sum(case when demand_tier = 'LOW'    then 1 else 0 end) as days_low,
    sum(case when is_blackout then 1 else 0 end)            as days_blackout,
    count(*) as days_total
  from cal
  group by 1,2,3,4,5
),

-- Days carrying a tier/blackout but no source ids (should normally have at least one)
calendar_flagged_without_source as (
  select *
  from cal
  where (is_blackout or demand_tier <> 'LOW')
    and (source_event_ids is null or array_length(source_event_ids,1) is null)
),

-- Days with pricing adjustments (non-zero)
calendar_price_adjustments as (
  select *, 
         (coalesce(fnb_adjust_pct,0) <> 0
       or coalesce(fnb_adjust_fixed,0) <> 0
       or coalesce(hall_adjust_pct,0) <> 0
       or coalesce(hall_adjust_fixed,0) <> 0) as has_adjust
  from cal
),
calendar_adjust_summary as (
  select hotel_id, hotel_code, hotel_name, city,
         sum(case when has_adjust then 1 else 0 end) as adjusted_days,
         count(*) as total_days
  from calendar_price_adjustments
  group by 1,2,3,4
),

-- Blackouts that still allow bot discount (often unintended)
calendar_blackout_allows_discount as (
  select *
  from cal
  where is_blackout and coalesce(allow_bot_discount, true) = true
)

-- ====== Output sections ===============================================
-- A1. Events with invalid date ranges
select 'A1_events_bad_ranges' as section, *
from events_bad_ranges
order by hotel_code, start_date;

-- A2. Events missing hotel_id
select 'A2_events_missing_hotel' as section, *
from events_missing_hotel
order by id;

-- A3. Events with priority outside 0–10
select 'A3_events_priority_out_of_bounds' as section, *
from events_priority_out_of_bounds
order by hotel_code, start_date;

-- A4. Events with invalid timing values
select 'A4_events_timing_invalid' as section, *
from events_timing_invalid
order by hotel_code, start_date;

-- A5. Exact duplicate event keys
select 'A5_events_exact_duplicates' as section, d.*
from events_exact_duplicates d
order by hotel_id, event_name, start_date;

-- A6. Overlapping event date ranges within the same hotel
select 'A6_events_overlaps' as section, *
from events_overlaps
order by hotel_code, a_start, b_start;

-- B1. Calendar monthly tier/blackout distribution
select 'B1_calendar_monthly' as section, *
from calendar_monthly
order by hotel_code, month;

-- B2. Calendar days with tier/blackout but no source_event_ids
select 'B2_calendar_flagged_without_source' as section, *
from calendar_flagged_without_source
order by hotel_code, d;

-- B3. Calendar pricing adjustment coverage
select 'B3_calendar_adjust_summary' as section, *
from calendar_adjust_summary
order by hotel_code;

-- B4. Blackout days that still allow bot discount
select 'B4_calendar_blackout_allows_discount' as section, *
from calendar_blackout_allows_discount
order by hotel_code, d;

-- B5. Calendar completeness per hotel across horizon
select 'B5_calendar_completeness' as section,
       h.code as hotel_code, h.name as hotel_name, h.city,
       count(c.d)                      as days_present,
       (select (p.horizon_end - p.today + 1)::int from params p) as expected_days,
       ((select (p.horizon_end - p.today + 1)::int from params p) - count(c.d)) as missing_days
from hotels h
left join cal c on c.hotel_id = h.id
group by h.code, h.name, h.city
order by hotel_code;

