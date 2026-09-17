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

@driver_ml_bp.route('/api/drivers/classify/<string:driver_uuid>', methods=['GET'])
def classify_driver(driver_uuid):
    global is_trained, model, scaler
    
    if not is_trained:
        train_driver_classification_model()
        
    try:
        if not driver_uuid or driver_uuid == 'null' or driver_uuid == 'None':
             return jsonify({
                 "success": True, 
                 "classification": "Insufficient Data",
                 "message": "Invalid Driver ID."
             }), 200

        trips_res = supabase.table('trip_schedule').select('trip_id').eq('user_id', driver_uuid).execute()
        
        if not trips_res.data:
             return jsonify({
                 "success": True, 
                 "classification": "Insufficient Data",
                 "message": "Driver has no completed trips."
             }), 200
             
        trip_ids = [t['trip_id'] for t in trips_res.data if t.get('trip_id')]
        
        if not trip_ids:
             return jsonify({"success": True, "classification": "Insufficient Data"}), 200
        
        evals_res = supabase.table('passenger_evaluation').select('safety_score, punctuality_score, professionalism_score').in_('trip_id', trip_ids).execute()
        
        total_evals = len(evals_res.data) if evals_res.data else 0
        
        if total_evals < 3:
             # Save Insufficient Data status to DB so it clears "Pending Sweep"
             supabase.table('driver_profile').update({"ml_classification": "Insufficient Data"}).eq('user_id', driver_uuid).execute()
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
        
        live_features = np.array([[avg_safety, avg_punct, avg_prof, total_evals]])
        scaled_features = scaler.transform(live_features)
        
        predicted_class = str(model.predict(scaled_features)[0])
        
        # 🔥 THE MISSING PIECE: SAVE THE ANSWER TO SUPABASE 🔥
        supabase.table('driver_profile').update({
            "ml_classification": predicted_class
        }).eq('user_id', driver_uuid).execute()
        
        return jsonify({
            "success": True,
            "classification": predicted_class,
            "metrics": {
                "avg_safety": round(avg_safety, 2),
                "avg_punctuality": round(avg_punct, 2),
                "avg_professionalism": round(avg_prof, 2),
                "total_evaluations": total_evals
            }
        }), 200

    except Exception as e:
        print(f"🚨 CLASSIFICATION ERROR FOR {driver_uuid}: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

# ---------------------------------------------------------
# NEW: BULK SWEEP ROUTE
# This allows your Flutter "Run AI Sweep" button to evaluate 
# all 41+ drivers in one single fast swoop without crashing.
# ---------------------------------------------------------
@driver_ml_bp.route('/api/drivers/sweep', methods=['POST', 'GET'])
def sweep_all_drivers():
    global is_trained, model, scaler, supabase
    if not is_trained:
        train_driver_classification_model()

    try:
        # Import supabase dynamically from app if it was unassigned
        if supabase is None:
            from flask import current_app
            # If your main app stores supabase globally or in extensions, reference it here, 
            # or ensure it's imported from your main app file e.g.: from app import supabase
            pass

        drivers_res = supabase.table('driver_profile').select('user_id').limit(5000).execute()
        driver_ids = [d['user_id'] for d in drivers_res.data] if drivers_res.data else []

        updated_count = 0
        for d_id in driver_ids:
            try:
                # Call classify logic directly and save
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