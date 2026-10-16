from flask import Blueprint, jsonify
from .errors import internal_error

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

    except Exception:
        return internal_error("Unable to load drivers.", connection_status="FAILED")
