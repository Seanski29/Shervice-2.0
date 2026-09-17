-- Optional columns for the Staff Trip Summary.
-- These match the billing-style 10-16 workbook tab:
-- Date, Working Day, Bus Type, Classification, Plate, Capacity, Ticket No.,
-- Driver, Route, Passenger Count, Departure, Arrival, Utilization, Remarks.

alter table public.trip_schedule
  add column if not exists summary_id text,
  add column if not exists working_day text,
  add column if not exists bus_type text,
  add column if not exists classification text,
  add column if not exists seating_capacity integer,
  add column if not exists ticket_no text,
  add column if not exists utilization_rate numeric,
  add column if not exists remarks text;

create index if not exists idx_trip_schedule_summary_staff_date
  on public.trip_schedule (staff_id, schedule_date);

create index if not exists idx_trip_schedule_summary_id
  on public.trip_schedule (summary_id);

create index if not exists idx_trip_schedule_summary_vehicle_date
  on public.trip_schedule (vehicle_id, schedule_date);
