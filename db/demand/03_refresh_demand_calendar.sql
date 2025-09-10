-- Expand events to per-day rows and upsert the calendar (take highest tier per day)

with expanded as (
  select
    de.hotel_id,
    (gs)::date as event_date,
    de.demand_tier,
    de.is_blackout,
    de.fnb_adjust_type, de.fnb_adjust_value,
    de.hall_adjust_type, de.hall_adjust_value,
    de.allow_bot_discount,
    de.event_code
  from demand_events de
  join lateral generate_series(de.start_date, de.end_date, interval '1 day') gs on true
),
ranked as (
  select
    hotel_id,
    event_date,
    max(case demand_tier when 'HIGH' then 3
                         when 'NORMAL' then 2
                         else 1 end) as tier_rank,
    bool_or(is_blackout) as is_blackout,
    max(fnb_adjust_value) filter (where fnb_adjust_type is not null)  as fnb_adjust_value,
    max(fnb_adjust_type)  filter (where fnb_adjust_type  is not null) as fnb_adjust_type,
    max(hall_adjust_value) filter (where hall_adjust_type is not null) as hall_adjust_value,
    max(hall_adjust_type)  filter (where hall_adjust_type  is not null) as hall_adjust_type,
    bool_or(allow_bot_discount) as allow_bot_discount,
    array_agg(event_code order by event_code) as source_codes
  from expanded
  group by hotel_id, event_date
),
normalized as (
  select
    hotel_id,
    event_date,
    case tier_rank when 3 then 'HIGH'::demand_tier
                   when 2 then 'NORMAL'::demand_tier
                   else 'LOW'::demand_tier end as demand_tier,
    is_blackout,
    fnb_adjust_type, fnb_adjust_value,
    hall_adjust_type, hall_adjust_value,
    allow_bot_discount,
    source_codes
  from ranked
)
insert into demand_calendar_by_hotel as cal (
  hotel_id, event_date, demand_tier, is_blackout,
  fnb_adjust_type, fnb_adjust_value, hall_adjust_type, hall_adjust_value,
  allow_bot_discount, source_codes
)
select
  hotel_id, event_date, demand_tier, is_blackout,
  fnb_adjust_type, fnb_adjust_value, hall_adjust_type, hall_adjust_value,
  allow_bot_discount, source_codes
from normalized
on conflict (hotel_id, event_date) do update
set demand_tier        = excluded.demand_tier,
    is_blackout        = excluded.is_blackout,
    fnb_adjust_type    = excluded.fnb_adjust_type,
    fnb_adjust_value   = excluded.fnb_adjust_value,
    hall_adjust_type   = excluded.hall_adjust_type,
    hall_adjust_value  = excluded.hall_adjust_value,
    allow_bot_discount = excluded.allow_bot_discount,
    source_codes       = excluded.source_codes;
