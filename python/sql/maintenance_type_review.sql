-- Review existing records before changing their type. This does not modify data.
-- Run maintenance_type_migration.sql first.
select
  maintenance_id,
  description,
  category,
  maintenance_type,
  case
    when lower(coalesce(description, '')) ~ '(routine|preventive|inspection|scheduled service|check-up)'
      then 'maintenance'
    when lower(coalesce(description, '')) ~ '(repair|repaired|replace|replaced|broken|fault|leak|damage)'
      then 'repair'
    else 'review manually'
  end as suggested_type
from public.maintenance_log
order by repair_date desc nulls last, maintenance_id desc;

-- After reviewing the results, apply only confirmed classifications, for example:
-- update public.maintenance_log
-- set maintenance_type = 'maintenance'
-- where maintenance_id in (/* confirmed maintenance IDs */);

-- Existing rows that are actual repairs should remain:
-- update public.maintenance_log
-- set maintenance_type = 'repair'
-- where maintenance_id in (/* confirmed repair IDs */);
