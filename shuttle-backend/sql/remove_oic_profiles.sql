-- Remove legacy OIC profile data now that companies are managed through
-- public.client_company and trip summaries use trip_schedule.company_id.
-- Run in Supabase SQL editor after taking a backup.

begin;

-- Detach historical trips from legacy OIC profile rows before deleting them.
alter table if exists public.trip_schedule
  alter column oic_id drop not null;

update public.trip_schedule
set oic_id = null
where oic_id is not null;

-- Remove OIC-targeted notifications and old OIC profile rows.
delete from public.app_notification
where lower(coalesce(target_role, '')) = 'oic';

delete from public.oic_profile;

commit;
