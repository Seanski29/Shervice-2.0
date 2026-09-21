-- Allow deleting a company without deleting trip summary history.
-- Existing trip_schedule rows keep their trips but company_id becomes null.
-- Run in Supabase SQL editor after taking a backup.

begin;

alter table public.trip_schedule
  drop constraint if exists fk_trip_company;

alter table public.trip_schedule
  drop constraint if exists fk_trip_client_company;

alter table public.trip_schedule
  add constraint fk_trip_company
  foreign key (company_id)
  references public.client_company(company_id)
  on delete set null;

commit;
