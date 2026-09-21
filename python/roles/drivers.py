from flask import Blueprint, jsonify

drivers_bp = Blueprint('drivers', __name__)
supabase = None


@drivers_bp.route('/api/driver/all', methods=['GET'])
def get_all_drivers():
    try:
        res = supabase.table('driver_profile').select(
            'driver_id, full_name, birthday, phone_no, date_hired, '
            'employment_status, is_backup, ml_classification'
        ).limit(10000).execute()
        drivers = res.data or []

        return jsonify({
            "connection_status": "SUCCESS",
            "sample_data_payload": drivers
        }), 200

    except Exception as e:
        print(f"Driver List Fetch Exception: {e}")
        return jsonify({
            "connection_status": "FAILED",
            "error": str(e)
        }), 500
