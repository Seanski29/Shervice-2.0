import os
import sys
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime
from dotenv import load_dotenv
from sklearn.cluster import KMeans
from sklearn.ensemble import RandomForestRegressor
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
from sklearn.model_selection import StratifiedKFold, cross_val_predict, train_test_split
from sklearn.neighbors import KNeighborsClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from supabase import create_client

# Reuse the production driver feature engineering and label rules so this
# evaluation script cannot drift from driver_ml.py.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from roles import driver_ml
from roles import predictive_ml

load_dotenv(Path(__file__).resolve().parents[1] / '.env')
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY") or os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise ValueError("Missing Supabase credentials in .env file!")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# --- Label adapter kept for callers of this evaluation script ---
def generate_ground_truth_labels(row):
    return driver_ml.generate_ground_truth_labels(row)

def evaluate_legacy_knn_split():
    print("\n=======================================================")
    print("OBJECTIVE 3.1: DRIVER CLASSIFICATION (KNN) EVALUATION")
    print("=======================================================")

    driver_ml.supabase = supabase
    df = driver_ml.fetch_and_prepare_data()

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

    print("Label distribution:")
    print(df['target_label'].value_counts().to_string())

    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, zero_division=0))


def evaluate_legacy_toy_mlr():
    print("\n=======================================================")
    print("OBJECTIVE 3.2: MAINTENANCE FORECASTING (MLR) EVALUATION")
    print("=======================================================")

    # Legacy standalone baseline retained for historical comparison.
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


def evaluate_objective_3_1_knn_cross_validated():
    print("\n=======================================================")
    print("OBJECTIVE 3.1: DRIVER CLASSIFICATION (KNN) EVALUATION")
    print("=======================================================")
    driver_ml.supabase = supabase
    df = driver_ml.fetch_and_prepare_data()
    if len(df) < 5:
        print("Insufficient driver records to perform validation.")
        return

    feature_cols = [
        'safety_score', 'punctuality_score', 'professionalism_score',
        'trips_amount', 'total_minutes_late', 'present_count',
        'half_day_count', 'absent_count'
    ]
    df['target_label'] = df.apply(generate_ground_truth_labels, axis=1)
    X = df[feature_cols].values
    y = df['target_label'].values
    class_counts = pd.Series(y).value_counts()
    folds = min(5, int(class_counts.min()))
    if folds < 2:
        print('Insufficient examples in one or more classes for cross-validation.')
        return

    pipeline = Pipeline([
        ('scale', StandardScaler()),
        ('knn', KNeighborsClassifier(n_neighbors=min(3, len(df) - 1), weights='distance')),
    ])
    cv = StratifiedKFold(n_splits=folds, shuffle=True, random_state=42)
    predictions = cross_val_predict(pipeline, X, y, cv=cv)
    print(f"Stratified cross-validation       : {folds} folds")
    print(f"Features                          : {feature_cols}")
    print(f"Accuracy                          : {accuracy_score(y, predictions) * 100:.2f}%")
    print(f"Macro Precision                   : {precision_score(y, predictions, average='macro', zero_division=0):.4f}")
    print(f"Macro Recall                      : {recall_score(y, predictions, average='macro', zero_division=0):.4f}")
    print(f"Macro F1-Score                    : {f1_score(y, predictions, average='macro', zero_division=0):.4f}")
    print('Label distribution:')
    print(df['target_label'].value_counts().to_string())
    print('\nClassification Report:')
    print(classification_report(y, predictions, zero_division=0))


def evaluate_objective_3_2_production():
    print("\n=======================================================")
    print("OBJECTIVE 3.2: MAINTENANCE FORECASTING (MLR) EVALUATION")
    print("=======================================================")
    predictive_ml.supabase = supabase
    trained = predictive_ml.train_model()
    print(f"Training snapshots             : {predictive_ml.training_samples}")
    print(f"Features                       : {predictive_ml.FEATURE_NAMES}")
    print("Target Variable                : Days until next recorded maintenance")
    print("Model                          : Multiple Linear Regression")
    print("Status                         : " + ("trained on live history" if trained else "insufficient history; workload baseline used"))


# Replace the legacy toy-data evaluator with a live, chronological evaluator.
def _maintenance_training_rows():
    # predictive_ml uses an injected client in the same way as the Flask app.
    predictive_ml.supabase = supabase
    vehicles, trips, repairs = predictive_ml._load_history()
    trips_by_vehicle, repairs_by_vehicle = {}, {}
    for trip in trips:
        trips_by_vehicle.setdefault(trip.get('vehicle_id'), []).append(trip)
    for repair in repairs:
        repairs_by_vehicle.setdefault(repair.get('vehicle_id'), []).append(repair)

    rows = []
    for vehicle in vehicles:
        vehicle_id = vehicle.get('vehicle_id')
        vehicle_trips = trips_by_vehicle.get(vehicle_id, [])
        vehicle_repairs = repairs_by_vehicle.get(vehicle_id, [])
        repair_dates = sorted(
            d for d in (
                predictive_ml._parse_date(r.get('repair_date') or r.get('incident_date'))
                for r in vehicle_repairs
            ) if d
        )
        for trip in vehicle_trips:
            snapshot = predictive_ml._parse_date(trip.get('schedule_date'))
            if not snapshot:
                continue
            future = [d for d in repair_dates if d > snapshot]
            if future:
                target = min(float((future[0] - snapshot).days), 365.0)
                rows.append((snapshot, predictive_ml._feature_row(
                    vehicle, vehicle_trips, vehicle_repairs, snapshot
                ), target))
    return sorted(rows, key=lambda row: row[0])


def evaluate_objective_3_2_live():
    print("\n=======================================================")
    print("OBJECTIVE 3.2: MAINTENANCE FORECASTING (MLR) EVALUATION")
    print("=======================================================")
    rows = _maintenance_training_rows()
    if len(rows) < 20:
        print("Insufficient live maintenance snapshots for evaluation.")
        return

    split = max(1, min(len(rows) - 1, int(len(rows) * 0.80)))
    X_train = np.asarray([row[1] for row in rows[:split]], dtype=float)
    X_test = np.asarray([row[1] for row in rows[split:]], dtype=float)
    y_train = np.asarray([row[2] for row in rows[:split]], dtype=float)
    y_test = np.asarray([row[2] for row in rows[split:]], dtype=float)

    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    mlr = LinearRegression().fit(X_train_scaled, y_train)
    mlr_pred = mlr.predict(X_test_scaled)

    rf = RandomForestRegressor(
        n_estimators=160, min_samples_leaf=2, random_state=42
    ).fit(X_train, y_train)
    rf_pred = rf.predict(X_test)

    print(f"Chronological split             : {len(X_train)} Train | {len(X_test)} Test")
    print(f"Features                        : {predictive_ml.FEATURE_NAMES}")
    print("Target Variable                 : Days until next recorded maintenance")
    for name, predictions in [('MLR production', mlr_pred), ('Random Forest comparison', rf_pred)]:
        print(f"\n{name}:")
        print(f"  MAE                          : {mean_absolute_error(y_test, predictions):.2f} Days")
        print(f"  RMSE                         : {np.sqrt(mean_squared_error(y_test, predictions)):.2f} Days")
        print(f"  R-squared                    : {r2_score(y_test, predictions):.4f}")


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
    evaluate_objective_3_1_knn_cross_validated()
    evaluate_objective_3_2_live()
    evaluate_objective_3_3_kmeans()
    print("\n=======================================================\n")
