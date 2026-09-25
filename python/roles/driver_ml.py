import os
import joblib
import pandas as pd
import numpy as np
from flask import Blueprint, jsonify, request
from sklearn.neighbors import KNeighborsClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

# 1. Initialize the Flask Blueprint
driver_ml_bp = Blueprint('driver_ml', __name__)
supabase = None  

# Global ML state variables
model = None
scaler = None
is_trained = False


def _fetch_all(table_name, columns, batch_size=1000):
    """Fetch every row instead of relying on Supabase's default page size."""
    rows = []
    offset = 0
    while True:
        batch = (
            supabase.table(table_name)
            .select(columns)
            .range(offset, offset + batch_size - 1)
            .execute()
            .data
            or []
        )
        rows.extend(batch)
        if len(batch) < batch_size:
            return rows
        offset += batch_size

def fetch_and_prepare_data():
    """
    Fetches raw data and aggregates 8 features per driver, parsing attendance notes.
    """
    global supabase
    
    # 1. Fetch Drivers
    drivers_df = pd.DataFrame(_fetch_all('driver_profile', 'driver_id'))
    
    # 2. Fetch Evaluations
    evals_df = pd.DataFrame(_fetch_all(
        'evaluation',
        'driver_id, safety_score, punctuality_score, professionalism_score',
    ))
    
    if not evals_df.empty:
        evals_agg = evals_df.groupby('driver_id').agg({
            'safety_score': 'mean',
            'punctuality_score': 'mean',
            'professionalism_score': 'mean'
        }).reset_index()
    else:
        evals_agg = pd.DataFrame(columns=['driver_id', 'safety_score', 'punctuality_score', 'professionalism_score'])

    # 3. Fetch Trip Counts
    trips_df = pd.DataFrame(_fetch_all('trip_schedule', 'driver_id, trip_id'))
    
    if not trips_df.empty:
        trips_agg = trips_df.groupby('driver_id').size().reset_index(name='trips_amount')
    else:
        trips_agg = pd.DataFrame(columns=['driver_id', 'trips_amount'])

    # 4. Fetch Attendance & Extract Present/Absent/Half-Day
    att_df = pd.DataFrame(_fetch_all(
        'attendance_record',
        'driver_id, total_minutes_late, note',
    ))
    
    if not att_df.empty:
        # Standardize notes for text matching
        att_df['note'] = att_df['note'].fillna('').astype(str).str.lower()
        
        # Categorize attendance types
        att_df['absent_count'] = att_df['note'].str.contains('absent').astype(int)
        att_df['half_day_count'] = att_df['note'].str.contains('half day').astype(int)
        att_df['present_count'] = ((att_df['absent_count'] == 0) & (att_df['half_day_count'] == 0)).astype(int)
        
        # Aggregate totals per driver
        att_agg = att_df.groupby('driver_id').agg({
            'total_minutes_late': 'sum',
            'present_count': 'sum',
            'half_day_count': 'sum',
            'absent_count': 'sum'
        }).reset_index()
    else:
        att_agg = pd.DataFrame(columns=['driver_id', 'total_minutes_late', 'present_count', 'half_day_count', 'absent_count'])

    # 5. Merge all features
    df = drivers_df.merge(evals_agg, on='driver_id', how='left')
    df = df.merge(trips_agg, on='driver_id', how='left')
    df = df.merge(att_agg, on='driver_id', how='left')

    # Fill missing data safely
    df.fillna({
        'safety_score': 5.0,
        'punctuality_score': 5.0,
        'professionalism_score': 5.0,
        'trips_amount': 0,
        'total_minutes_late': 0,
        'present_count': 0,
        'half_day_count': 0,
        'absent_count': 0
    }, inplace=True)

    return df

def generate_ground_truth_labels(row):
    safety = row['safety_score']
    punctuality = row['punctuality_score']
    professionalism = row['professionalism_score']
    late_mins = row['total_minutes_late']
    absences = row['absent_count']
    present = row['present_count']
    
    # 1. Critical fail conditions
    if absences >= 3 or late_mins > 60 or punctuality < 3.0:
        return 'Tardiness Risk'
        
    # 2. Safety fail conditions
    elif safety < 3.5:
        return 'Safety Risk'
        
    # 3. High performer conditions (Now requires high professionalism AND actual attendance data)
    elif safety >= 4.5 and punctuality >= 4.5 and professionalism >= 4.0 and late_mins <= 15 and absences == 0 and present > 0:
        return 'Elite Performer'

    # 4. Consistent drivers: reliable attendance and performance, but not
    # enough safety score to qualify for the Elite tier.
    elif (
        safety >= 4.0
        and punctuality >= 4.0
        and professionalism >= 4.0
        and late_mins <= 30
        and absences == 0
        and present > 0
        and row['trips_amount'] > 0
    ):
        return 'Consistent Performer'
        
    # 5. Default middle-ground
    else:
        return 'Needs Review'
def train_driver_classification_model():
    """
    Trains the KNN Model and updates Supabase.
    """
    global model, scaler, is_trained, supabase

    print("Fetching data and engineering 8 features for KNN...")
    df = fetch_and_prepare_data()
    
    if len(df) < 5:
        print("Not enough data to train KNN reliably.")
        return False

    df['target_label'] = df.apply(generate_ground_truth_labels, axis=1)

    # The 8 explicit features for classification
    feature_cols = [
        'safety_score', 
        'punctuality_score', 
        'professionalism_score', 
        'trips_amount', 
        'total_minutes_late',
        'present_count',
        'half_day_count',
        'absent_count'
    ]
    
    X = df[feature_cols]
    y = df['target_label']

    # Scale the features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    # Keep a holdout only for reporting. The serving model is fitted on all
    # available drivers so every current driver receives a classification.
    X_train, X_test, y_train, y_test = train_test_split(
        X_scaled, y, test_size=0.2, random_state=42
    )

    # Initialize and Train KNN
    evaluation_model = KNeighborsClassifier(n_neighbors=3, weights='distance')
    evaluation_model.fit(X_train, y_train)
    
    y_pred = evaluation_model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    print(f"\n--- Model Training Complete ---")
    print(f"KNN Accuracy Score: {accuracy * 100:.2f}%")
    print("\nClassification Report:\n", classification_report(y_test, y_pred, zero_division=0))

    # Refit the serving model on the complete driver dataset. This prevents
    # the 20% holdout from receiving a classification based on incomplete
    # neighborhood information.
    model = KNeighborsClassifier(n_neighbors=3, weights='distance')
    model.fit(X_scaled, y)

    # Predict entire fleet
    df['ml_classification'] = model.predict(X_scaled)
    
    # Save models
    os.makedirs('models', exist_ok=True)
    joblib.dump(model, 'models/knn_driver_model.pkl')
    joblib.dump(scaler, 'models/knn_scaler.pkl')
    is_trained = True

    # Update database
    print("Updating database with new classifications...")
    for index, row in df.iterrows():
        try:
            supabase.table('driver_profile').update({
                'ml_classification': row['ml_classification']
            }).eq('driver_id', row['driver_id']).execute()
        except Exception as e:
            print(f"Failed to update driver {row['driver_id']}: {e}")

    return True

@driver_ml_bp.route('/drivers/classify/<driver_id>', methods=['GET'])
@driver_ml_bp.route('/api/drivers/classify/<driver_id>', methods=['GET'])
def classify_driver(driver_id):
    """
    Returns the assigned classification for a single driver.
    """
    global is_trained, supabase
    try:
        # Rebuild on an explicit refresh so newly added trip summaries are
        # included in the trips_amount feature instead of using stale model
        # classifications from an earlier data snapshot.
        if not is_trained or request.args.get('refresh') == '1':
            train_driver_classification_model()
            
        res = supabase.table('driver_profile').select('ml_classification').eq('driver_id', driver_id).execute()
        
        if res.data and len(res.data) > 0:
            classification = res.data[0].get('ml_classification') or 'Needs Review'
            return jsonify({"success": True, "classification": classification}), 200
            
        return jsonify({"success": False, "classification": "Unknown Driver"}), 404

    except Exception as e:
        print(f"❌ ML Classification fetch error for driver {driver_id}: {e}")
        return jsonify({"success": False, "error": str(e), "classification": "Analysis Failed"}), 500
