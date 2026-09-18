from flask import Blueprint, jsonify, request

payroll_bp = Blueprint('payroll', __name__)
supabase = None


@payroll_bp.route('/api/payroll/context', methods=['GET'])
def get_payroll_context():
    try:
        start_date = request.args.get('start')
        end_date = request.args.get('end')

        drivers_res = (
            supabase.table('driver_profile')
            .select('driver_id, full_name, employment_status, phone_no')
            .order('full_name', desc=False)
            .execute()
        )

        attendance_query = supabase.table('attendance_record').select(
            'attendance_id, driver_id, employee_name, employee_id, work_date, '
            'raw_date, morning_in, morning_out, afternoon_in, afternoon_out, '
            'overtime_in, overtime_out, time_in, time_out, note, total_minutes_late'
        )
        trips_query = supabase.table('trip_schedule').select(
            'trip_id, driver_id, schedule_date, route_id, route_name'
        )

        if start_date:
            attendance_query = attendance_query.gte('work_date', start_date)
            trips_query = trips_query.gte('schedule_date', start_date)
        if end_date:
            attendance_query = attendance_query.lte('work_date', end_date)
            trips_query = trips_query.lte('schedule_date', end_date)

        attendance_res = attendance_query.order('work_date', desc=False).execute()
        trips_res = trips_query.order('schedule_date', desc=False).execute()
        destinations_res = (
            supabase.table('destination')
            .select('route_id, route_name, price')
            .order('route_name', desc=False)
            .execute()
        )

        destinations = destinations_res.data or []
        destinations_by_id = {
            str(destination.get('route_id')): destination
            for destination in destinations
            if destination.get('route_id') is not None
        }
        destinations_by_name = {
            str(destination.get('route_name') or '').strip().lower(): destination
            for destination in destinations
            if destination.get('route_name')
        }

        trips = []
        for trip in trips_res.data or []:
            destination = destinations_by_id.get(str(trip.get('route_id')))
            if destination is None:
                destination = destinations_by_name.get(
                    str(trip.get('route_name') or '').strip().lower()
                )
            trips.append({
                **trip,
                'destination_name': (destination or {}).get('route_name') or trip.get('route_name'),
                'destination_price': (destination or {}).get('price', 0),
            })

        return jsonify({
            "success": True,
            "drivers": drivers_res.data or [],
            "attendance": attendance_res.data or [],
            "trips": trips,
            "destinations": destinations,
        }), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500


@payroll_bp.route('/api/payroll/destination-rates', methods=['POST', 'PUT'])
def update_payroll_destination_rates():
    try:
        payload = request.get_json(silent=True) or {}
        rates = payload.get('rates') or []
        if not isinstance(rates, list):
            return jsonify({"success": False, "message": "Rates must be a list."}), 400

        saved = []
        for item in rates:
            if not isinstance(item, dict):
                continue
            route_id = item.get('route_id')
            route_name = str(item.get('route_name') or '').strip()
            try:
                price = float(item.get('price') or 0)
            except (TypeError, ValueError):
                price = 0.0

            if route_id:
                result = (
                    supabase.table('destination')
                    .update({'price': price})
                    .eq('route_id', route_id)
                    .execute()
                )
            elif route_name:
                result = (
                    supabase.table('destination')
                    .upsert({'route_name': route_name, 'price': price}, on_conflict='route_name')
                    .execute()
                )
            else:
                continue
            saved.extend(result.data or [])

        return jsonify({"success": True, "saved": saved}), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500
