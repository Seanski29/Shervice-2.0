from flask import Blueprint, request, jsonify
from datetime import datetime

schedules_bp = Blueprint('schedules', __name__)
supabase = None  


def _vehicle_type_only(raw_type):
    text = str(raw_type or '').strip()
    import re
    return re.sub(r'^\s*\d+\s*(seats?|seater)\s*[-–—:]?\s*', '', text, flags=re.IGNORECASE).strip()


def _create_notification(payload):
    try:
        supabase.table('app_notification').insert(payload).execute()
    except Exception as e:
        print(f"❌ Notification Create Error: {e}")


def _blackout_for_date(target_date):
    try:
        result = supabase.table('schedule_blackout').select(
            'blackout_date, reason'
        ).eq('blackout_date', target_date).limit(1).execute()
        return result.data[0] if result.data else None
    except Exception:
        # Older deployments may not have the optional table until migration.
        return None


@schedules_bp.route('/api/schedules/blackouts', methods=['GET', 'POST'])
def manage_schedule_blackouts():
    try:
        if request.method == 'POST':
            data = request.get_json() or {}
            blackout_date = data.get('blackout_date')
            reason = str(data.get('reason') or '').strip()
            if not blackout_date or not reason:
                return jsonify({"success": False, "message": "Date and reason are required."}), 400
            result = supabase.table('schedule_blackout').upsert({
                'blackout_date': blackout_date,
                'reason': reason
            }, on_conflict='blackout_date').execute()
            return jsonify({"success": True, "data": result.data or []}), 201

        result = supabase.table('schedule_blackout').select(
            'blackout_id, blackout_date, reason'
        ).order('blackout_date').execute()
        return jsonify({"success": True, "data": result.data or []}), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500


@schedules_bp.route('/api/schedules/blackouts/<int:blackout_id>', methods=['DELETE'])
def delete_schedule_blackout(blackout_id):
    try:
        supabase.table('schedule_blackout').delete().eq('blackout_id', blackout_id).execute()
        return jsonify({"success": True}), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500


@schedules_bp.route('/api/schedules/request', methods=['POST'])
def create_trip_request():
    return jsonify({
        "success": False,
        "message": "OIC trip requests have been retired. Staff now documents trip summaries directly."
    }), 410
    try:
        data = request.get_json() or {}
        
        try: p_count = int(data.get('passenger_count', 0))
        except (ValueError, TypeError): p_count = 0 
            
        try: r_distance = float(data.get('route_distance', 0.0)) 
        except (ValueError, TypeError): r_distance = 0.0

        oic_uuid = data.get('oic_id')
        
        oic_lookup = (
            supabase.table('oic_profile')
            .select('oic_id, company_name')
            .eq('user_id', oic_uuid)
            .execute()
        )
        
        if not oic_lookup.data:
            return jsonify({"success": False, "message": "Client profile not found."}), 404
            
        oic_int_id = oic_lookup.data[0].get('oic_id')
        company_name = oic_lookup.data[0].get('company_name')
        final_route = data.get('destination', 'Unspecified Route')
        final_date = data.get('departure_date')

        blackout = _blackout_for_date(final_date)
        if blackout:
            return jsonify({
                "success": False,
                "message": f"Trip requests are blocked on {final_date}: {blackout.get('reason', 'GT LANTIN unavailable.')}"
            }), 409

        response = (
            supabase.table('trip_schedule')
            .insert({
                "oic_id": oic_int_id, 
                "staff_id": data.get('staff_id'),
                "route_name": final_route,
                "route_distance": r_distance, 
                "passenger_count": p_count, 
                "schedule_date": final_date, 
                "departure_time": data.get('departure_time'),
                "estimated_arrival_time": data.get('estimated_arrival_time'), 
                "trip_status": "Pending Staff Assignment" 
            })
            .execute()
        )

        if response.data and len(response.data) > 0:
            trip_id = response.data[0].get('trip_id')
            notification_payload = {
                "title": "New trip request",
                "message": f"{final_route} requested for {final_date}",
                "target_role": "staff",
                "related_trip_id": trip_id,
            }
            if company_name:
                notification_payload["target_company"] = company_name
            _create_notification(notification_payload)

        return jsonify({"success": True, "message": "Trip request submitted to staff!"}), 201
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

def _sweep_expired_trips():
    """Automatically sweeps the database for missed schedules and finishes abandoned ongoing trips."""
    try:
        today_str = datetime.now().strftime('%Y-%m-%d')
        
        supabase.table('trip_schedule').update({
            "trip_status": "Expired",
            "expiry_reason": "No driver or vehicle assignment before the scheduled date."
        }).lt('schedule_date', today_str).in_(
            'trip_status', ['Pending Staff Assignment', 'Scheduled']
        ).execute()

        supabase.table('trip_schedule').update({
            "trip_status": "Completed",
            "actual_end_time": None
        }).lt('schedule_date', today_str).eq('trip_status', 'Ongoing').execute()

    except Exception as e:
        print(f"⚠️ Auto-Sweep Error: {e}")


@schedules_bp.route('/api/schedules/staff-options', methods=['GET'])
def get_staff_options():
    try:
        query = supabase.table('user_account').select('user_id, full_name').eq('role', 'staff').execute()
        return jsonify({"success": True, "data": query.data}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/oic/<string:oic_uuid>', methods=['GET'])
def get_oic_trips(oic_uuid):
    return jsonify({"success": True, "data": []}), 200
    try:
        user_profile = supabase.table('oic_profile').select('company_name').eq('user_id', oic_uuid).execute()
        if not user_profile.data:
            return jsonify({"success": True, "data": []}), 200
            
        company_name = user_profile.data[0].get('company_name')
        company_colleagues = supabase.table('oic_profile').select('oic_id').eq('company_name', company_name).execute()
        allowed_oic_ids = [colleague['oic_id'] for colleague in company_colleagues.data]

        trips = supabase.table('trip_schedule').select('*').in_('oic_id', allowed_oic_ids).order('schedule_date', desc=True).execute()
        
        # 🔥 FIX: Safe Table Search to prevent crash if columns differ
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

    
@schedules_bp.route('/api/schedules/pending', methods=['GET'])
def get_pending_schedules():
    try:
        query = supabase.table('trip_schedule').select('*').eq('trip_status', 'Pending Staff Assignment').execute()
        return jsonify({"success": True, "data": query.data}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/dispatch-options', methods=['GET'])
def get_dispatch_options():
    try:
        all_vehicles = supabase.table('vehicle').select('*').eq('is_available', True).execute()
        raw_drivers = supabase.table('driver_profile').select('*').execute()
        
        all_drivers = raw_drivers.data or []
        active_drivers = [d for d in all_drivers if str(d.get('employment_status', '')).strip().lower() == 'active']

        target_date = request.args.get('date')
        is_summary_picker = str(request.args.get('summary') or '').strip().lower() in ('1', 'true', 'yes')
        if not target_date:
            return jsonify({"success": True, "vehicles": all_vehicles.data, "drivers": all_drivers if is_summary_picker else active_drivers}), 200

        blackout = _blackout_for_date(target_date)
        if blackout:
            return jsonify({
                "success": True,
                "vehicles": [],
                "drivers": [],
                "blocked": True,
                "block_reason": blackout.get('reason', 'GT LANTIN unavailable.')
            }), 200

        busy_query = (
            supabase.table('trip_schedule')
            .select('vehicle_id, driver_id')
            .eq('schedule_date', target_date)
            .in_('trip_status', ['Scheduled', 'In Progress', 'Ongoing'])
            .execute()
        )
            
        busy_vehicle_ids = [t['vehicle_id'] for t in busy_query.data if t.get('vehicle_id')]
        busy_driver_ids = [t['driver_id'] for t in busy_query.data if t.get('driver_id')]

        available_vehicles = [v for v in all_vehicles.data if v['vehicle_id'] not in busy_vehicle_ids]
        available_drivers = all_drivers if is_summary_picker else [d for d in active_drivers if d.get('driver_id') not in busy_driver_ids]

        return jsonify({
            "success": True,
            "vehicles": available_vehicles,
            "drivers": available_drivers,
            "blocked": False,
            "availability_message": {
                "drivers": "No driver available for this date." if not available_drivers else None,
                "vehicles": "No vehicle available for this date." if not available_vehicles else None
            }
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/complete', methods=['POST'])
def complete_trip():
    try:
        data = request.get_json() or {}
        trip_id = data.get('trip_id')
        
        response = (
            supabase.table('trip_schedule')
            .update({
                "trip_status": "Completed",
                "actual_end_time": datetime.utcnow().isoformat()
            })
            .eq('trip_id', trip_id)
            .execute()
        )

        return jsonify({"success": True, "message": "Trip marked as finished!"}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500
    

@schedules_bp.route('/api/schedules/driver/<string:driver_id>', methods=['GET'])
def get_driver_trips(driver_id):
    try:
        query = supabase.table('trip_schedule').select('*').eq('driver_id', driver_id).order('schedule_date', desc=True).execute()
        return jsonify({"success": True, "data": query.data}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@schedules_bp.route('/api/schedules/update-status', methods=['POST'])
def update_trip_status():
    try:
        data = request.get_json() or {}
        trip_id = data.get('trip_id')
        new_status = data.get('status')
        
        if new_status == 'Ongoing':
            trip_query = supabase.table('trip_schedule').select('driver_id').eq('trip_id', trip_id).execute()
            if trip_query.data and trip_query.data[0].get('driver_id'):
                driver_id = trip_query.data[0].get('driver_id')
                active_check = supabase.table('trip_schedule').select('trip_id').eq('driver_id', driver_id).eq('trip_status', 'Ongoing').execute()
                
                if active_check.data:
                    return jsonify({"success": False, "message": "You already have an active trip in progress. Please finish it first."}), 400

        update_payload = {"trip_status": new_status}
        
        if new_status == 'Ongoing':
            update_payload['actual_start_time'] = datetime.utcnow().isoformat()
        elif new_status == 'Completed':
            update_payload['actual_end_time'] = datetime.utcnow().isoformat()
        
        response = supabase.table('trip_schedule').update(update_payload).eq('trip_id', trip_id).execute()

        return jsonify({"success": True, "message": f"Trip updated to {new_status}"}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@schedules_bp.route('/api/schedules/all', methods=['GET'])
def get_all_trips():
    try:
        _sweep_expired_trips()

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

    
@schedules_bp.route('/api/schedules/staff/<string:staff_uuid>', methods=['GET'])
def get_staff_assigned_trips(staff_uuid):
    try:
        _sweep_expired_trips()

        trips = supabase.table('trip_schedule').select('*').eq('staff_id', staff_uuid).order('schedule_date', desc=True).execute()
        vehicles = supabase.table('vehicle').select('*').execute()
        drivers = supabase.table('driver_profile').select('*').execute()
        companies = supabase.table('client_company').select('company_id, company_name').execute()

        v_map = {v['vehicle_id']: v['plate_number'] for v in vehicles.data if v.get('vehicle_id') is not None}
        d_map = {d['driver_id']: d['full_name'] for d in drivers.data if d.get('driver_id') is not None}
        c_map = {c['company_id']: c['company_name'] for c in companies.data if c.get('company_id') is not None}

        formatted_trips = []
        for t in trips.data:
            t['plate_number'] = v_map.get(t.get('vehicle_id'), 'Pending Assignment')
            t['driver_name'] = d_map.get(t.get('driver_id'), 'Pending Assignment')
            t['client_company'] = c_map.get(t.get('company_id'), 'Unknown Client')
            formatted_trips.append(t)

        return jsonify({"success": True, "data": formatted_trips}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/staff-summary/<string:staff_uuid>', methods=['GET'])
def get_staff_trip_summary(staff_uuid):
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

        excluded_statuses = ('ongoing', 'expired', 'rejected')
        formatted_trips = []
        for trip in trips.data or []:
            status = str(trip.get('trip_status') or '').strip().lower()
            if any(blocked in status for blocked in excluded_statuses):
                continue

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
                'classification': trip.get('classification'),
                'plate_number': vehicle.get('plate_number', 'Unassigned'),
                'seating_capacity': seating_capacity,
                'ticket_no': trip.get('ticket_no'),
                'driver_name': d_map.get(trip.get('driver_id'), 'Unassigned'),
                'client_company': c_map.get(trip.get('company_id'), 'Unknown Client'),
                'utilization_rate': utilization_rate,
                'remarks': trip.get('remarks'),
            })

        return jsonify({"success": True, "data": formatted_trips}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/staff-summary', methods=['POST'])
def create_staff_trip_summary():
    try:
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
                return jsonify({
                    "success": False,
                    "message": "Passenger count cannot exceed seating capacity."
                }), 400
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
                "route_distance": to_float(row.get('route_distance')) or 0,
                "passenger_count": passenger_count,
                "departure_time": row.get('departure_time'),
                "estimated_arrival_time": row.get('estimated_arrival_time') or row.get('arrival_time'),
                "utilization_rate": utilization_rate,
                "remarks": row.get('remarks'),
                "trip_status": row.get('trip_status') or data.get('trip_status') or "Completed",
            })

        if not payloads:
            return jsonify({"success": False, "message": "At least one trip summary row with a date is required."}), 400

        response = supabase.table('trip_schedule').insert(payloads).execute()
        return jsonify({
            "success": True,
            "message": "Trip summary added.",
            "summary_id": summary_id,
            "data": response.data or []
        }), 201
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/staff-summary/<int:trip_id>', methods=['PUT'])
def update_staff_trip_summary(trip_id):
    try:
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
            return jsonify({
                "success": False,
                "message": "Passenger count cannot exceed seating capacity."
            }), 400
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

        response = (
            supabase.table('trip_schedule')
            .update(update_payload)
            .eq('trip_id', trip_id)
            .execute()
        )
        return jsonify({"success": True, "message": "Trip summary updated.", "data": response.data or []}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/update-request', methods=['PUT'])
def update_trip_request():
    try:
        data = request.get_json() or {}
        trip_id = data.get('trip_id')
        
        check = supabase.table('trip_schedule').select('trip_status').eq('trip_id', trip_id).execute()
        if not check.data:
            return jsonify({"success": False, "message": "Trip not found."}), 404
            
        current_status = check.data[0].get('trip_status')
        if current_status not in ['Pending Staff Assignment', 'Rejected']:
            return jsonify({"success": False, "message": "You can only edit pending or rejected requests."}), 400

        try: p_count = int(data.get('passenger_count', 0))
        except (ValueError, TypeError): p_count = 0 
            
        try: r_distance = float(data.get('route_distance', 0.0)) 
        except (ValueError, TypeError): r_distance = 0.0

        staff_id = data.get('staff_id')
        
        response = (
            supabase.table('trip_schedule')
            .update({
                "staff_id": staff_id,
                "route_name": data.get('destination'),
                "route_distance": r_distance,
                "passenger_count": p_count,
                "schedule_date": data.get('departure_date'),
                "departure_time": data.get('departure_time'),
                "estimated_arrival_time": data.get('estimated_arrival_time'),
                "trip_status": "Pending Staff Assignment", 
                "driver_id": None,    
                "vehicle_id": None  
            })
            .eq('trip_id', trip_id)
            .execute()
        )

        route_name = data.get('destination', 'A trip')
        if staff_id:
            _create_notification({
                "title": "Trip Request Resubmitted",
                "message": f"A client updated {route_name}. Please review and assign assets.",
                "target_user_id": staff_id,
                "target_role": "staff",
                "related_trip_id": trip_id
            })
        else:
            staff_members = supabase.table('user_account').select('user_id').eq('role', 'staff').execute()
            if staff_members.data:
                for staff in staff_members.data:
                    _create_notification({
                        "title": "Trip Request Resubmitted",
                        "message": f"A client updated {route_name}. Please review and assign assets.",
                        "target_user_id": staff.get('user_id'),
                        "target_role": "staff",
                        "related_trip_id": trip_id
                    })

        return jsonify({"success": True, "message": "Trip updated and sent for re-approval!"}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

    
@schedules_bp.route('/api/schedules/reject', methods=['POST'])
def reject_trip_request():
    try:
        data = request.get_json() or {}
        trip_id = data.get('trip_id')
        rejection_reason = str(data.get('rejection_reason') or '').strip()

        if not rejection_reason:
            return jsonify({"success": False, "message": "A reason is required when rejecting a trip request."}), 400

        supabase.table('trip_schedule').update({
            "trip_status": "Rejected",
            "rejection_reason": rejection_reason
        }).eq('trip_id', trip_id).execute()

        return jsonify({"success": True, "message": "Trip request rejected."}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/assign', methods=['POST'])
def assign_trip_assets():
    try:
        data = request.get_json() or {}
        trip_id = data.get('trip_id')
        driver_id = data.get('driver_id')

        trip_result = supabase.table('trip_schedule').select(
            'schedule_date, trip_status'
        ).eq('trip_id', trip_id).limit(1).execute()
        if not trip_result.data:
            return jsonify({"success": False, "message": "Trip not found."}), 404
        trip = trip_result.data[0]
        target_date = trip.get('schedule_date')

        blackout = _blackout_for_date(target_date)
        if blackout:
            return jsonify({"success": False, "message": f"Assignment blocked: {blackout.get('reason', 'GT LANTIN unavailable.')}"}), 409

        vehicle_id = data.get('vehicle_id')
        vehicle_result = supabase.table('vehicle').select('vehicle_id, is_available').eq(
            'vehicle_id', vehicle_id
        ).limit(1).execute()
        if not vehicle_result.data or not vehicle_result.data[0].get('is_available', False):
            return jsonify({"success": False, "message": "No vehicle available for this assignment."}), 409

        driver_result = supabase.table('driver_profile').select(
            'driver_id, employment_status'
        ).eq('driver_id', driver_id).limit(1).execute()
        if not driver_result.data or str(driver_result.data[0].get('employment_status', '')).lower() != 'active':
            return jsonify({"success": False, "message": "No driver available for this assignment."}), 409

        conflicts = supabase.table('trip_schedule').select('trip_id').eq(
            'schedule_date', target_date
        ).in_('trip_status', ['Scheduled', 'In Progress', 'Ongoing']).or_(
            f'driver_id.eq.{driver_id},vehicle_id.eq.{vehicle_id}'
        ).neq('trip_id', trip_id).execute()
        if conflicts.data:
            return jsonify({"success": False, "message": "The selected driver or vehicle is already assigned on this date."}), 409

        supabase.table('trip_schedule').update({
            "driver_id": driver_id,  
            "vehicle_id": vehicle_id,
            "trip_status": "Scheduled"
        }).eq('trip_id', trip_id).execute()

        return jsonify({"success": True, "message": "Trip successfully dispatched!"}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500
