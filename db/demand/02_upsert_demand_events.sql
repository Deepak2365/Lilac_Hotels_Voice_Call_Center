-- Normalize the staging payload, map hotel, derive event_code & demand_tier, then UPSERT.

with src as (
  select
    nullif(trim(hotel_name),'')  as hotel_name,
    nullif(trim(hotel_code),'')  as hotel_code,
    nullif(trim(event_name),'')  as event_name,
    nullif(trim(event_code),'')  as event_code_raw,
    start_date::date,
    end_date::date,
    nullif(trim(timing),'')      as timing,
    nullif(trim(priority),'')    as priority_raw,
    upper(nullif(trim(fnb_adjust_type),''))  as fnb_adjust_type,
    fnb_adjust_value,
    upper(nullif(trim(hall_adjust_type),'')) as hall_adjust_type,
    hall_adjust_value,
    coalesce(allow_bot_discount,false) as allow_bot_discount,
    coalesce(is_blackout,false)        as is_blackout,
    notes
  from staging.demand_events_source
),
with_code as (
  select
    *,
    coalesce(
      event_code_raw,
      regexp_replace(lower(event_name),'[^a-z0-9]+','-','g')
    ) as event_code
  from src
),
joined as (
  select
    h.id as hotel_id,
    w.*
  from with_code w
  join hotels h
    on (w.hotel_code is not null and h.code = w.hotel_code)
    or (w.hotel_code is null and w.hotel_name is not null and h.name = w.hotel_name)
),
parsed as (
  select
    *,
    nullif(regexp_replace(coalesce(priority_raw,''),'[^0-9]','','g'),'')::int as priority_num
  from joined
),
mapped as (
  select
    hotel_id, event_code, event_name,
    start_date, end_date, timing,
    priority_num, priority_raw,
    fnb_adjust_type, fnb_adjust_value,
    hall_adjust_type, hall_adjust_value,
    allow_bot_discount, is_blackout, notes,
    case
      when is_blackout then 'HIGH'::demand_tier
      when coalesce(lower(priority_raw),'') similar to '%(high|peak|wedding)%' then 'HIGH'::demand_tier
      when coalesce(priority_num,0) >= 8 then 'HIGH'::demand_tier
      when coalesce(priority_num,0) between 5 and 7 then 'NORMAL'::demand_tier
      else 'LOW'::demand_tier
    end as demand_tier
  from parsed
)
insert into demand_events as de (
  hotel_id, event_code, event_name, start_date, end_date, timing,
  priority, priority_raw,
  fnb_adjust_type, fnb_adjust_value,
  hall_adjust_type, hall_adjust_value,
  allow_bot_discount, is_blackout, demand_tier, notes
)
select
  hotel_id, event_code, event_name, start_date, end_date, timing,
  priority_num, priority_raw,
  fnb_adjust_type, fnb_adjust_value,
  hall_adjust_type, hall_adjust_value,
  allow_bot_discount, is_blackout, demand_tier, notes
from mapped
on conflict (hotel_id, event_code) do update
set event_name        = excluded.event_name,
    start_date        = excluded.start_date,
    end_date          = excluded.end_date,
    timing            = excluded.timing,
    priority          = excluded.priority,
    priority_raw      = excluded.priority_raw,
    fnb_adjust_type   = excluded.fnb_adjust_type,
    fnb_adjust_value  = excluded.fnb_adjust_value,
    hall_adjust_type  = excluded.hall_adjust_type,
    hall_adjust_value = excluded.hall_adjust_value,
    allow_bot_discount= excluded.allow_bot_discount,
    is_blackout       = excluded.is_blackout,
    demand_tier       = excluded.demand_tier,
    notes             = excluded.notes,
    updated_at        = now();
