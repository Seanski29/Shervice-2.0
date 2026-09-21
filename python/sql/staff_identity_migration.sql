-- Introduce a stable staff identifier for operational ownership.
-- user_id remains only as the Supabase Auth link in user_account.

begin;

create extension if not exists pgcrypto;

alter table public.user_account
  add column if not exists staff_id uuid default gen_random_uuid();

update public.user_account
set staff_id = gen_random_uuid()
where lower(role) = 'staff' and staff_id is null;

create unique index if not exists user_account_staff_id_key
  on public.user_account (staff_id)
  where staff_id is not null;

update public.trip_schedule trip
set staff_id = account.staff_id
from public.user_account account
where lower(account.role) = 'staff'
  and trip.staff_id = account.user_id
  and account.staff_id is not null;

alter table public.trip_schedule
  drop column if exists oic_id;

alter table public.driver_profile
  drop column if exists user_id;

-- driver_id is the only identifier needed for driver records.
-- Do not add an auth UUID or user_id to driver_profile.

alter table if exists public.oic_profile
  drop column if exists user_id;

drop table if exists public.oic_profile;

commit;
