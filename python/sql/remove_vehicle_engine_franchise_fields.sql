alter table public.vehicle
  drop column if exists engine_no,
  drop column if exists franchise_no,
  drop column if exists franchise_expiry;
