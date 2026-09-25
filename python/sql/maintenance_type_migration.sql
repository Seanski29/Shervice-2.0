-- Adds an explicit distinction between a scheduled maintenance activity and
-- a repair event. This preserves all existing maintenance_log rows.
alter table public.maintenance_log
  add column if not exists maintenance_type text;

-- Existing records are retained as repair events by default because their
-- original type is unknown. Review and change historical rows that were
-- routine maintenance checks before relying on them for reporting or ML.
update public.maintenance_log
set maintenance_type = 'repair'
where maintenance_type is null;

alter table public.maintenance_log
  alter column maintenance_type set default 'repair',
  alter column maintenance_type set not null;

alter table public.maintenance_log
  drop constraint if exists maintenance_log_maintenance_type_check;

alter table public.maintenance_log
  add constraint maintenance_log_maintenance_type_check
  check (maintenance_type in ('maintenance', 'repair'));

create index if not exists idx_maintenance_log_type_date
  on public.maintenance_log (maintenance_type, repair_date desc);
