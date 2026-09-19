from flask import Blueprint, request, jsonify
from datetime import datetime

evaluate_bp = Blueprint('evaluate', __name__)
supabase = None 

@evaluate_bp.route('/api/evaluate/driver/<int:driver_id>', methods=['GET'])
def get_driver_evaluations(driver_id):
    """Fetches all evaluations directly linked to a specific driver."""
    try:
        evals = supabase.table('evaluation').select('*').eq('driver_id', driver_id).order('submit_date', desc=True).execute()
        return jsonify({"success": True, "data": evals.data or []}), 200
    except Exception as e:
        print(f"❌ Fetch Evals Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@evaluate_bp.route('/api/evaluate/staff-submit', methods=['POST'])
def staff_submit_evaluation():
    """Allows Staff/Admin to evaluate a driver. Attaches automatically to their most recent trip."""
    try:
        data = request.get_json() or {}
        driver_id = data.get('driver_id')
        
        if not driver_id:
            return jsonify({"success": False, "message": "Driver ID is required."}), 400
            
        # Fetch latest trip to optionally attach context (if they have one)
        trip_query = supabase.table('trip_schedule').select('trip_id, vehicle_id').eq('driver_id', driver_id).order('schedule_date', desc=True).limit(1).execute()
        
        latest_trip_id = trip_query.data[0]['trip_id'] if trip_query.data else None
        latest_vehicle_id = trip_query.data[0]['vehicle_id'] if trip_query.data else None
        
        now = datetime.now()
        payload = {
            "submit_date": now.strftime("%Y-%m-%d"),
            "submit_time": now.strftime("%H:%M:%S"),
            "safety_score": data.get('safety_score', 5),
            "punctuality_score": data.get('punctuality_score', 5),
            "professionalism_score": data.get('professionalism_score', 5),
            "comments": data.get('comments', ''),
            "driver_id": driver_id,
            "trip_id": latest_trip_id,
            "vehicle_id": latest_vehicle_id
        }
        
        supabase.table('evaluation').insert(payload).execute()
        return jsonify({"success": True, "message": "Staff Evaluation submitted successfully!"}), 200
    except Exception as e:
        print(f"❌ Submit Eval Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500