from flask import Blueprint, request, jsonify, render_template
import datetime

passenger_bp = Blueprint('passenger', __name__)
supabase = None 

@passenger_bp.route('/evaluate', methods=['GET'])
def passenger_evaluation_page():
    """Serves the HTML page when the passenger scans the QR code"""
    trip_id = request.args.get('trip_id')
    
    if not trip_id:
        return "Invalid QR Code: Missing Trip ID", 400
        
    # FETCH THE DRIVER's NAME
    driver_name = "Your Driver"
    try:
        # 1. Find the user_id (driver) assigned to this trip
        trip_query = supabase.table('trip_schedule').select('user_id').eq('trip_id', trip_id).execute()
        
        if trip_query.data and trip_query.data[0].get('user_id'):
            driver_uuid = trip_query.data[0].get('user_id')
            
            # 2. Look up the driver's full name in the driver_profile table
            driver_query = supabase.table('driver_profile').select('full_name').eq('user_id', driver_uuid).execute()
            if driver_query.data:
                driver_name = driver_query.data[0].get('full_name')
                
    except Exception as e:
        print(f"Error fetching driver name: {e}")
        
    # Pass BOTH the trip_id and driver_name to the HTML file
    return render_template('passenger_evaluation.html', trip_id=trip_id, driver_name=driver_name)


@passenger_bp.route('/api/evaluate/submit', methods=['POST'])
def submit_passenger_evaluation():
    """Receives the 5-star rating data and comments from the web page"""
    try:
        data = request.get_json()
        trip_id = data.get('trip_id')
        
        # 1. Fetch the vehicle_id associated with this trip
        trip_query = supabase.table('trip_schedule').select('vehicle_id').eq('trip_id', trip_id).execute()
        
        if not trip_query.data:
            return jsonify({"success": False, "message": "Trip not found"}), 404
            
        vehicle_id = trip_query.data[0].get('vehicle_id')
        
        # 2. Prepare the data for insertion (Now including comments!)
        current_date = datetime.datetime.now().strftime('%Y-%m-%d')
        current_time = datetime.datetime.now().strftime('%H:%M:%S')
        
        insert_payload = {
            "trip_id": trip_id,
            "vehicle_id": vehicle_id,
            "submit_date": current_date,
            "submit_time": current_time,
            "punctuality_score": data.get('punctuality_score'),
            "safety_score": data.get('safety_score'),
            "professionalism_score": data.get('professionalism_score'),
            "comments": data.get('comments', '') # Save the comments (or empty string if none)
        }
        
        # 3. Insert into database
        supabase.table('passenger_evaluation').insert(insert_payload).execute()
        
        return jsonify({"success": True, "message": "Thank you for your feedback!"}), 200
        
    except Exception as e:
        print(f"❌ Evaluation Submit Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@passenger_bp.route('/api/evaluate/driver/<string:driver_uuid>', methods=['GET'])
def get_driver_evaluations(driver_uuid):
    """Fetches all passenger evaluations for a specific driver."""
    try:
        # 1. Find all trips that belong to this driver
        trips = supabase.table('trip_schedule').select('trip_id').eq('user_id', driver_uuid).execute()
        
        # If the driver has no trips yet, return an empty list safely
        if not trips.data:
            return jsonify({"success": True, "data": []}), 200
            
        trip_ids = [t['trip_id'] for t in trips.data]

        # 2. Fetch all passenger evaluations linked to those specific trip IDs
        evals = supabase.table('passenger_evaluation').select('*').in_('trip_id', trip_ids).execute()
        
        return jsonify({"success": True, "data": evals.data}), 200
        
    except Exception as e:
        print(f"❌ Fetch Driver Eval Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500