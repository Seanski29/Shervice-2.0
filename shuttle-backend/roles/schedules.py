from flask import Blueprint, request, jsonify
from datetime import datetime

schedules_bp = Blueprint('schedules', __name__)
supabase = None  


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
            return jsonify({"success": False, "message": "OIC Profile not found."}), 404
            
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
        
        # 1. Mark unassigned or unstarted trips older than today as Expired
        supabase.table('trip_schedule').update({
            "trip_status": "Expired",
            "expiry_reason": "No driver or vehicle assignment before the scheduled date."
        }).lt('schedule_date', today_str).in_(
            'trip_status', ['Pending Staff Assignment', 'Scheduled']
        ).execute()

        # 2. Force-complete abandoned 'Ongoing' trips from past days so drivers are unlocked,
        # but leave actual_end_time as None so Route Delay ML clustering ignores them.
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
    try:
        user_profile = supabase.table('oic_profile').select('company_name').eq('user_id', oic_uuid).execute()
        if not user_profile.data:
            return jsonify({"success": True, "data": []}), 200
            
        company_name = user_profile.data[0].get('company_name')
        company_colleagues = supabase.table('oic_profile').select('oic_id').eq('company_name', company_name).execute()
        allowed_oic_ids = [colleague['oic_id'] for colleague in company_colleagues.data]

        trips = supabase.table('trip_schedule').select('*').in_('oic_id', allowed_oic_ids).order('schedule_date', desc=True).execute()
        vehicles = supabase.table('vehicle').select('vehicle_id, plate_number').execute()
        drivers = supabase.table('driver_profile').select('user_id, full_name').execute()

        v_map = {v['vehicle_id']: v['plate_number'] for v in vehicles.data}
        d_map = {d['user_id']: d['full_name'] for d in drivers.data}

        formatted_trips = []
        for t in trips.data:
            t['plate_number'] = v_map.get(t.get('vehicle_id'), 'No Plate Assigned')
            t['driver_name'] = d_map.get(t.get('user_id'), 'Unassigned')
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
        all_vehicles = supabase.table('vehicle').select('vehicle_id, plate_number, bus_type').eq('is_available', True).execute()
        raw_drivers = supabase.table('driver_profile').select('user_id, full_name, employment_status').execute()
        active_drivers = [d for d in raw_drivers.data if str(d.get('employment_status', '')).strip().lower() == 'active']

        target_date = request.args.get('date')
        if not target_date:
            return jsonify({"success": True, "vehicles": all_vehicles.data, "drivers": active_drivers}), 200

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
            .select('vehicle_id, user_id')
            .eq('schedule_date', target_date)
            .in_('trip_status', ['Scheduled', 'In Progress', 'Ongoing'])
            .execute()
        )
            
        busy_vehicle_ids = [t['vehicle_id'] for t in busy_query.data if t.get('vehicle_id')]
        busy_driver_uuids = [t['user_id'] for t in busy_query.data if t.get('user_id')]

        available_vehicles = [v for v in all_vehicles.data if v['vehicle_id'] not in busy_vehicle_ids]
        available_drivers = [d for d in active_drivers if d['user_id'] not in busy_driver_uuids]

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
    

@schedules_bp.route('/api/schedules/driver/<string:driver_uuid>', methods=['GET'])
def get_driver_trips(driver_uuid):
    try:
        query = supabase.table('trip_schedule').select('*').eq('user_id', driver_uuid).order('schedule_date', desc=True).execute()
        return jsonify({"success": True, "data": query.data}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@schedules_bp.route('/api/schedules/update-status', methods=['POST'])
def update_trip_status():
    try:
        data = request.get_json() or {}
        trip_id = data.get('trip_id')
        new_status = data.get('status')
        
        # 🛡️ CONCURRENCY LOCK: Prevent starting a new trip if one is already ongoing
        if new_status == 'Ongoing':
            trip_query = supabase.table('trip_schedule').select('user_id').eq('trip_id', trip_id).execute()
            if trip_query.data and trip_query.data[0].get('user_id'):
                user_uuid = trip_query.data[0].get('user_id')
                active_check = supabase.table('trip_schedule').select('trip_id').eq('user_id', user_uuid).eq('trip_status', 'Ongoing').execute()
                
                if active_check.data:
                    return jsonify({"success": False, "message": "You already have an active trip in progress. Please finish it first."}), 400

        update_payload = {"trip_status": new_status}
        
        # Capture precise timestamps for the ML Clustering Pipeline
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
        vehicles = supabase.table('vehicle').select('vehicle_id, plate_number').execute()
        drivers = supabase.table('driver_profile').select('user_id, full_name').execute()

        v_map = {v['vehicle_id']: v['plate_number'] for v in vehicles.data}
        d_map = {d['user_id']: d['full_name'] for d in drivers.data}

        formatted_trips = []
        for t in trips.data:
            t['plate_number'] = v_map.get(t.get('vehicle_id'), 'No Plate Assigned')
            t['driver_name'] = d_map.get(t.get('user_id'), 'Unassigned')
            formatted_trips.append(t)

        return jsonify({"success": True, "data": formatted_trips}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

    
@schedules_bp.route('/api/schedules/staff/<string:staff_uuid>', methods=['GET'])
def get_staff_assigned_trips(staff_uuid):
    try:
        _sweep_expired_trips()

        trips = supabase.table('trip_schedule').select('*').eq('staff_id', staff_uuid).order('schedule_date', desc=True).execute()
        vehicles = supabase.table('vehicle').select('vehicle_id, plate_number').execute()
        drivers = supabase.table('driver_profile').select('user_id, full_name').execute()
        oics = supabase.table('oic_profile').select('oic_id, company_name').execute()

        v_map = {v['vehicle_id']: v['plate_number'] for v in vehicles.data}
        d_map = {d['user_id']: d['full_name'] for d in drivers.data}
        o_map = {o['oic_id']: o['company_name'] for o in oics.data}

        formatted_trips = []
        for t in trips.data:
            t['plate_number'] = v_map.get(t.get('vehicle_id'), 'Pending Assignment')
            t['driver_name'] = d_map.get(t.get('user_id'), 'Pending Assignment')
            t['client_company'] = o_map.get(t.get('oic_id'), 'Unknown Client')
            formatted_trips.append(t)

        return jsonify({"success": True, "data": formatted_trips}), 200
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
                "user_id": None,    
                "vehicle_id": None  
            })
            .eq('trip_id', trip_id)
            .execute()
        )

        route_name = data.get('destination', 'A trip')
        if staff_id:
            _create_notification({
                "title": "Trip Request Resubmitted",
                "message": f"An OIC updated {route_name}. Please review and assign assets.",
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
                        "message": f"An OIC updated {route_name}. Please review and assign assets.",
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

        trip_info = supabase.table('trip_schedule').select('route_name, oic_id').eq('trip_id', trip_id).execute()
        if trip_info.data:
            route_name = trip_info.data[0].get('route_name')
            oic_id = trip_info.data[0].get('oic_id')
            
            oic_profile = supabase.table('oic_profile').select('user_id, company_name').eq('oic_id', oic_id).execute()
            if oic_profile.data:
                _create_notification({
                    "title": "Trip Request Rejected",
                    "message": f"Your request for {route_name} was rejected: {rejection_reason}. Please edit and resubmit.",
                    "target_user_id": oic_profile.data[0].get('user_id'),
                    "target_role": "oic",
                    "target_company": oic_profile.data[0].get('company_name'),
                    "related_trip_id": trip_id
                })

        return jsonify({"success": True, "message": "Trip request rejected."}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@schedules_bp.route('/api/schedules/assign', methods=['POST'])
def assign_trip_assets():
    try:
        data = request.get_json() or {}
        trip_id = data.get('trip_id')
        driver_uuid = data.get('driver_uuid')

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
            'user_id, employment_status'
        ).eq('user_id', driver_uuid).limit(1).execute()
        if not driver_result.data or str(driver_result.data[0].get('employment_status', '')).lower() != 'active':
            return jsonify({"success": False, "message": "No driver available for this assignment."}), 409

        conflicts = supabase.table('trip_schedule').select('trip_id').eq(
            'schedule_date', target_date
        ).in_('trip_status', ['Scheduled', 'In Progress', 'Ongoing']).or_(
            f'user_id.eq.{driver_uuid},vehicle_id.eq.{vehicle_id}'
        ).neq('trip_id', trip_id).execute()
        if conflicts.data:
            return jsonify({"success": False, "message": "The selected driver or vehicle is already assigned on this date."}), 409

        supabase.table('trip_schedule').update({
            "user_id": driver_uuid,  
            "vehicle_id": vehicle_id,
            "trip_status": "Scheduled"
        }).eq('trip_id', trip_id).execute()

        trip_info = supabase.table('trip_schedule').select('route_name, schedule_date, oic_id').eq('trip_id', trip_id).execute()

        if trip_info.data:
            route_name = trip_info.data[0].get('route_name')
            schedule_date = trip_info.data[0].get('schedule_date')
            oic_id = trip_info.data[0].get('oic_id')

            oic_profile = supabase.table('oic_profile').select('user_id, company_name').eq('oic_id', oic_id).execute()
            company_name = None
            
            if oic_profile.data:
                oic_user_id = oic_profile.data[0].get('user_id')
                company_name = oic_profile.data[0].get('company_name')
                
                _create_notification({
                    "title": "Trip Assigned",
                    "message": f"Assets have been assigned for your {route_name} trip on {schedule_date}.",
                    "target_user_id": oic_user_id,
                    "target_role": "oic",
                    "target_company": company_name,
                    "related_trip_id": trip_id,
                })

            if driver_uuid:
                _create_notification({
                    "title": "New Dispatch Assignment",
                    "message": f"You have been assigned to drive to {route_name} on {schedule_date}.",
                    "target_user_id": driver_uuid,
                    "target_role": "driver",
                    "target_company": company_name,
                    "related_trip_id": trip_id,
                })

        return jsonify({"success": True, "message": "Trip successfully dispatched!"}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500