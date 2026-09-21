-- Remove legacy OIC and Driver login accounts while preserving driver records.
-- Run this in the Supabase SQL editor after taking a backup.

begin;

create temporary table removed_role_accounts as
select user_id
from public.user_account
where lower(role) in ('oic', 'driver');

-- Clear role-targeted notifications for roles that no longer exist.
delete from public.app_notification
where lower(target_role) in ('oic', 'driver')
   or target_user_id in (select user_id from removed_role_accounts);

-- Remove the OIC/Driver accounts instead of setting role to null because
-- user_account.role is not nullable.
delete from public.user_account
where user_id in (select user_id from removed_role_accounts);

commit;
