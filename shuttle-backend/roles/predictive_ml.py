import numpy as np
from flask import Blueprint, request, jsonify
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import StandardScaler

predictive_bp = Blueprint('predictive_ml', __name__)
supabase = None  

model = LinearRegression()
scaler = StandardScaler()
is_trained = False

def train_baseline_model():
    """
    Trains a Multiple Linear Regression model to forecast maintenance cycles.
    Features: [Total Mileage (km), Vehicle Age (Years), Trip Count, Past Repair Count]
    """
    global is_trained, model, scaler
    try:
        X_train = np.array([
            [85000, 8, 120, 14],  
            [12000, 1, 15,  1],   
            [62000, 5, 95,  8],   
            [22000, 2, 40,  2],   
            [110000, 9, 180, 22], 
            [5000,  1, 8,   0],   
            [71000, 6, 110, 11],  
            [35000, 3, 55,  3],   
            [0, 10, 0, 0],        
            [40000, 8, 60, 4]     
        ])
        
        y_train = np.array([
            12.0, 310.0, 45.0, 240.0, 2.0, 350.0, 25.0, 180.0,
            280.0, 
            140.0  
        ])
        
        X_scaled = scaler.fit_transform(X_train)
        model.fit(X_scaled, y_train)
        is_trained = True
        print("🧠 Multiple Linear Regression Engine compiled successfully!")
    except Exception as e:
        print(f"❌ ML Engine Compiler Exception: {e}")

@predictive_bp.route('/api/vehicles/predict/<int:vehicle_id>', methods=['GET'])
def predict_maintenance_risk(vehicle_id):
    global is_trained, model, scaler
    
    if not is_trained:
        train_baseline_model()
        
    try:
        vehicle_res = supabase.table('vehicle').select('*').eq('vehicle_id', vehicle_id).execute()
        if not vehicle_res.data:
            return jsonify({"success": False, "message": "Vehicle asset not found."}), 404
        vehicle = vehicle_res.data[0]

        current_year = 2026
        try: age = float(current_year - int(vehicle.get('model_year', current_year)))
        except ValueError: age = 2.0

        trips_res = supabase.table('trip_schedule').select('route_distance').eq('vehicle_id', vehicle_id).eq('trip_status', 'Completed').execute()
        trip_count = len(trips_res.data) if trips_res.data else 0
        total_mileage = sum(float(t.get('route_distance', 0.0)) for t in trips_res.data) if trips_res.data else 0.0

        logs_res = supabase.table('maintenance_log').select('source: maintenance_id').eq('vehicle_id', vehicle_id).execute()
        past_repairs = len(logs_res.data) if logs_res.data else 0

        live_features = np.array([[total_mileage, age, trip_count, past_repairs]])
        scaled_features = scaler.transform(live_features)
        
        predicted_days = float(model.predict(scaled_features)[0])
        predicted_days = max(0.0, round(predicted_days, 1)) 
        
        # 🛡️ BULLETPROOF BOOLEAN PARSER
        raw_is_avail = vehicle.get('is_available')
        is_active = True
        if raw_is_avail is False or str(raw_is_avail).lower() == 'false':
            is_active = False

        update_payload = {"risk_score": predicted_days}
        
        if predicted_days <= 7.0:
            if is_active:
                update_payload["is_available"] = False
                update_payload["last_maintenance_description"] = f"⚠️ ML FORECAST: Structural maintenance required within {predicted_days} days."
            update_payload["health_status"] = "Needs Maintenance"
        else:
            # STRICT Auto-Heal: Only touch health_status if the vehicle is actively cleared for dispatch
            if is_active:
                if predicted_days > 90.0:
                    update_payload["health_status"] = "Excellent"
                elif predicted_days > 30.0:
                    update_payload["health_status"] = "Good"
                else:
                    update_payload["health_status"] = "Fair"

        supabase.table('vehicle').update(update_payload).eq('vehicle_id', vehicle_id).execute()

        return jsonify({
            "success": True,
            "vehicle_id": vehicle_id,
            "plate_number": vehicle.get('plate_number'),
            "risk_index": predicted_days, 
            "telemetry_metrics": {
                "total_mileage_km": total_mileage,
                "age_years": age,
                "total_trips": trip_count,
                "past_repairs_count": past_repairs
            }
        }), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@predictive_bp.route('/api/vehicles/predict/fleet-sweep', methods=['POST', 'GET'])
def evaluate_entire_fleet():
    global is_trained, model, scaler
    
    if not is_trained:
        train_baseline_model()
        
    try:
        vehicles_res = supabase.table(
            'vehicle'
        ).select('vehicle_id, model_year, is_available, plate_number').execute()
        if not vehicles_res.data:
            return jsonify({"success": True, "message": "No vehicles found."}), 200

        # PERF: Replace 2 queries per vehicle with two fleet-wide reads and O(1)
        # in-memory aggregation; prediction and update semantics remain unchanged.
        completed_trips_res = supabase.table('trip_schedule').select(
            'vehicle_id, route_distance'
        ).eq('trip_status', 'Completed').execute()
        repairs_res = supabase.table('maintenance_log').select(
            'vehicle_id, maintenance_id'
        ).execute()

        trip_totals = {}
        for trip in completed_trips_res.data or []:
            vehicle_id = trip.get('vehicle_id')
            if vehicle_id is None:
                continue
            totals = trip_totals.setdefault(vehicle_id, [0.0, 0])
            totals[0] += float(trip.get('route_distance') or 0.0)
            totals[1] += 1

        repair_counts = {}
        for repair in repairs_res.data or []:
            vehicle_id = repair.get('vehicle_id')
            if vehicle_id is not None:
                repair_counts[vehicle_id] = repair_counts.get(vehicle_id, 0) + 1
            
        flagged_assets = []
        
        for vehicle in vehicles_res.data:
            vehicle_id = vehicle['vehicle_id']
            
            current_year = 2026
            try: age = float(current_year - int(vehicle.get('model_year', current_year)))
            except ValueError: age = 2.0
                
            trip_totals_for_vehicle = trip_totals.get(vehicle_id, (0.0, 0))
            total_mileage = trip_totals_for_vehicle[0]
            trip_count = trip_totals_for_vehicle[1]
            past_repairs = repair_counts.get(vehicle_id, 0)
            
            live_features = np.array([[total_mileage, age, trip_count, past_repairs]])
            scaled_features = scaler.transform(live_features)
            
            predicted_days = float(model.predict(scaled_features)[0])
            predicted_days = max(0.0, round(predicted_days, 1))

            # 🛡️ BULLETPROOF BOOLEAN PARSER
            raw_is_avail = vehicle.get('is_available')
            is_active = True
            if raw_is_avail is False or str(raw_is_avail).lower() == 'false':
                is_active = False

            update_payload = {"risk_score": predicted_days}
            
            if predicted_days <= 7.0:
                if is_active:
                    update_payload["is_available"] = False
                    update_payload["last_maintenance_description"] = f"⚠️ ML FORECAST: Background sweep triggered lockout. Maintenance due in {predicted_days} days."
                    flagged_assets.append({"plate": vehicle.get('plate_number'), "forecast_days": predicted_days})
                update_payload["health_status"] = "Needs Maintenance"
            else:
                # STRICT Auto-Heal
                if is_active:
                    if predicted_days > 90.0:
                        update_payload["health_status"] = "Excellent"
                    elif predicted_days > 30.0:
                        update_payload["health_status"] = "Good"
                    else:
                        update_payload["health_status"] = "Fair"

            supabase.table('vehicle').update(update_payload).eq('vehicle_id', vehicle_id).execute()
                
        return jsonify({
            "success": True,
            "message": "Fleet ML sweep complete.",
            "total_evaluated": len(vehicles_res.data),
            "newly_flagged_count": len(flagged_assets),
            "flagged_assets": flagged_assets
        }), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500