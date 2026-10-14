-- Shervice data backfill
--
-- Assumptions:
--   * The requested year is 2026.
--   * October trips should cover 2026-10-01 through 2026-10-22.
--   * A normal day is copied from the latest September day with the same
--     weekday.  If September has no trips for a weekday, that target day is
--     skipped.
--   * Each generated date gets its own summary_id, because a trip summary is
--     date-specific in Shervice.
--   * Staff evaluations: two per driver per month, using the first and last
--     October trips for each driver.
--   * Passenger evaluations: 20 per driver for each month from January 2026
--     through October 2026.  October evaluations are dated within Oct 1-22.
--
-- Run the preview SELECT statements first if you want to inspect counts.

begin;

-- Required by the evaluation insert below.  This is safe if the migration
-- has already been applied.
alter table public.evaluation
  add column if not exists source text not null default 'staff';

-- Preview: existing trip volume by month.
select date_trunc('month', schedule_date::date)::date as month,
       count(*) as trips
from public.trip_schedule
group by 1
order by 1;

-- Preview: active driver count.
select count(*) as drivers from public.driver_profile;

-- Preview: source rows that do not have complete assignments.  These values
-- are copied as-is, so resolve any rows returned here before running the
-- insert if every generated trip must be fully assigned.
select count(*) filter (where vehicle_id is null) as missing_vehicle,
       count(*) filter (where company_id is null) as missing_company,
       count(*) filter (where driver_id is null) as missing_driver
from public.trip_schedule
where schedule_date::date between date '2026-09-01' and date '2026-09-30';

-- Stop safely instead of creating partially assigned October trips.
do $$
declare
  incomplete_rows integer;
begin
  select count(*) into incomplete_rows
  from public.trip_schedule
  where schedule_date::date between date '2026-09-01' and date '2026-09-30'
    and (vehicle_id is null or company_id is null or driver_id is null);

  if incomplete_rows > 0 then
    raise exception
      'Aborted: % September source trip(s) have a missing vehicle, company, or driver assignment.',
      incomplete_rows;
  end if;
end $$;

-- 1) Copy the latest September weekday pattern into Oct 1-22.
--    All rows for one target date share that date's summary_id.
--    trip_id is intentionally omitted so PostgreSQL generates a new identity.
insert into public.trip_schedule (
  summary_id,
  staff_id,
  company_id,
  schedule_date,
  working_day,
  bus_type,
  classification,
  vehicle_id,
  seating_capacity,
  ticket_no,
  driver_id,
  passenger_count,
  departure_time,
  estimated_arrival_time,
  utilization_rate,
  remarks,
  route_id,
  route_name
)
select
  'AUTO-' || to_char(target.target_date::date, 'YYYY-MM-DD'),
  source.staff_id,
  source.company_id,
  target.target_date::date,
  trim(to_char(target.target_date::date, 'Day')),
  source.bus_type,
  source.classification,
  source.vehicle_id,
  source.seating_capacity,
  source.ticket_no,
  source.driver_id,
  source.passenger_count,
  source.departure_time,
  source.estimated_arrival_time,
  source.utilization_rate,
  source.remarks,
  source.route_id,
  source.route_name
from generate_series(
       date '2026-10-01', date '2026-10-22', interval '1 day'
     ) as target(target_date)
cross join lateral (
  select distinct on (t.schedule_date::date)
         t.schedule_date::date as source_date
  from public.trip_schedule t
  where t.schedule_date::date between date '2026-09-01' and date '2026-09-30'
    and extract(isodow from t.schedule_date::date)
        = extract(isodow from target.target_date::date)
  order by t.schedule_date::date desc
  limit 1
) as source_day
join public.trip_schedule source
  on source.schedule_date::date = source_day.source_date
where not exists (
  select 1
  from public.trip_schedule already
  where already.schedule_date::date = target.target_date::date
    and already.driver_id is not distinct from source.driver_id
    and already.departure_time is not distinct from source.departure_time
    and already.route_name is not distinct from source.route_name
);

-- 2) Add two staff evaluations per driver for October, if they are missing.
with ranked_trips as (
  select t.*,
         row_number() over (
           partition by t.driver_id, date_trunc('month', t.schedule_date::date)
           order by t.schedule_date::date, t.departure_time nulls last, t.trip_id
         ) as first_trip,
         row_number() over (
           partition by t.driver_id, date_trunc('month', t.schedule_date::date)
           order by t.schedule_date::date desc, t.departure_time desc nulls last, t.trip_id desc
         ) as last_trip
  from public.trip_schedule t
  where t.schedule_date::date between date '2026-10-01' and date '2026-10-22'
    and t.driver_id is not null
), staff_candidates as (
  select * from ranked_trips where first_trip = 1 or last_trip = 1
)
insert into public.evaluation (
  submit_date,
  submit_time,
  punctuality_score,
  safety_score,
  professionalism_score,
  comments,
  driver_id,
  trip_id,
  vehicle_id,
  source
)
select
  c.schedule_date::date,
  case when c.first_trip = 1 then time '09:00' else time '15:00' end,
  4 + floor(random() * 2)::int,
  4 + floor(random() * 2)::int,
  4 + floor(random() * 2)::int,
  'Monthly staff evaluation for October 2026.',
  c.driver_id,
  c.trip_id,
  c.vehicle_id,
  'staff'
from staff_candidates c
where not exists (
  select 1
  from public.evaluation e
  where e.driver_id = c.driver_id
    and e.source = 'staff'
    and e.submit_date::date = c.schedule_date::date
);

-- 3) Ensure 20 passenger evaluations per driver per month from Jan 2026
--    through Oct 2026. Existing rows count toward the monthly target.
with months as (
  select month_start::date,
         least(
           (month_start + interval '1 month - 1 day')::date,
           date '2026-10-22'
         ) as month_end
  from generate_series(
         date '2026-01-01', date '2026-10-01', interval '1 month'
       ) as g(month_start)
), driver_month_counts as (
  select d.driver_id,
         m.month_start,
         m.month_end,
         count(e.evaluation_id)::int as existing_count
  from public.driver_profile d
  cross join months m
  left join public.evaluation e
    on e.driver_id = d.driver_id
   and e.source = 'passenger'
   and e.submit_date::date >= m.month_start
   and e.submit_date::date <= m.month_end
  group by d.driver_id, m.month_start, m.month_end
), missing_slots as (
  select x.*, slot_no
  from driver_month_counts x
  cross join generate_series(1, 20) as slots(slot_no)
  where slots.slot_no > x.existing_count
), dates_assigned as (
  select *,
         (month_start + ((slot_no - 1) %
           greatest(1, (month_end - month_start + 1)))::int)::date as evaluation_date
  from missing_slots
)
insert into public.evaluation (
  submit_date,
  submit_time,
  punctuality_score,
  safety_score,
  professionalism_score,
  comments,
  driver_id,
  source
)
select
  evaluation_date,
  make_time(8 + (slot_no % 9), (slot_no * 7) % 60, 0),
  4 + floor(random() * 2)::int,
  4 + floor(random() * 2)::int,
  4 + floor(random() * 2)::int,
  'Synthetic passenger evaluation for ' || to_char(month_start, 'YYYY-MM') || '.',
  driver_id,
  'passenger'
from dates_assigned;

-- 4) Add attendance in the same shape as the attendance importer.
--    One attendance row is created per driver per October trip date.
--    The source_file value makes these generated rows identifiable and the
--    NOT EXISTS check makes this section safe to rerun.
with driver_workdays as (
  select distinct
         t.driver_id,
         t.schedule_date::date as work_date
  from public.trip_schedule t
  where t.schedule_date::date between date '2026-10-01' and date '2026-10-22'
    and t.driver_id is not null
), attendance_values as (
  select
    d.driver_id,
    coalesce(p.full_name, 'Driver ' || d.driver_id::text) as employee_name,
    d.work_date,
    ((d.driver_id + extract(day from d.work_date)::int) % 16)::int as late_minutes
  from driver_workdays d
  join public.driver_profile p on p.driver_id = d.driver_id
)
insert into public.attendance_record (
  driver_id,
  employee_name,
  employee_id,
  pay_period,
  day_label,
  work_date,
  raw_date,
  time_in,
  time_out,
  work_time,
  daily_total,
  morning_in,
  morning_out,
  afternoon_in,
  afternoon_out,
  overtime_in,
  overtime_out,
  total_minutes_late,
  note,
  source_file,
  raw_payload
)
select
  a.driver_id,
  a.employee_name,
  a.driver_id::text,
  'October 2026',
  upper(trim(to_char(a.work_date, 'Day'))),
  a.work_date,
  to_char(a.work_date, 'MM/DD/YYYY'),
  to_char(time '07:00' + a.late_minutes * interval '1 minute', 'HH24:MI'),
  '17:00',
  '09:00',
  '09:00',
  to_char(time '07:00' + a.late_minutes * interval '1 minute', 'HH24:MI'),
  '12:00',
  '13:00',
  '17:00',
  null,
  null,
  a.late_minutes,
  case when a.late_minutes = 0 then 'Present' else 'Present - Late' end,
  'October 2026 Attendance.xls',
  jsonb_build_object(
    'generated', true,
    'format', 'attendance_import',
    'employee_id', a.driver_id::text,
    'work_date', to_char(a.work_date, 'MM/DD/YYYY')
  )
from attendance_values a
where not exists (
  select 1
  from public.attendance_record existing
  where existing.source_file = 'October 2026 Attendance.xls'
    and existing.employee_name = a.employee_name
    and existing.work_date = a.work_date
    and existing.time_in = to_char(
      time '07:00' + a.late_minutes * interval '1 minute', 'HH24:MI'
    )
    and existing.time_out = '17:00'
);

commit;

-- Verification.
select source,
       date_trunc('month', submit_date::date)::date as month,
       count(*) as evaluations
from public.evaluation
where submit_date::date between date '2026-01-01' and date '2026-10-22'
group by source, 2
order by 2, 1;

select date_trunc('month', schedule_date::date)::date as month,
       count(*) as trips
from public.trip_schedule
where schedule_date::date between date '2026-10-01' and date '2026-10-22'
group by 1;

select count(*) as october_attendance_rows
from public.attendance_record
where source_file = 'October 2026 Attendance.xls'
  and work_date between date '2026-10-01' and date '2026-10-22';
