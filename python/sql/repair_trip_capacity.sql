-- Non-destructive repair for existing trip data.
-- This does not delete or recreate trips, attendance, evaluations, or tickets.
-- It aligns each trip with the assigned vehicle's seating capacity and ensures
-- passenger_count never exceeds that capacity.

begin;

with vehicle_capacity as (
  select
    vehicle_id,
    bus_type,
    case
      when bus_type ~ '^[0-9]+'
        then split_part(bus_type, ' ', 1)::integer
      else 40
    end as capacity
  from public.vehicle
)
update public.trip_schedule t
set bus_type = coalesce(vc.bus_type, t.bus_type),
    seating_capacity = vc.capacity,
    passenger_count = least(
      greatest(coalesce(t.passenger_count, 0), 0),
      vc.capacity
    ),
    utilization_rate = round(
      least(
        greatest(coalesce(t.passenger_count, 0), 0),
        vc.capacity
      )::numeric / nullif(vc.capacity, 0),
      2
    )
from vehicle_capacity vc
where t.vehicle_id = vc.vehicle_id;

commit;

-- Verification: this should return zero.
select count(*) as over_capacity_rows
from public.trip_schedule
where passenger_count > seating_capacity;

select count(*) as repaired_trip_rows,
       count(distinct vehicle_id) as vehicles_covered
from public.trip_schedule
where vehicle_id is not null;
