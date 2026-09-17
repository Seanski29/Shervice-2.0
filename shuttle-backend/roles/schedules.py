from flask import Blueprint, request, jsonify, current_app
from datetime import datetime
from roles.notifs import trigger_notification

schedules_bp = Blueprint('schedules', __name__)
supabase = None  

def _notify_summary_saved(summary_id, staff_id, added=0, updated=0, editing=False):
    try:
        counts = []
        if added:
            counts.append(f'{added} {"trip" if added == 1 else "trips"} added')
        if updated:
            counts.append(f'{updated} {"trip" if updated == 1 else "trips"} updated')
        if not counts:
            return True
        notified = trigger_notification(
            title='Trip Summary Updated' if editing else 'Trip Summary Created',
            message=f'{summary_id}: {", ".join(counts)}.',
            target_user_id=staff_id,
            target_role='admin',
            source_tag='staff',
            db_client=supabase,
        )
        if not notified:
            current_app.logger.warning('Notification could not be saved for summary %s', summary_id)
    except Exception:
        current_app.logger.exception('Notification failed for summary %s', summary_id)

def _vehicle_type_only(raw_type):
    text = str(raw_type or '').strip()
    import re
    return re.sub(r'^\s*\d+\s*(seats?|seater)\s*[-–—:]?\s*', '', text, flags=re.IGNORECASE).strip()

def _to_int(value):
    if value in (None, ''):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None

def _to_float(value):
    if value in (None, ''):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

def _trip_update_payload(data):
    passenger_count = _to_int(data.get('passenger_count'))
    seating_capacity = _to_int(data.get('seating_capacity'))

    utilization_rate = _to_float(data.get('utilization_rate'))
    if utilization_rate is None and passenger_count is not None and seating_capacity:
        utilization_rate = passenger_count / seating_capacity

    update_payload = {}
    text_fields = [
        'summary_id', 'schedule_date', 'working_day', 'bus_type',
        'classification', 'ticket_no', 'route_name', 'departure_time',
        'estimated_arrival_time', 'remarks',
    ]
    for field in text_fields:
        if field in data:
            value = str(data.get(field) or '').strip() or None
            update_payload[field] = _vehicle_type_only(value) if field == 'bus_type' else value

    if 'vehicle_id' in data:
        update_payload['vehicle_id'] = _to_int(data.get('vehicle_id'))
    if 'driver_id' in data:
        update_payload['driver_id'] = _to_int(data.get('driver_id'))
    if 'company_id' in data:
        update_payload['company_id'] = _to_int(data.get('company_id'))
    if 'seating_capacity' in data:
        update_payload['seating_capacity'] = seating_capacity
    if 'passenger_count' in data:
        update_payload['passenger_count'] = passenger_count or 0
    if utilization_rate is not None:
        update_payload['utilization_rate'] = utilization_rate

    return update_payload

def _trip_payload_changed(existing, update_payload):
    for field, incoming in update_payload.items():
        current = existing.get(field)
        if field in ('vehicle_id', 'driver_id', 'company_id', 'seating_capacity', 'passenger_count'):
            if _to_int(current) != incoming:
                return True
        elif field == 'utilization_rate':
            current_float = _to_float(current)
            if current_float is None or incoming is None:
                if current_float != incoming:
                    return True
            elif abs(current_float - incoming) > 0.000001:
                return True
        else:
            current_text = str(current or '').strip() or None
            incoming_text = str(incoming or '').strip() or None
            if field == 'bus_type':
                current_text = _vehicle_type_only(current_text)
                incoming_text = _vehicle_type_only(incoming_text)
            if current_text != incoming_text:
                return True
    return False

@schedules_bp.route('/api/schedules/staff-options', methods=['GET'])
def get_staff_options():
    try:
        query = supabase.table('user_account').select('user_id, full_name').eq('role', 'staff').execute()
        return jsonify({"success": True, "data": query.data}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@schedules_bp.route('/api/schedules/dispatch-options', methods=['GET'])
def get_dispatch_options():
    """Returns available vehicles and drivers for summary logging."""
    try:
        all_vehicles = supabase.table('vehicle').select('*').eq('is_available', True).execute()
        raw_drivers = supabase.table('driver_profile').select('*').execute()
        
        all_drivers = raw_drivers.data or []
        active_drivers = [d for d in all_drivers if str(d.get('employment_status', '')).strip().lower() == 'active']

        # Since operations are strictly summary reports now, we no longer lock out assets.
        return jsonify({
            "success": True,
            "vehicles": all_vehicles.data or [],
            "drivers": active_drivers,
            "blocked": False
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@schedules_bp.route('/api/schedules/driver/<string:driver_id>', methods=['GET'])
def get_driver_trips(driver_id):
    """Used for evaluating a specific driver's trip history"""
    try:
        query = supabase.table('trip_schedule').select('*').eq('driver_id', driver_id).order('schedule_date', desc=True).execute()
        return jsonify({"success": True, "data": query.data}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@schedules_bp.route('/api/schedules/all', methods=['GET'])
def get_all_trips():
    """Fetches all raw trip summaries for admin/fleet views"""
    try:
        trips = supabase.table('trip_schedule').select('*').order('schedule_date', desc=True).execute()
        vehicles = supabase.table('vehicle').select('*').execute()
        drivers = supabase.table('driver_profile').select('*').execute()

        v_map = {v['vehicle_id']: v['plate_number'] for v in vehicles.data if v.get('vehicle_id') is not None}
        d_map = {d['driver_id']: d['full_name'] for d in drivers.data if d.get('driver_id') is not None}

        formatted_trips = []
        for t in trips.data:
            t['plate_number'] = v_map.get(t.get('vehicle_id'), 'No Plate Assigned')
            t['driver_name'] = d_map.get(t.get('driver_id'), 'Unassigned')
            formatted_trips.append(t)

        return jsonify({"success": True, "data": formatted_trips}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@schedules_bp.route('/api/schedules/staff-summary/<string:staff_uuid>', methods=['GET'])
def get_staff_trip_summary(staff_uuid):
    """Fetches grouped trip summaries for the staff UI"""
    try:
        query = supabase.table('trip_schedule').select('*')
        if str(staff_uuid).lower() not in ('all', 'admin'):
            query = query.eq('staff_id', staff_uuid)
        trips = query.order('schedule_date', desc=False).execute()

        vehicles = supabase.table('vehicle').select('*').execute()
        drivers = supabase.table('driver_profile').select('*').execute()
        companies = supabase.table('client_company').select('company_id, company_name').execute()

        v_map = {v['vehicle_id']: v for v in (vehicles.data or []) if v.get('vehicle_id') is not None}
        d_map = {d['driver_id']: d['full_name'] for d in (drivers.data or []) if d.get('driver_id') is not None}
        c_map = {c['company_id']: c['company_name'] for c in (companies.data or []) if c.get('company_id') is not None}

        formatted_trips = []
        for trip in trips.data or []:
            vehicle = v_map.get(trip.get('vehicle_id'), {})
            schedule_date = trip.get('schedule_date')
            working_day = trip.get('working_day')
            if not working_day and schedule_date:
                try:
                    working_day = datetime.strptime(str(schedule_date)[:10], '%Y-%m-%d').strftime('%A').upper()
                except Exception:
                    working_day = None

            seating_capacity = trip.get('seating_capacity')
            passenger_count = trip.get('passenger_count')
            utilization_rate = trip.get('utilization_rate')
            if utilization_rate is None and seating_capacity:
                try:
                    utilization_rate = float(passenger_count or 0) / float(seating_capacity)
                except Exception:
                    utilization_rate = None

            formatted_trips.append({
                **trip,
                'date': schedule_date,
                'working_day': working_day,
                'bus_type': _vehicle_type_only(trip.get('bus_type') or vehicle.get('bus_type')),
                'plate_number': vehicle.get('plate_number', 'Unassigned'),
                'seating_capacity': seating_capacity,
                'driver_name': d_map.get(trip.get('driver_id'), 'Unassigned'),
                'client_company': c_map.get(trip.get('company_id'), 'Unknown Client'),
                'utilization_rate': utilization_rate,
            })

        return jsonify({"success": True, "data": formatted_trips}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@schedules_bp.route('/api/schedules/staff-summary', methods=['POST'])
def create_staff_trip_summary(data=None, notify=True):
    try:
        if data is None:
            data = request.get_json() or {}
        staff_id = data.get('staff_id')
        rows = data.get('rows')
        if not isinstance(rows, list) or not rows:
            rows = [data]

        if not staff_id:
            return jsonify({"success": False, "message": "Staff is required."}), 400

        def to_int(value):
            if value in (None, ''): return None
            try: return int(value)
            except (TypeError, ValueError): return None

        def to_float(value):
            if value in (None, ''): return None
            try: return float(value)
            except (TypeError, ValueError): return None

        summary_id = str(data.get('summary_id') or '').strip()
        if not summary_id:
            summary_id = f"SUM-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

        payloads = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            schedule_date = row.get('schedule_date') or row.get('date') or data.get('schedule_date') or data.get('date')
            if not schedule_date:
                continue

            passenger_count = to_int(row.get('passenger_count')) or 0
            seating_capacity = to_int(row.get('seating_capacity'))
            if seating_capacity and passenger_count > seating_capacity:
                return jsonify({"success": False, "message": "Passenger count cannot exceed seating capacity."}), 400

            utilization_rate = to_float(row.get('utilization_rate'))
            if utilization_rate is None and seating_capacity:
                utilization_rate = passenger_count / seating_capacity

            payloads.append({
                "summary_id": summary_id,
                "staff_id": staff_id,
                "company_id": to_int(row.get('company_id') or data.get('company_id')),
                "schedule_date": schedule_date,
                "working_day": row.get('working_day'),
                "bus_type": _vehicle_type_only(row.get('bus_type')),
                "classification": row.get('classification'),
                "vehicle_id": to_int(row.get('vehicle_id')),
                "seating_capacity": seating_capacity,
                "ticket_no": str(row.get('ticket_no') or '').strip() or None,
                "driver_id": to_int(row.get('driver_id')),
                "route_name": str(row.get('route_name') or row.get('route') or 'Unspecified Route').strip(),
                "passenger_count": passenger_count,
                "departure_time": row.get('departure_time'),
                "estimated_arrival_time": row.get('estimated_arrival_time') or row.get('arrival_time'),
                "utilization_rate": utilization_rate,
                "remarks": row.get('remarks')
            })

        if not payloads:
            return jsonify({"success": False, "message": "At least one trip summary row with a date is required."}), 400

        response = supabase.table('trip_schedule').insert(payloads).execute()
        if notify:
            _notify_summary_saved(summary_id, staff_id, added=len(payloads))
        return jsonify({
            "success": True,
            "message": "Trip summary added.",
            "summary_id": summary_id,
            "data": response.data or []
        }), 201
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@schedules_bp.route('/api/schedules/staff-summary/<int:trip_id>', methods=['PUT'])
def update_staff_trip_summary(trip_id, data=None, notify=True):
    try:
        if data is None:
            data = request.get_json() or {}

        def to_int(value):
            if value in (None, ''): return None
            try: return int(value)
            except (TypeError, ValueError): return None

        def to_float(value):
            if value in (None, ''): return None
            try: return float(value)
            except (TypeError, ValueError): return None

        passenger_count = to_int(data.get('passenger_count'))
        seating_capacity = to_int(data.get('seating_capacity'))
        if seating_capacity and passenger_count is not None and passenger_count > seating_capacity:
            return jsonify({"success": False, "message": "Passenger count cannot exceed seating capacity."}), 400

        utilization_rate = to_float(data.get('utilization_rate'))
        if utilization_rate is None and passenger_count is not None and seating_capacity:
            utilization_rate = passenger_count / seating_capacity

        update_payload = {}
        text_fields = [
            'summary_id', 'schedule_date', 'working_day', 'bus_type',
            'classification', 'ticket_no', 'route_name', 'departure_time',
            'estimated_arrival_time', 'remarks',
        ]
        for field in text_fields:
            if field in data:
                value = str(data.get(field) or '').strip() or None
                update_payload[field] = _vehicle_type_only(value) if field == 'bus_type' else value

        if 'vehicle_id' in data:
            update_payload['vehicle_id'] = to_int(data.get('vehicle_id'))
        if 'driver_id' in data:
            update_payload['driver_id'] = to_int(data.get('driver_id'))
        if 'company_id' in data:
            update_payload['company_id'] = to_int(data.get('company_id'))
        if 'seating_capacity' in data:
            update_payload['seating_capacity'] = seating_capacity
        if 'passenger_count' in data:
            update_payload['passenger_count'] = passenger_count or 0
        if utilization_rate is not None:
            update_payload['utilization_rate'] = utilization_rate

        if not update_payload:
            return jsonify({"success": False, "message": "No trip summary fields to update."}), 400

        response = supabase.table('trip_schedule').update(update_payload).eq('trip_id', trip_id).execute()
        updated_rows = response.data or []
        if not updated_rows:
            return jsonify({"success": False, "message": "Trip summary row not found."}), 404

        updated_trip = updated_rows[0]
        if notify:
            _notify_summary_saved(
                updated_trip.get('summary_id') or f'TRIP-{trip_id}',
                updated_trip.get('staff_id'), updated=1, editing=True,
            )

        return jsonify({"success": True, "message": "Trip summary updated.", "data": updated_rows}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/staff-summary/save', methods=['POST'])
def save_staff_trip_summary():
    """Save an editor submission and notify once, including mixed adds/edits."""
    try:
        data = request.get_json() or {}
        rows = data.get('rows')
        summary_id = str(data.get('summary_id') or '').strip()
        if not summary_id or not isinstance(rows, list) or not rows:
            return jsonify({'success': False, 'message': 'Summary ID and rows are required.'}), 400
        if any(not isinstance(row, dict) for row in rows):
            return jsonify({'success': False, 'message': 'Invalid summary row.'}), 400

        existing = supabase.table('trip_schedule').select('*').eq('summary_id', summary_id).execute().data or []
        if not existing:
            return jsonify({'success': False, 'message': 'Summary not found.'}), 404
        staff_id = existing[0].get('staff_id')
        existing_by_id = {int(row['trip_id']): row for row in existing}
        valid_ids = set(existing_by_id)
        updates, additions = [], []
        seen_ids = set()
        for row in rows:
            # Validate the whole submission before writing any row.
            passengers = int(row.get('passenger_count') or 0)
            capacity = int(row.get('seating_capacity') or 0)
            if capacity and passengers > capacity:
                return jsonify({'success': False, 'message': 'Passenger count cannot exceed seating capacity.'}), 400
            if row.get('trip_id') is not None:
                trip_id = int(row['trip_id'])
                if trip_id not in valid_ids or trip_id in seen_ids:
                    return jsonify({'success': False, 'message': 'Invalid or duplicate trip in summary.'}), 400
                seen_ids.add(trip_id)
                row_payload = {**row, 'summary_id': summary_id}
                update_payload = _trip_update_payload(row_payload)
                if _trip_payload_changed(existing_by_id[trip_id], update_payload):
                    updates.append((trip_id, row_payload))
            else:
                if not (row.get('schedule_date') or row.get('date') or data.get('schedule_date')):
                    return jsonify({'success': False, 'message': 'A date is required for each new trip.'}), 400
                additions.append(row)

        for trip_id, row in updates:
            response, status = update_staff_trip_summary(trip_id, data=row, notify=False)
            if status != 200:
                return response, status
        if additions:
            response, status = create_staff_trip_summary(
                data={**data, 'staff_id': staff_id, 'rows': additions}, notify=False,
            )
            if status != 201:
                return response, status

        _notify_summary_saved(summary_id, staff_id, added=len(additions), updated=len(updates), editing=True)
        return jsonify({'success': True, 'summary_id': summary_id, 'added': len(additions), 'updated': len(updates)}), 200
    except (TypeError, ValueError):
        return jsonify({'success': False, 'message': 'Invalid trip counts or IDs.'}), 400
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500
