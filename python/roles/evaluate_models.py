import os
import pandas as pd
import numpy as np
from datetime import datetime
from dotenv import load_dotenv
from sklearn.cluster import KMeans
from sklearn.linear_model import LinearRegression
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    mean_absolute_error,
    mean_squared_error,
    precision_score,
    r2_score,
    recall_score,
    silhouette_score,
)
from sklearn.model_selection import train_test_split
from sklearn.neighbors import KNeighborsClassifier
from sklearn.preprocessing import StandardScaler
from supabase import create_client

load_dotenv()
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY") or os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise ValueError("Missing Supabase credentials in .env file!")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# --- Bootstrapping rule for KNN matching driver_ml.py ---
def generate_ground_truth_labels(row):
    safety = row['safety_score']
    punctuality = row['punctuality_score']
    professionalism = row['professionalism_score']
    late_mins = row['total_minutes_late']
    absences = row['absent_count']
    present = row['present_count']
    
    if absences >= 3 or late_mins > 60 or punctuality < 3.0:
        return 'Tardiness Risk'
    elif safety < 3.5:
        return 'Safety Risk'
    elif safety >= 4.5 and punctuality >= 4.5 and professionalism >= 4.0 and late_mins <= 15 and absences == 0 and present > 0:
        return 'Elite Performer'
    else:
        return 'Needs Review'

def evaluate_objective_3_1_knn():
    print("\n=======================================================")
    print("OBJECTIVE 3.1: DRIVER CLASSIFICATION (KNN) EVALUATION")
    print("=======================================================")

    drivers_res = supabase.table('driver_profile').select('driver_id').execute()
    drivers_df = pd.DataFrame(drivers_res.data or [])
    
    evals_res = supabase.table('evaluation').select('driver_id, safety_score, punctuality_score, professionalism_score').execute()
    evals_df = pd.DataFrame(evals_res.data or [])
    
    if not evals_df.empty:
        evals_agg = evals_df.groupby('driver_id').mean().reset_index()
    else:
        evals_agg = pd.DataFrame(columns=['driver_id', 'safety_score', 'punctuality_score', 'professionalism_score'])

    trips_res = supabase.table('trip_schedule').select('driver_id, trip_id').execute()
    trips_df = pd.DataFrame(trips_res.data or [])
    
    if not trips_df.empty:
        trips_agg = trips_df.groupby('driver_id').size().reset_index(name='trips_amount')
    else:
        trips_agg = pd.DataFrame(columns=['driver_id', 'trips_amount'])

    att_res = supabase.table('attendance_record').select('driver_id, total_minutes_late, note').execute()
    att_df = pd.DataFrame(att_res.data or [])
    
    if not att_df.empty:
        att_df['note'] = att_df['note'].fillna('').astype(str).str.lower()
        att_df['absent_count'] = att_df['note'].str.contains('absent').astype(int)
        att_df['half_day_count'] = att_df['note'].str.contains('half day').astype(int)
        att_df['present_count'] = ((att_df['absent_count'] == 0) & (att_df['half_day_count'] == 0)).astype(int)
        
        att_agg = att_df.groupby('driver_id').agg({
            'total_minutes_late': 'sum',
            'present_count': 'sum',
            'half_day_count': 'sum',
            'absent_count': 'sum'
        }).reset_index()
    else:
        att_agg = pd.DataFrame(columns=['driver_id', 'total_minutes_late', 'present_count', 'half_day_count', 'absent_count'])

    df = drivers_df.merge(evals_agg, on='driver_id', how='left')
    df = df.merge(trips_agg, on='driver_id', how='left')
    df = df.merge(att_agg, on='driver_id', how='left')

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

    if len(df) < 5:
        print("Insufficient driver records to perform split validation.")
        return

    df['target_label'] = df.apply(generate_ground_truth_labels, axis=1)

    feature_cols = [
        'safety_score', 'punctuality_score', 'professionalism_score', 
        'trips_amount', 'total_minutes_late', 'present_count', 
        'half_day_count', 'absent_count'
    ]
    
    X = df[feature_cols].values
    y = df['target_label'].values

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    X_train, X_test, y_train, y_test = train_test_split(
        X_scaled, y, test_size=0.20, random_state=42
    )

    k_val = min(3, len(X_train))
    knn = KNeighborsClassifier(n_neighbors=k_val, weights='distance')
    knn.fit(X_train, y_train)
    y_pred = knn.predict(X_test)

    print(f"Dataset Split: {len(X_train)} Train | {len(X_test)} Test")
    print(f"Features: {feature_cols}")
    print(f"Accuracy  : {accuracy_score(y_test, y_pred) * 100:.2f}%")
    print(f"Precision : {precision_score(y_test, y_pred, average='weighted', zero_division=0):.4f}")
    print(f"Recall    : {recall_score(y_test, y_pred, average='weighted', zero_division=0):.4f}")
    print(f"F1-Score  : {f1_score(y_test, y_pred, average='weighted', zero_division=0):.4f}")

    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, zero_division=0))


def evaluate_objective_3_2_mlr():
    print("\n=======================================================")
    print("OBJECTIVE 3.2: MAINTENANCE FORECASTING (MLR) EVALUATION")
    print("=======================================================")

    # Based identically on the predictive_ml.py baseline training matrix
    X = np.array([
        [8, 120, 14], [1, 15, 1], [5, 95, 8], [2, 40, 2], [9, 180, 22], 
        [1, 8, 0], [6, 110, 11], [3, 55, 3], [10, 0, 0], [8, 60, 4]     
    ])
    
    y = np.array([
        12.0, 310.0, 45.0, 240.0, 2.0, 350.0, 25.0, 180.0, 280.0, 140.0  
    ])

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    # 80/20 split based on the baseline matrix
    X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.20, random_state=42)

    mlr = LinearRegression()
    mlr.fit(X_train, y_train)
    y_pred = mlr.predict(X_test)

    mae = mean_absolute_error(y_test, y_pred)
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    
    try:
        r2 = r2_score(y_test, y_pred)
    except Exception:
        r2 = 0.0

    print(f"Dataset Split: {len(X_train)} Train | {len(X_test)} Test")
    print("Features                        : [Vehicle Age (Years), Trip Count, Past Repair Count]")
    print("Target Variable                 : Days until structural maintenance required")
    print(f"Mean Absolute Error (MAE)       : {mae:.2f} Days")
    print(f"Root Mean Squared Error (RMSE)  : {rmse:.2f} Days")
    print(f"Coefficient of Determination (R²): {r2:.4f}")


def evaluate_objective_3_3_kmeans():
    print("\n=======================================================")
    print("OBJECTIVE 3.3: DESTINATION DEMAND (K-MEANS) EVALUATION")
    print("=======================================================")

    # Replicates route_ml_2.py feature extraction
    trips_res = supabase.table('trip_schedule').select('route_name, passenger_count, vehicle_id').execute()
    raw_trips = trips_res.data or []

    route_stats = {}
    for t in raw_trips:
        r = str(t.get('route_name') or 'Unknown').strip()
        if r not in route_stats:
            route_stats[r] = {'trips': 0, 'passengers': 0, 'vehicles': set()}
        
        route_stats[r]['trips'] += 1
        pax = t.get('passenger_count')
        try:
            route_stats[r]['passengers'] += max(0, int(pax or 0))
        except (TypeError, ValueError):
            pass
        v_id = t.get('vehicle_id')
        if v_id:
            route_stats[r]['vehicles'].add(v_id)

    features = []
    for r, stats in route_stats.items():
        features.append([stats['passengers'], stats['trips'], len(stats['vehicles'])])

    if len(features) < 3:
        print("Insufficient unique destinations to evaluate clustering.")
        return

    X = np.array(features)
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    k_val = min(3, len(X))
    kmeans = KMeans(n_clusters=k_val, random_state=42, n_init=10)
    labels = kmeans.fit_predict(X_scaled)

    try:
        score = silhouette_score(X_scaled, labels)
    except ValueError:
        score = 0.0

    print(f"Total Unique Destinations Analyzed: {len(X)}")
    print(f"Features                      : [passenger_volume, trip_frequency, assigned_vehicle_count]")
    print(f"Number of Clusters (k)        : {k_val}")
    print(f"Silhouette Coefficient        : {score:.4f}")
    
    if score > 0.50:
        print("Interpretation                : Strong structural separation. Routes have distinct volume profiles.")
    elif score > 0.25:
        print("Interpretation                : Moderate separation; clusters capture real demand trends.")
    else:
        print("Interpretation                : Overlapping variance profiles; route demands are highly homogenous.")


if __name__ == '__main__':
    evaluate_objective_3_1_knn()
    evaluate_objective_3_2_mlr()
    evaluate_objective_3_3_kmeans()
    print("\n=======================================================\n")