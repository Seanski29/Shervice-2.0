-- Repair the existing synthetic 2026 operations data.
--
-- This script is intentionally scoped to rows created by the rebuild script:
--   * trips have ticket_no beginning with REBUILD-
--   * attendance has the rebuild source_file
--
-- It does not delete rows and does not modify unrelated real records.

begin;

-- 1) Give every synthetic work date one generated-looking summary ID.
--    All trips on the same date share one summary ID.
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

-- 2) Enforce passenger_count <= seating_capacity and recalculate utilization.
update public.trip_schedule
set passenger_count = least(
      greatest(coalesce(passenger_count, 0), 0),
      greatest(coalesce(seating_capacity, 0), 0)
    ),
    utilization_rate = case
      when coalesce(seating_capacity, 0) > 0 then round(
        least(
          greatest(coalesce(passenger_count, 0), 0),
          greatest(coalesce(seating_capacity, 0), 0)
        )::numeric / seating_capacity::numeric,
        2
      )
      else null
    end
where ticket_no like 'REBUILD-%';

-- 3) Replace generic synthetic remarks with varied, realistic outcomes.
update public.trip_schedule
set remarks = case (trip_id % 5)
  when 0 then 'Trip successful.'
  when 1 then 'Trip completed on schedule.'
  when 2 then 'Trip completed with no reported issues.'
  when 3 then 'Minor traffic delay; trip completed successfully.'
  else 'Passenger service completed successfully.'
end
where ticket_no like 'REBUILD-%';

-- 4) GT Lantin Internal is the operating company, not a client.
--    Reassign its synthetic trips across the remaining client companies.
with eligible_companies as (
  select array_agg(company_id order by company_id) as ids,
         count(*)::int as company_count
  from public.client_company
  where company_name not ilike '%GT LANTIN%'
), internal_trips as (
  select t.trip_id,
         row_number() over (order by t.trip_id)::int as trip_no
  from public.trip_schedule t
  join public.client_company c on c.company_id = t.company_id
  where t.ticket_no like 'REBUILD-%'
    and c.company_name ilike '%GT LANTIN%'
)
update public.trip_schedule t
set company_id = e.ids[((i.trip_no - 1) % e.company_count) + 1]
from internal_trips i
cross join eligible_companies e
where t.trip_id = i.trip_id
  and e.company_count > 0;

-- 5) Create useful attendance variation for the ML labels.
--    Driver bands are deterministic and repeat across workdays:
--      IDs ending 5-6: low lateness      -> Elite candidates
--      IDs ending 2-4,9: moderate lateness -> Consistent candidates
--      IDs ending 7-8: high lateness     -> Tardiness candidates
--      IDs ending 0-1: good attendance + score-3 evaluations -> Safety candidates
with attendance_values as (
  select
    a.attendance_id,
    a.driver_id,
    a.work_date,
    case
      when mod(a.driver_id, 10) in (5, 6)
        then mod(a.driver_id + extract(day from a.work_date)::int, 4)
      when mod(a.driver_id, 10) in (2, 3, 4, 9)
        then 3 + mod(a.driver_id + extract(day from a.work_date)::int, 4)
      when mod(a.driver_id, 10) in (7, 8)
        then 8 + mod(a.driver_id + extract(day from a.work_date)::int, 8)
      else 2 + mod(a.driver_id + extract(day from a.work_date)::int, 4)
    end::int as late_minutes
  from public.attendance_record a
  where a.source_file = '2026 Operations Rebuild Attendance.xls'
)
update public.attendance_record a
set time_in = to_char(
      time '03:00' + v.late_minutes * interval '1 minute', 'HH24:MI'
    ),
    morning_in = to_char(
      time '03:00' + v.late_minutes * interval '1 minute', 'HH24:MI'
    ),
    total_minutes_late = v.late_minutes,
    note = case
      when v.late_minutes = 0 then 'Present'
      else 'Present - Late'
    end,
    raw_payload = jsonb_build_object(
      'generated', true,
      'repaired', true,
      'work_date', v.work_date,
      'late_minutes', v.late_minutes
    )
from attendance_values v
where a.attendance_id = v.attendance_id;

commit;

-- Verification.
select date_trunc('month', schedule_date::date)::date as month,
       count(*) as trips,
       count(*) filter (where passenger_count > seating_capacity)
         as over_capacity_rows,
       count(distinct summary_id) as summaries
from public.trip_schedule
where ticket_no like 'REBUILD-%'
group by 1
order by 1;

select min(total_minutes_late) as min_late,
       max(total_minutes_late) as max_late,
       round(avg(total_minutes_late), 2) as avg_late
from public.attendance_record
where source_file = '2026 Operations Rebuild Attendance.xls';

select count(*) as gt_lantin_synthetic_trips
from public.trip_schedule t
join public.client_company c on c.company_id = t.company_id
where t.ticket_no like 'REBUILD-%'
  and c.company_name ilike '%GT LANTIN%';
