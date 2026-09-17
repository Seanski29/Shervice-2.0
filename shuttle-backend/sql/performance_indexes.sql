-- Safe, additive indexes for the existing Supabase schema.
-- Run in Supabase SQL Editor during a low-write window.

create index if not exists idx_trip_schedule_user_date
  on public.trip_schedule (user_id, schedule_date desc);

create index if not exists idx_trip_schedule_staff_date
  on public.trip_schedule (staff_id, schedule_date desc);

create index if not exists idx_trip_schedule_oic_date
  on public.trip_schedule (oic_id, schedule_date desc);

create index if not exists idx_trip_schedule_vehicle_status
  on public.trip_schedule (vehicle_id, trip_status);

create index if not exists idx_trip_schedule_status_date
  on public.trip_schedule (trip_status, schedule_date);

create index if not exists idx_trip_schedule_company_status_date
  on public.trip_schedule (company_id, trip_status, schedule_date);

create index if not exists idx_passenger_evaluation_trip
  on public.passenger_evaluation (trip_id);

create index if not exists idx_passenger_evaluation_submit_date
  on public.passenger_evaluation (submit_date);

create index if not exists idx_maintenance_log_vehicle_repair_date
  on public.maintenance_log (vehicle_id, repair_date desc);

create index if not exists idx_app_notification_created_at
  on public.app_notification (created_at desc);

create index if not exists idx_app_notification_target_user
  on public.app_notification (target_user_id, created_at desc);

create index if not exists idx_app_notification_role_company
  on public.app_notification (target_role, target_company, created_at desc);
