-- Synthetic operations rebuild for 2026
--
-- WARNING: This permanently deletes all rows from evaluation,
-- attendance_record, and trip_schedule. Use only when those rows are demo or
-- synthetic data. Export a backup first if there is any real data.
--
-- Rebuild targets:
--   * 1,000 trips for each complete month from January through September.
--   * 700 trips for October 1 through October 22.
--   * Every generated trip has a real driver, vehicle, company, route, and
--     one of the existing staff owners.
--   * Attendance is derived from distinct generated driver/trip dates.
--   * Staff evaluations: 6 per driver per month, representing 2 evaluations
--     from each of 3 staff members. The evaluator identity is recorded in
--     comments because evaluation has no evaluator_staff_id column.
--   * Passenger evaluations: approximately 10% of each driver's trips,
--     capped at 10 per driver per month, minimum 1 when the driver has trips.

begin;

-- Delete dependent records first. passenger_evaluation is a legacy table in
-- some installations, so remove it only when it exists.
do $$
begin
  if to_regclass('public.passenger_evaluation') is not null then
    execute 'delete from public.passenger_evaluation';
  end if;
end $$;

delete from public.evaluation;
delete from public.attendance_record;
delete from public.trip_schedule;

-- Optional for this clean synthetic rebuild: restart the three generated IDs.
-- This does not reset IDs in drivers, vehicles, companies, or routes.
do $$
declare
  sequence_name text;
begin
  foreach sequence_name in array array[
    pg_get_serial_sequence('public.trip_schedule', 'trip_id'),
    pg_get_serial_sequence('public.evaluation', 'evaluation_id'),
    pg_get_serial_sequence('public.attendance_record', 'attendance_id')
  ] loop
    if sequence_name is not null then
      execute format('alter sequence %s restart with 1', sequence_name);
    end if;
  end loop;
end $$;

-- Refuse to create incomplete synthetic trips.
do $$
declare
  driver_count integer;
  vehicle_count integer;
  company_count integer;
  client_company_count integer;
  route_count integer;
  staff_count integer;
begin
  select count(*) into driver_count from public.driver_profile;
  select count(*) into vehicle_count from public.vehicle;
  select count(*) into company_count from public.client_company;
  select count(*) into client_company_count
  from public.client_company
  where company_name not ilike '%GT LANTIN%';
  select count(*) into route_count from public.destination;
  select count(*) into staff_count
  from public.user_account
  where lower(role) = 'staff' and staff_id is not null;

  if driver_count = 0 or vehicle_count = 0 or company_count = 0
     or client_company_count = 0
     or route_count = 0 or staff_count < 3 then
    raise exception
      'Aborted: requires drivers %, vehicles %, non-GT-Lantin client companies %, routes %, and at least 3 staff (found %).',
      driver_count, vehicle_count, client_company_count, route_count, staff_count;
  end if;
end $$;

-- 1) Generate the trip calendar and insert 1,000 trips per full month.
with months as (
  select
    month_start::date,
    least(
      (month_start + interval '1 month - 1 day')::date,
      date '2026-10-22'
    ) as month_end,
    case
      when month_start::date = date '2026-10-01' then 700
      else 1000
    end as target_trips
  from generate_series(
    date '2026-01-01', date '2026-10-01', interval '1 month'
  ) as g(month_start)
), workdays_base as (
  select
    m.month_start,
    m.target_trips,
    day_value::date as work_date
  from months m
  cross join lateral generate_series(
    m.month_start, m.month_end, interval '1 day'
  ) as days(day_value)
  where extract(isodow from day_value) between 1 and 5
), workdays as (
  select
    w.*,
    row_number() over (
      partition by w.month_start order by w.work_date
    )::int as day_no,
    count(*) over (partition by w.month_start)::int as day_count
  from workdays_base w
), trip_numbers as (
  select
    m.month_start,
    gs.trip_no,
    ((gs.trip_no - 1) % w.day_count) + 1 as day_no
  from months m
  join lateral (
    select count(*)::int as day_count
    from workdays x
    where x.month_start = m.month_start
  ) w on true
  cross join lateral generate_series(1, m.target_trips) as gs(trip_no)
), trip_calendar as (
  select
    n.month_start,
    n.trip_no,
    w.work_date
  from trip_numbers n
  join workdays w
    on w.month_start = n.month_start
   and w.day_no = n.day_no
), drivers as (
  select array_agg(driver_id order by driver_id) as ids,
         count(*)::int as item_count
  from public.driver_profile
), vehicles as (
  select array_agg(vehicle_id order by vehicle_id) as ids,
         count(*)::int as item_count
  from public.vehicle
), companies as (
  select array_agg(company_id order by company_id) as ids,
         count(*)::int as item_count
  from public.client_company
  where company_name not ilike '%GT LANTIN%'
), routes as (
  select array_agg(route_id order by route_id) as ids,
         array_agg(route_name order by route_id) as names,
         count(*)::int as item_count
  from public.destination
), staff as (
  select array_agg(staff_id order by staff_id) as ids,
         count(*)::int as item_count
  from public.user_account
  where lower(role) = 'staff' and staff_id is not null
)
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
  'REBUILD-' || to_char(c.work_date, 'YYYY-MM-DD'),
  s.ids[((c.trip_no - 1) % s.item_count) + 1],
  co.ids[((c.trip_no - 1) % co.item_count) + 1],
  c.work_date,
  trim(to_char(c.work_date, 'Day')),
  'Synthetic Shuttle',
  'Regular',
  v.ids[((c.trip_no - 1) % v.item_count) + 1],
  40,
  'REBUILD-' || to_char(c.work_date, 'YYYYMMDD') || '-' || lpad(c.trip_no::text, 4, '0'),
  d.ids[((c.trip_no - 1) % d.item_count) + 1],
  20 + (c.trip_no % 21),
  time '03:00' + ((c.trip_no % 12) * interval '1 hour'),
  time '07:00' + ((c.trip_no % 12) * interval '1 hour'),
  round((20 + (c.trip_no % 21))::numeric / 40, 2),
  case (c.trip_no % 5)
    when 0 then 'Trip successful.'
    when 1 then 'Trip completed on schedule.'
    when 2 then 'Trip completed with no reported issues.'
    when 3 then 'Minor traffic delay; trip completed successfully.'
    else 'Passenger service completed successfully.'
  end,
  r.ids[((c.trip_no - 1) % r.item_count) + 1],
  r.names[((c.trip_no - 1) % r.item_count) + 1]
from trip_calendar c
cross join drivers d
cross join vehicles v
cross join companies co
cross join routes r
cross join staff s;

-- 2) Attendance: exactly one row per generated driver/work date.
with driver_workdays as (
  select distinct driver_id, schedule_date::date as work_date
  from public.trip_schedule
  where summary_id like 'REBUILD-%'
), attendance_values as (
  select
    w.driver_id,
    p.full_name as employee_name,
    w.work_date,
    case
      when mod(w.driver_id, 10) in (5, 6)
        then mod(w.driver_id + extract(day from w.work_date)::int, 4)
      when mod(w.driver_id, 10) in (2, 3, 4, 9)
        then 3 + mod(w.driver_id + extract(day from w.work_date)::int, 4)
      when mod(w.driver_id, 10) in (7, 8)
        then 8 + mod(w.driver_id + extract(day from w.work_date)::int, 8)
      else 2 + mod(w.driver_id + extract(day from w.work_date)::int, 4)
    end::int as late_minutes,
    ((w.driver_id * 3 + extract(day from w.work_date)::int) % 12) = 0
      as has_overtime
  from driver_workdays w
  join public.driver_profile p on p.driver_id = w.driver_id
)
insert into public.attendance_record (
  driver_id, employee_name, employee_id, pay_period, day_label,
  work_date, raw_date, time_in, time_out, work_time, daily_total,
  morning_in, morning_out, afternoon_in, afternoon_out,
  overtime_in, overtime_out, total_minutes_late, note, source_file, raw_payload
)
select
  a.driver_id,
  a.employee_name,
  a.driver_id::text,
  '2026 Operations Rebuild',
  upper(trim(to_char(a.work_date, 'Day'))),
  a.work_date,
  to_char(a.work_date, 'MM/DD/YYYY'),
  to_char(time '03:00' + a.late_minutes * interval '1 minute', 'HH24:MI'),
  case when a.has_overtime then '21:00' else '19:00' end,
  case when a.has_overtime then '10:00' else '08:00' end,
  case when a.has_overtime then '10:00' else '08:00' end,
  to_char(time '03:00' + a.late_minutes * interval '1 minute', 'HH24:MI'),
  '07:00', '15:00', '19:00',
  case when a.has_overtime then '19:00' else null end,
  case when a.has_overtime then '21:00' else null end,
  a.late_minutes,
  case
    when a.has_overtime and a.late_minutes > 0 then 'Present - Late - Overtime'
    when a.has_overtime then 'Present - Overtime'
    when a.late_minutes > 0 then 'Present - Late'
    else 'Present'
  end,
  '2026 Operations Rebuild Attendance.xls',
  jsonb_build_object('generated', true, 'work_date', a.work_date)
from attendance_values a;

-- Rating helper: lower scores are correlated with lateness-risk driver IDs so
-- the ML features have useful variation instead of all 4s and 5s.
-- 3) Six staff evaluations per driver per month, dated on actual trip dates.
with ranked_trips as (
  select t.*,
         row_number() over (
           partition by t.driver_id, date_trunc('month', t.schedule_date::date)
           order by t.schedule_date::date, t.trip_id
         ) as driver_month_rank
  from public.trip_schedule t
  where t.summary_id like 'REBUILD-%'
), staff_rows as (
  select * from ranked_trips where driver_month_rank <= 6
)
insert into public.evaluation (
  submit_date, submit_time, punctuality_score, safety_score,
  professionalism_score, comments, driver_id, trip_id, vehicle_id, source
)
select
  s.schedule_date::date,
  time '09:00' + ((s.driver_month_rank - 1) * interval '1 hour'),
  case when s.driver_id % 10 in (0, 1) then 3
       when s.driver_id % 10 in (2, 3, 4) then 4 else 5 end,
  case when s.driver_id % 10 in (0, 1) then 3
       when s.driver_id % 10 in (2, 3, 4) then 4 else 5 end,
  case when s.driver_id % 10 in (0, 1) then 3
       when s.driver_id % 10 in (2, 3, 4) then 4 else 5 end,
  'Staff evaluation ' || (((s.driver_month_rank - 1) % 3) + 1)::text ||
    ' of 3; synthetic rebuild.',
  s.driver_id, s.trip_id, s.vehicle_id, 'staff'
from staff_rows s;

-- 4) Voluntary passenger evaluations: roughly 10% of each driver's trips,
-- capped at 10 per driver/month and never detached from a real trip.
with ranked_driver_trips as (
  select t.*,
         count(*) over (
           partition by t.driver_id, date_trunc('month', t.schedule_date::date)
         ) as driver_month_trips,
         row_number() over (
           partition by t.driver_id, date_trunc('month', t.schedule_date::date)
           order by t.schedule_date::date, t.trip_id
         ) as driver_month_rank
  from public.trip_schedule t
  where t.summary_id like 'REBUILD-%'
), passenger_rows as (
  select *
  from ranked_driver_trips
  where driver_month_rank <= greatest(
    1, least(10, ceil(driver_month_trips * 0.10)::int)
  )
)
insert into public.evaluation (
  submit_date, submit_time, punctuality_score, safety_score,
  professionalism_score, comments, driver_id, trip_id, vehicle_id, source
)
select
  p.schedule_date::date,
  time '10:00' + ((p.driver_month_rank % 8) * interval '1 hour'),
  case when p.driver_id % 10 in (0, 1) then 3
       when p.driver_id % 10 in (2, 3, 4) then 4 else 5 end,
  case when p.driver_id % 10 in (0, 1) then 3
       when p.driver_id % 10 in (2, 3, 4) then 4 else 5 end,
  case when p.driver_id % 10 in (0, 1) then 3
       when p.driver_id % 10 in (2, 3, 4) then 4 else 5 end,
  'Voluntary passenger evaluation; synthetic rebuild.',
  p.driver_id, p.trip_id, p.vehicle_id, 'passenger'
from passenger_rows p;

-- Normalize temporary rebuild IDs to the application's SUM date format.
with rebuild_dates as (
  select schedule_date::date as work_date,
         row_number() over (order by schedule_date::date)::int as date_no
  from public.trip_schedule
  where ticket_no like 'REBUILD-%'
  group by schedule_date::date
)
update public.trip_schedule t
set summary_id = 'SUM-' || to_char(d.work_date, 'YYYYMMDD') || '-'
                 || lpad(d.date_no::text, 6, '0')
from rebuild_dates d
where t.ticket_no like 'REBUILD-%'
  and t.schedule_date::date = d.work_date;

commit;

-- Verification.
select date_trunc('month', schedule_date::date)::date as month,
       count(*) as trips,
       count(distinct driver_id) as drivers_used,
       count(distinct vehicle_id) as vehicles_used
from public.trip_schedule
where ticket_no like 'REBUILD-%'
group by 1
order by 1;

select source,
       date_trunc('month', submit_date::date)::date as month,
       count(*) as evaluations
from public.evaluation
where comments like '%synthetic rebuild%'
   or comments like '%Synthetic rebuild%'
group by source, 2
order by 2, 1;

select date_trunc('month', work_date)::date as month,
       count(*) as attendance_rows,
       count(distinct driver_id || '-' || work_date::text) as driver_days
from public.attendance_record
where source_file = '2026 Operations Rebuild Attendance.xls'
group by 1
order by 1;
