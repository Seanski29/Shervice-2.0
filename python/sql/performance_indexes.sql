-- Safe, additive indexes for the existing Supabase schema.
-- Run in Supabase SQL Editor during a low-write window.

-- Core indexes used by driver history, attendance, and evaluation screens.
create index if not exists idx_trip_schedule_driver_date
  on public.trip_schedule (driver_id, schedule_date desc);

create index if not exists idx_trip_schedule_date
  on public.trip_schedule (schedule_date desc);

create index if not exists idx_attendance_record_driver_date
  on public.attendance_record (driver_id, work_date desc);

create index if not exists idx_attendance_record_work_date
  on public.attendance_record (work_date desc);

create index if not exists idx_evaluation_driver_date
  on public.evaluation (driver_id, submit_date desc);

create index if not exists idx_evaluation_trip
  on public.evaluation (trip_id);
