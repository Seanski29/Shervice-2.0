-- WARNING: This permanently removes all rows from maintenance_log.
-- It does not delete vehicles or trip records.
-- Review the generated rows before running this in production.
--
-- Synthetic design:
--   * Monthly routine inspections are resolved.
--   * Every third active month has a resolved repair event for ML history.
--   * Only the first two non-excellent vehicles have an open repair, so the dashboard has
--     realistic alerts without requiring many manual repair confirmations.

begin;

alter table public.maintenance_log
  add column if not exists maintenance_type text;

alter table public.maintenance_log
  drop constraint if exists maintenance_log_maintenance_type_check;

alter table public.maintenance_log
  add constraint maintenance_log_maintenance_type_check
  check (maintenance_type in ('maintenance', 'repair'));

alter table public.maintenance_log
  alter column maintenance_type set default 'maintenance';

truncate table public.maintenance_log restart identity;

-- Build the history from actual trip months. Vehicles without trips receive
-- no fabricated maintenance or repair records. The first available month is
-- normally January in the supplied trip history, so the generated history
-- starts in January without inventing dates before a vehicle operated.
with trip_months as (
  select
    vehicle_id,
    date_trunc('month', schedule_date::date)::date as month_start,
    min(schedule_date::date) as first_trip_date,
    max(schedule_date::date) as last_trip_date
  from public.trip_schedule
  where vehicle_id is not null
    and schedule_date is not null
  group by vehicle_id, date_trunc('month', schedule_date::date)::date
), ranked_months as (
  select
    tm.*,
    row_number() over (
      partition by vehicle_id
      order by month_start
    ) as active_month_number
  from trip_months tm
), vehicle_windows as (
  select
    vehicle_id,
    max(last_trip_date) as last_trip_date
  from ranked_months
  group by vehicle_id
), maintenance_rows as (
  select
    vehicle_id,
    first_trip_date as event_date,
    'maintenance'::text as maintenance_type,
    case ((vehicle_id + extract(month from month_start)::int) % 6)
      when 0 then 'Monthly engine inspection based on active trip operations'
      when 1 then 'Monthly exterior inspection based on active trip operations'
      when 2 then 'Monthly interior inspection based on active trip operations'
      when 3 then 'Monthly electrical inspection based on active trip operations'
      when 4 then 'Monthly tires and wheels inspection based on active trip operations'
      else 'Monthly general vehicle inspection based on active trip operations'
    end as description,
    case ((vehicle_id + extract(month from month_start)::int) % 6)
      when 0 then 'Engine'
      when 1 then 'Exterior'
      when 2 then 'Interior'
      when 3 then 'Electrical'
      when 4 then 'Tires/Wheels'
      else 'General'
    end as category,
    true as is_resolved
  from ranked_months
), repair_rows as (
  -- Create a repair event every third active trip month for the non-excellent
  -- cohort. Vehicles whose ID is divisible by 5 have no repair history and
  -- become excellent-vehicle candidates after the forecast refresh.
  select
    vehicle_id,
    first_trip_date as event_date,
    'repair'::text as maintenance_type,
    'Vehicle repair recorded after accumulated operating workload'::text as description,
    case when vehicle_id % 4 = 0 then 'Engine'
         when vehicle_id % 4 = 1 then 'Electrical'
         when vehicle_id % 4 = 2 then 'Tires/Wheels'
         else 'General' end as category,
    true as is_resolved
  from ranked_months
  where active_month_number % 3 = 0
    and vehicle_id % 5 <> 0
), open_repair_rows as (
  -- Keep only two deterministic active repair issues for the Due Repair
  -- workflow. Do not duplicate a repair already created that month.
  select
    vw.vehicle_id,
    vw.last_trip_date as event_date,
    'repair'::text as maintenance_type,
    'Open repair issue requiring staff attention'::text as description,
    case when vw.vehicle_id % 4 = 0 then 'Engine'
         when vw.vehicle_id % 4 = 1 then 'Electrical'
         when vw.vehicle_id % 4 = 2 then 'Tires/Wheels'
         else 'General' end as category,
    false as is_resolved
  from vehicle_windows vw
  where vw.vehicle_id in (
    select vehicle_id
    from vehicle_windows
    where vehicle_id % 5 <> 0
    order by vehicle_id
    limit 2
  )
    and not exists (
      select 1
      from repair_rows rr
      where rr.vehicle_id = vw.vehicle_id
        and rr.event_date = vw.last_trip_date
    )
), seed_rows as (
  select * from maintenance_rows
  union all
  select * from repair_rows
  union all
  select * from open_repair_rows
)
insert into public.maintenance_log (
  repair_date,
  description,
  vehicle_id,
  user_id,
  category,
  maintenance_type,
  incident_date,
  incident_time,
  repair_time,
  is_resolved
)
select
  case when seed.maintenance_type = 'repair' and seed.is_resolved
       then seed.event_date else null end,
  seed.description,
  seed.vehicle_id,
  (
    select user_id
    from public.user_account
    where lower(coalesce(role, '')) in ('admin', 'administrator', 'staff')
    order by user_id
    limit 1
  ),
  seed.category,
  seed.maintenance_type,
  seed.event_date,
  time '08:00:00',
  case when seed.maintenance_type = 'repair' and seed.is_resolved
       then time '16:00:00' else null end,
  seed.is_resolved
from seed_rows seed;

-- Reset stale vehicle status left by older synthetic maintenance data.
update public.vehicle
set health_status = 'Good',
    is_available = true,
    last_maintenance_description = 'Synthetic maintenance history refreshed.';

-- Only the two seeded open repairs remain unavailable.
update public.vehicle v
set health_status = 'Needs Maintenance',
    is_available = false,
    last_maintenance_description = l.description
from public.maintenance_log l
where l.vehicle_id = v.vehicle_id
  and l.maintenance_type = 'repair'
  and l.is_resolved = false;

-- Protect future inserts and make the generated data easy to inspect.
alter table public.maintenance_log
  alter column maintenance_type set not null;

create index if not exists idx_maintenance_log_type_date
  on public.maintenance_log (maintenance_type, repair_date desc);

commit;

-- Maintenance rows are monthly checks tied to actual trip activity and use
-- only the categories supported by the application. Repair rows are separate
-- fault/repair events; unresolved repairs remain visible as Due Repair.
select maintenance_type, is_resolved, count(*) as rows
from public.maintenance_log
group by maintenance_type, is_resolved
order by maintenance_type, is_resolved;

select count(*) as ongoing_repairs
from public.maintenance_log
where maintenance_type = 'repair'
  and is_resolved = false;
