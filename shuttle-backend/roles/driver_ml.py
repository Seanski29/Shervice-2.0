import numpy as np
from flask import Blueprint, jsonify
from sklearn.neighbors import KNeighborsClassifier
from sklearn.preprocessing import StandardScaler

driver_ml_bp = Blueprint('driver_ml', __name__)
supabase = None  

model = KNeighborsClassifier(n_neighbors=3)
scaler = StandardScaler()
is_trained = False

def train_driver_classification_model():
    """
    Trains a KNN model to classify driver behavior.
    Features: [Avg Safety, Avg Punctuality, Avg Professionalism, Total Trips]
    Target (y): Behavioral Category
    """
    global is_trained, model, scaler
    try:
        X_train = np.array([
            [4.8, 4.9, 4.8, 50],  
            [4.5, 4.7, 4.9, 15],  
            [4.2, 4.1, 4.3, 10],  
            [4.0, 4.0, 4.0, 25],  
            [3.8, 4.2, 4.1, 8],   
            [4.1, 4.4, 4.2, 35],  
            [2.1, 4.8, 3.5, 30],  
            [1.5, 4.5, 4.0, 10],  
            [4.6, 2.0, 4.5, 25],  
            [4.2, 1.5, 4.0, 40],  
            [4.5, 4.5, 1.8, 20],  
            [4.0, 4.2, 2.1, 15],  
            [2.5, 2.5, 2.5, 35],  
            [2.0, 2.0, 2.0, 10],  
        ])
        
        y_train = np.array([
            "Consistent Performer", "Consistent Performer",
            "Consistent Performer", "Consistent Performer", 
            "Consistent Performer", "Consistent Performer",
            "Aggressive Driving Risk", "Aggressive Driving Risk",
            "Tardiness Risk", "Tardiness Risk",
            "Unprofessional Conduct", "Unprofessional Conduct",
            "Needs Review", "Needs Review"
        ])
        
        X_scaled = scaler.fit_transform(X_train)
        model.fit(X_scaled, y_train)
        is_trained = True
        print("🤖 KNN Driver Classification Engine compiled successfully!")
    except Exception as e:
        print(f"❌ Driver ML Compiler Exception: {e}")

@driver_ml_bp.route('/api/drivers/classify/<string:driver_identifier>', methods=['GET'])
def classify_driver(driver_identifier):
    global is_trained, model, scaler
    
    if not is_trained:
        train_driver_classification_model()
        
    try:
        if not driver_identifier or driver_identifier == 'null' or driver_identifier == 'None':
             return jsonify({
                 "success": True, 
                 "classification": "Insufficient Data",
                 "message": "Invalid Driver ID."
             }), 200

        driver_id = None
        if str(driver_identifier).isdigit():
            driver_id = int(driver_identifier)
        else:
            profile_res = (
                supabase.table('driver_profile')
                .select('driver_id')
                .eq('user_id', driver_identifier)
                .limit(1)
                .execute()
            )
            if profile_res.data:
                driver_id = profile_res.data[0].get('driver_id')

        if driver_id is None:
             return jsonify({"success": True, "classification": "Insufficient Data"}), 200

        # 🔥 1. Get exact total trip volume for the ML Matrix
        trips_res = supabase.table('trip_schedule').select('trip_id').eq('driver_id', driver_id).execute()
        total_trips = len(trips_res.data) if trips_res.data else 0
        
        # 🔥 2. Get all staff evaluations for the driver
        evals_res = supabase.table('evaluation').select('safety_score, punctuality_score, professionalism_score').eq('driver_id', driver_id).execute()
        total_evals = len(evals_res.data) if evals_res.data else 0
        
        if total_evals < 3:
             # Save Insufficient Data status to DB so it clears "Pending Sweep"
             supabase.table('driver_profile').update({"ml_classification": "Insufficient Data"}).eq('driver_id', driver_id).execute()
             return jsonify({
                 "success": True, 
                 "classification": "Insufficient Data",
                 "evaluations_count": total_evals
             }), 200

        total_safety = sum(float(e.get('safety_score') or 5.0) for e in evals_res.data)
        total_punct = sum(float(e.get('punctuality_score') or 5.0) for e in evals_res.data)
        total_prof = sum(float(e.get('professionalism_score') or 5.0) for e in evals_res.data)
        
        avg_safety = total_safety / total_evals
        avg_punct = total_punct / total_evals
        avg_prof = total_prof / total_evals
        
        # 🔥 ML EXECUTION: Matrix relies on Trip Volume, NOT Evaluation Volume
        live_features = np.array([[avg_safety, avg_punct, avg_prof, total_trips]])
        scaled_features = scaler.transform(live_features)
        
        predicted_class = str(model.predict(scaled_features)[0])
        
        # Save the answer to Supabase
        supabase.table('driver_profile').update({
            "ml_classification": predicted_class
        }).eq('driver_id', driver_id).execute()
        
        return jsonify({
            "success": True,
            "classification": predicted_class,
            "metrics": {
                "avg_safety": round(avg_safety, 2),
                "avg_punctuality": round(avg_punct, 2),
                "avg_professionalism": round(avg_prof, 2),
                "total_trips": total_trips,
                "total_evaluations": total_evals
            }
        }), 200

    except Exception as e:
        print(f"CLASSIFICATION ERROR FOR {driver_identifier}: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@driver_ml_bp.route('/api/drivers/sweep', methods=['POST', 'GET'])
def sweep_all_drivers():
    global is_trained, model, scaler, supabase
    if not is_trained:
        train_driver_classification_model()

    try:
        # Import supabase dynamically from app if it was unassigned
        if supabase is None:
            pass

        drivers_res = supabase.table('driver_profile').select('driver_id').limit(5000).execute()
        driver_ids = [d['driver_id'] for d in drivers_res.data if d.get('driver_id') is not None] if drivers_res.data else []

        updated_count = 0
        for d_id in driver_ids:
            try:
                classify_driver(d_id)
                updated_count += 1
            except Exception as inner_e:
                print(f"⚠️ Skipped {d_id} during sweep: {inner_e}")

        return jsonify({
            "success": True, 
            "message": f"Successfully swept and updated {updated_count} drivers."
        }), 200

    except Exception as e:
        print(f"🚨 BULK SWEEP ERROR: {e}")
        return jsonify({"success": False, "message": str(e)}), 500