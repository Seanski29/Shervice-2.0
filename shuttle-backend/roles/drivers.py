from flask import Blueprint, jsonify, request

drivers_bp = Blueprint('drivers', __name__)
supabase = None

@drivers_bp.route('/api/driver/all', methods=['GET'])
def get_all_drivers():
    try:
        res = supabase.table('driver_profile')\
            .select('*, user_account(username)')\
            .execute()

        drivers = res.data or []
        for driver in drivers:
            account = driver.pop('user_account', None) or {}
            driver['username'] = account.get('username', '')

        return jsonify({
            "connection_status": "SUCCESS",
            "sample_data_payload": drivers
        }), 200

    except Exception as e:
        print(f"❌ Driver List Fetch Exception: {e}")
        return jsonify({
            "connection_status": "FAILED",
            "error": str(e)
        }), 500

@drivers_bp.route('/api/driver/active-trip/<driver_name>', methods=['GET'])
def get_driver_active_trip(driver_name):
    try:
        driver_res = supabase.table('driver_profile')\
            .select('user_id')\
            .ilike('full_name', driver_name)\
            .maybe_single()\
            .execute()
            
        driver_data = driver_res.data
        if not driver_data:
            return jsonify({"success": True, "active_trip": None}), 200
            
        user_uuid = driver_data.get('user_id')

        trip_res = supabase.table('trip_schedule').select(
            '*, vehicle(*)'
        ).eq('user_id', user_uuid)\
         .in_('trip_status', ['Ongoing', 'Scheduled'])\
         .order('schedule_date', desc=False)\
         .limit(1)\
         .maybe_single()\
         .execute()
         
        trip = trip_res.data
        if not trip:
            return jsonify({"success": True, "active_trip": None}), 200

        vehicle_info = trip.get('vehicle') or {}
        
        formatted_trip = {
            'trip_id': trip.get('trip_id'),
            'status': trip.get('trip_status', 'Scheduled').upper(),
            'route_name': trip.get('route_name', 'Route Unassigned'),
            'departure_time': str(trip.get('departure_time'))[:5] if trip.get('departure_time') else '--:--',
            'estimated_arrival_time': str(trip.get('estimated_arrival_time'))[:5] if trip.get('estimated_arrival_time') else '--:--',
            'passenger_count': trip.get('passenger_count', 0),
            'route_distance': trip.get('route_distance', 0.0),
            'actual_start_time': trip.get('actual_start_time'), 
            'actual_end_time': trip.get('actual_end_time'),     
            'plate_number': vehicle_info.get('plate_number', 'No Plate Assigned'),
        }

        return jsonify({"success": True, "active_trip": formatted_trip}), 200
        
    except Exception as e:
        print(f"❌ Driver Active Trip Sync Exception: {e}")
        return jsonify({"success": False, "error": str(e)}), 500