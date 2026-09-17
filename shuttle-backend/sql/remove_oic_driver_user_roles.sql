-- Remove OIC and Driver as login/system roles while preserving operational records.
-- Run this in the Supabase SQL editor after taking a backup.

begin;

create temporary table removed_role_accounts as
select user_id
from public.user_account
where lower(role) in ('oic', 'driver');

-- Detach operational profiles from login accounts before deleting the accounts.
-- This keeps driver/OIC history rows while removing their system-user access.
alter table public.driver_profile alter column user_id drop not null;
alter table public.oic_profile alter column user_id drop not null;
alter table public.trip_schedule alter column user_id drop not null;
alter table public.maintenance_log alter column user_id drop not null;

update public.driver_profile
set user_id = null
where user_id in (select user_id from removed_role_accounts);

update public.oic_profile
set user_id = null
where user_id in (select user_id from removed_role_accounts);

update public.trip_schedule
set user_id = null
where user_id in (select user_id from removed_role_accounts);

update public.maintenance_log
set user_id = null
where user_id in (select user_id from removed_role_accounts);

-- Clear role-targeted notifications for roles that no longer exist.
delete from public.app_notification
where lower(target_role) in ('oic', 'driver')
   or target_user_id in (select user_id from removed_role_accounts);

-- Remove the OIC/Driver accounts instead of setting role to null because
-- user_account.role is not nullable.
delete from public.user_account
where user_id in (select user_id from removed_role_accounts);

commit;
