-- Optional columns for the Staff Trip Summary.
-- These match the billing-style 10-16 workbook tab:
-- Date, Working Day, Bus Type, Classification, Plate, Capacity, Ticket No.,
-- Driver, Route, Passenger Count, Departure, Arrival, Utilization, Remarks.

alter table public.trip_schedule
  add column if not exists summary_id text,
  add column if not exists working_day text,
  add column if not exists bus_type text,
  add column if not exists vehicle_type text,
  add column if not exists classification text,
  add column if not exists driver_id integer references public.driver_profile(driver_id) on delete set null,
  add column if not exists company_id bigint references public.client_company(company_id) on delete set null,
  add column if not exists seating_capacity integer,
  add column if not exists ticket_no text,
  add column if not exists utilization_rate numeric,
  add column if not exists remarks text;

-- Keep the fleet category separate from the legacy bus_type field, which
-- contains the vehicle model and seating capacity in older records.
alter table public.vehicle
  add column if not exists vehicle_type text;

alter table public.client_company
  add column if not exists address text;

create index if not exists idx_trip_schedule_summary_staff_date
  on public.trip_schedule (staff_id, schedule_date);

create index if not exists idx_trip_schedule_summary_id
  on public.trip_schedule (summary_id);

create index if not exists idx_trip_schedule_summary_vehicle_date
  on public.trip_schedule (vehicle_id, schedule_date);

create index if not exists idx_trip_schedule_summary_driver_date
  on public.trip_schedule (driver_id, schedule_date);

create index if not exists idx_trip_schedule_summary_company_date
  on public.trip_schedule (company_id, schedule_date);

notify pgrst, 'reload schema';
