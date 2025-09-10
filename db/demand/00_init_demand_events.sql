-- TYPES -----------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'demand_tier') then
    create type demand_tier as enum ('LOW','NORMAL','HIGH');
  end if;
end $$;

-- TABLES ----------------------------------------------------------------------
create table if not exists demand_events (
  id                bigserial primary key,
  hotel_id          bigint not null references hotels(id),
  event_code        text   not null,      -- stable key per event per hotel
  event_name        text   not null,
  start_date        date   not null,
  end_date          date   not null,
  timing            text,
  priority          int,                  -- numeric 1..10 after parsing
  priority_raw      text,                 -- original text (e.g. "Peak", "9")
  fnb_adjust_type   text check (fnb_adjust_type in ('ABS','PCT') or fnb_adjust_type is null),
  fnb_adjust_value  numeric,
  hall_adjust_type  text check (hall_adjust_type in ('ABS','PCT') or hall_adjust_type is null),
  hall_adjust_value numeric,
  allow_bot_discount boolean default false,
  is_blackout        boolean default false,
  demand_tier        demand_tier not null default 'LOW',
  notes              text,
  created_at         timestamptz default now(),
  updated_at         timestamptz default now()
);

create unique index if not exists ux_demand_events_hotel_event
  on demand_events(hotel_id, event_code);

create or replace function set_demand_events_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_demand_events_updated_at on demand_events;
create trigger trg_demand_events_updated_at
before update on demand_events
for each row execute function set_demand_events_updated_at();

create table if not exists demand_calendar_by_hotel (
  hotel_id           bigint not null references hotels(id),
  event_date         date   not null,
  demand_tier        demand_tier not null,
  is_blackout        boolean default false,
  fnb_adjust_type    text,
  fnb_adjust_value   numeric,
  hall_adjust_type   text,
  hall_adjust_value  numeric,
  allow_bot_discount boolean default false,
  source_codes       text[],
  primary key (hotel_id, event_date)
);

-- STAGING ---------------------------------------------------------------------
create schema if not exists staging;

create table if not exists staging.demand_events_source (
  hotel_name        text,
  hotel_code        text,
  event_name        text,
  event_code        text,
  event_type        text,
  start_date        date,
  end_date          date,
  timing            text,
  priority          text,     -- keep as text in staging; we parse later
  fnb_adjust_type   text,
  fnb_adjust_value  numeric,
  hall_adjust_type  text,
  hall_adjust_value numeric,
  allow_bot_discount boolean,
  is_blackout        boolean,
  notes              text
);
