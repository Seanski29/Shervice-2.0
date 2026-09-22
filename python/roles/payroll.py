from flask import Blueprint, jsonify, request
import re

payroll_bp = Blueprint('payroll', __name__)
supabase = None


def _route_key(route_name):
    return re.sub(r'\s+', ' ', str(route_name or '').strip()).lower()


def _canonical_route_name(route_name):
    clean_name = re.sub(r'\s+', ' ', str(route_name or '').strip())
    return clean_name or 'Unspecified Route'


def _payroll_settings():
    result = (
        supabase.table('payroll_settings')
        .select('regular_pay, half_day_deduction, absent_deduction, overtime_pay')
        .eq('setting_key', 'default')
        .limit(1)
        .execute()
    )
    return (result.data or [{}])[0]


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
        trips = []
        for trip in trips_res.data or []:
            destination = destinations_by_id.get(str(trip.get('route_id')))
            trips.append({
                **trip,
                'destination_name': (destination or {}).get('route_name') or trip.get('route_name'),
                'destination_price': (destination or {}).get('price', 0),
            })

        return jsonify({
            "success": True,
            "settings": _payroll_settings(),
            "drivers": drivers_res.data or [],
            "attendance": attendance_res.data or [],
            "trips": trips,
            "destinations": destinations,
        }), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500


@payroll_bp.route('/api/payroll/settings', methods=['PUT'])
def update_payroll_settings():
    try:
        payload = request.get_json(silent=True) or {}
        field_names = (
            'regular_pay',
            'half_day_deduction',
            'absent_deduction',
            'overtime_pay',
        )
        settings = {}
        for field_name in field_names:
            value = float(payload.get(field_name))
            if value < 0 or value != value or value == float('inf'):
                raise ValueError
            settings[field_name] = round(value, 2)
    except (TypeError, ValueError):
        return jsonify({
            "success": False,
            "message": "Payroll rates must be non-negative numbers.",
        }), 400

    try:
        result = (
            supabase.table('payroll_settings')
            .upsert({'setting_key': 'default', **settings}, on_conflict='setting_key')
            .execute()
        )
        return jsonify({"success": True, "settings": (result.data or [settings])[0]}), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500


@payroll_bp.route('/api/payroll/destinations/<int:route_id>', methods=['DELETE'])
def delete_payroll_destination(route_id):
    try:
        trips = supabase.table('trip_schedule').select('trip_id').eq('route_id', route_id).limit(1).execute().data or []
        if trips:
            return jsonify({
                "success": False,
                "message": "This route is already used by trips and cannot be deleted.",
            }), 409

        destination = (
            supabase.table('destination')
            .select('route_id, route_name')
            .eq('route_id', route_id)
            .maybe_single()
            .execute()
        )
        if not destination.data:
            return jsonify({"success": False, "message": "Destination not found."}), 404

        deleted = supabase.table('destination').delete().eq('route_id', route_id).execute()

        return jsonify({
            "success": True,
            "deleted": deleted.data or [],
            "message": "Destination deleted.",
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
            route_name = _canonical_route_name(item.get('route_name'))
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
                all_destinations = supabase.table('destination').select('route_id, route_name').execute()
                matched = None
                for destination in all_destinations.data or []:
                    if _route_key(destination.get('route_name')) == _route_key(route_name):
                        matched = destination
                        break
                if matched:
                    result = (
                        supabase.table('destination')
                        .update({'price': price})
                        .eq('route_id', matched.get('route_id'))
                        .execute()
                    )
                else:
                    result = (
                        supabase.table('destination')
                        .insert({'route_name': route_name, 'price': price})
                        .execute()
                    )
            else:
                continue
            saved.extend(result.data or [])

        return jsonify({"success": True, "saved": saved}), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500


@payroll_bp.route('/api/routes', methods=['GET'])
def get_routes():
    try:
        destinations = (
            supabase.table('destination')
            .select('route_id, route_name, price')
            .order('route_name', desc=False)
            .execute()
            .data or []
        )
        trips = supabase.table('trip_schedule').select('route_id').execute().data or []
        trip_counts = {}
        for trip in trips:
            route_id = trip.get('route_id')
            if route_id is not None:
                trip_counts[str(route_id)] = trip_counts.get(str(route_id), 0) + 1
        for destination in destinations:
            destination['trip_count'] = trip_counts.get(str(destination.get('route_id')), 0)
        return jsonify({"success": True, "data": destinations}), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500


@payroll_bp.route('/api/routes', methods=['POST'])
def create_route():
    try:
        payload = request.get_json(silent=True) or {}
        route_name = _canonical_route_name(payload.get('route_name'))
        price = float(payload.get('price') or 0)

        existing = supabase.table('destination').select('route_id, route_name').execute().data or []
        for destination in existing:
            if _route_key(destination.get('route_name')) == _route_key(route_name):
                return jsonify({"success": False, "message": "Route already exists."}), 409

        result = supabase.table('destination').insert({
            'route_name': route_name,
            'price': price,
        }).execute()
        return jsonify({"success": True, "data": result.data or []}), 201
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500


@payroll_bp.route('/api/routes/<int:route_id>', methods=['PUT'])
def update_route(route_id):
    try:
        payload = request.get_json(silent=True) or {}
        route_name = _canonical_route_name(payload.get('route_name'))
        price = float(payload.get('price') or 0)

        existing = supabase.table('destination').select('route_id, route_name').execute().data or []
        for destination in existing:
            if int(destination.get('route_id')) != route_id and _route_key(destination.get('route_name')) == _route_key(route_name):
                return jsonify({"success": False, "message": "Another route already uses that name."}), 409

        result = supabase.table('destination').update({
            'route_name': route_name,
            'price': price,
        }).eq('route_id', route_id).execute()
        supabase.table('trip_schedule').update({'route_name': route_name}).eq('route_id', route_id).execute()
        return jsonify({"success": True, "data": result.data or []}), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500


@payroll_bp.route('/api/routes/<int:route_id>', methods=['DELETE'])
def delete_route(route_id):
    try:
        trips = supabase.table('trip_schedule').select('trip_id').eq('route_id', route_id).limit(1).execute().data or []
        if trips:
            return jsonify({
                "success": False,
                "message": "This route is already used by trips and cannot be deleted.",
            }), 409
        result = supabase.table('destination').delete().eq('route_id', route_id).execute()
        return jsonify({"success": True, "data": result.data or []}), 200
    except Exception as exc:
        return jsonify({"success": False, "message": str(exc)}), 500
