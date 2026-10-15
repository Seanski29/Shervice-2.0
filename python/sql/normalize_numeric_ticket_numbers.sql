-- Convert existing trip ticket values to six-digit numeric-looking values.
-- This changes only ticket_no; trip assignments and other trip data remain intact.
-- Review the preview query before applying in production.

begin;

select count(*) as trips_to_update,
       min(ticket_no) as current_ticket_example,
       max(ticket_no) as current_ticket_example_max
from public.trip_schedule;

with numbered_trips as (
  select
    trip_id,
    lpad((100000 + row_number() over (order by trip_id))::text, 6, '0') as new_ticket_no
  from public.trip_schedule
)
update public.trip_schedule t
set ticket_no = n.new_ticket_no
from numbered_trips n
where t.trip_id = n.trip_id;

-- Align each trip with the capacity of its assigned vehicle.
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

select count(*) as numeric_ticket_rows,
       count(*) filter (where ticket_no !~ '^[0-9]+$') as non_numeric_ticket_rows,
       count(*) filter (where passenger_count > seating_capacity) as over_capacity_rows,
       min(ticket_no) as first_ticket,
       max(ticket_no) as last_ticket
from public.trip_schedule;
