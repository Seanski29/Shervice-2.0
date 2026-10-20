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
    print("OBJECTIVE 3.1: DRIVER CLASSIFICATION (KNN) RULE-CONSISTENCY EVALUATION")
    print("=======================================================")
    print("Note: labels are generated from the same driver features used by KNN.")
    print("This measures consistency with the labeling policy, not future-driver prediction.")

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
    print("OBJECTIVE 3.1: DRIVER CLASSIFICATION (KNN) RULE-CONSISTENCY EVALUATION")
    print("=======================================================")
    print("Note: labels are generated from the same driver features used by KNN.")
    print("This measures consistency with the labeling policy, not future-driver prediction.")
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


def _driver_temporal_rows():
    """Build prior-month features and next-month labels for honest testing."""
    drivers = pd.DataFrame(driver_ml._fetch_all('driver_profile', 'driver_id'))
    evaluations = pd.DataFrame(driver_ml._fetch_all(
        'evaluation',
        'driver_id, submit_date, safety_score, punctuality_score, '
        'professionalism_score, source',
    ))
    trips = pd.DataFrame(driver_ml._fetch_all(
        'trip_schedule', 'driver_id, schedule_date',
    ))
    attendance = pd.DataFrame(driver_ml._fetch_all(
        'attendance_record',
        'driver_id, work_date, total_minutes_late, note',
    ))

    for frame, column in (
        (evaluations, 'submit_date'),
        (trips, 'schedule_date'),
        (attendance, 'work_date'),
    ):
        if not frame.empty:
            frame['_date'] = pd.to_datetime(frame[column], errors='coerce')
            frame['_month'] = frame['_date'].dt.to_period('M')

    def period_metrics(driver_id, period, historical):
        start = period.start_time
        end = period.end_time
        if historical:
            evals = evaluations[(evaluations.driver_id == driver_id) & (evaluations['_date'] < start)] if not evaluations.empty else evaluations
            trip_rows = trips[(trips.driver_id == driver_id) & (trips['_date'] < start)] if not trips.empty else trips
            att = attendance[(attendance.driver_id == driver_id) & (attendance['_date'] < start)] if not attendance.empty else attendance
        else:
            evals = evaluations[(evaluations.driver_id == driver_id) & (evaluations['_date'] >= start) & (evaluations['_date'] <= end)] if not evaluations.empty else evaluations
            trip_rows = trips[(trips.driver_id == driver_id) & (trips['_date'] >= start) & (trips['_date'] <= end)] if not trips.empty else trips
            att = attendance[(attendance.driver_id == driver_id) & (attendance['_date'] >= start) & (attendance['_date'] <= end)] if not attendance.empty else attendance

        scores = {}
        for metric in ('safety_score', 'punctuality_score', 'professionalism_score'):
            if evals.empty:
                scores[metric] = 3.0
                continue
            source = evals['source'].fillna('staff').where(evals['source'].isin(['staff', 'passenger']), 'staff')
            staff_values = pd.to_numeric(evals.loc[source == 'staff', metric], errors='coerce').mean()
            passenger_values = pd.to_numeric(evals.loc[source == 'passenger', metric], errors='coerce').mean()
            if pd.notna(staff_values) and pd.notna(passenger_values):
                scores[metric] = staff_values * 0.60 + passenger_values * 0.40
            elif pd.notna(staff_values):
                scores[metric] = staff_values
            elif pd.notna(passenger_values):
                scores[metric] = passenger_values
            else:
                scores[metric] = 3.0

        if att.empty:
            total_late = present = half_day = absent = 0
        else:
            notes = att['note'].fillna('').astype(str).str.lower()
            absent_flags = notes.str.contains('absent')
            half_flags = notes.str.contains('half day')
            total_late = pd.to_numeric(att['total_minutes_late'], errors='coerce').fillna(0).sum()
            absent = int(absent_flags.sum())
            half_day = int(half_flags.sum())
            present = int((~absent_flags & ~half_flags).sum())

        return {
            **scores,
            'trips_amount': int(len(trip_rows)),
            'total_minutes_late': float(total_late),
            'present_count': present,
            'half_day_count': half_day,
            'absent_count': absent,
        }

    periods = set()
    for frame in (evaluations, trips, attendance):
        if not frame.empty:
            periods.update(frame['_month'].dropna().unique())
    periods = sorted(periods)

    rows = []
    for driver_id in drivers['driver_id'].tolist():
        for period in periods[1:]:
            prior = period_metrics(driver_id, period, historical=True)
            target = period_metrics(driver_id, period, historical=False)
            if (prior['trips_amount'] == 0 and prior['present_count'] == 0
                    and prior['safety_score'] == 3.0
                    and target['trips_amount'] == 0
                    and target['present_count'] == 0):
                continue
            rows.append({
                'period': period,
                'features': [prior[column] for column in [
                    'safety_score', 'punctuality_score', 'professionalism_score',
                    'trips_amount', 'total_minutes_late', 'present_count',
                    'half_day_count', 'absent_count',
                ]],
                'label': generate_ground_truth_labels(pd.Series(target)),
            })
    return sorted(rows, key=lambda row: row['period'])


def evaluate_objective_3_1_temporal():
    print("\n=======================================================")
    print("OBJECTIVE 3.1: DRIVER CLASSIFICATION TEMPORAL EVALUATION")
    print("=======================================================")
    print("Features use history before each month; labels come from that month.")
    print("This is a future-style holdout, not a same-period rule-consistency test.")

    driver_ml.supabase = supabase
    rows = _driver_temporal_rows()
    periods = sorted({row['period'] for row in rows})
    if len(rows) < 20 or len(periods) < 3:
        print("Insufficient monthly driver snapshots for temporal evaluation.")
        return

    # Use a chronological 80/20 split: the first 80% of months train the
    # model, and the final 20% are held out as future-style test data.
    split_period = periods[max(1, int(len(periods) * 0.80))]
    train_rows = [row for row in rows if row['period'] < split_period]
    test_rows = [row for row in rows if row['period'] >= split_period]
    if not train_rows or not test_rows:
        print("Unable to create chronological train/test partitions.")
        return

    X_train = np.asarray([row['features'] for row in train_rows], dtype=float)
    X_test = np.asarray([row['features'] for row in test_rows], dtype=float)
    y_train = [row['label'] for row in train_rows]
    y_test = [row['label'] for row in test_rows]
    model = Pipeline([
        ('scale', StandardScaler()),
        ('knn', KNeighborsClassifier(
            n_neighbors=min(5, len(train_rows)), weights='distance'
        )),
    ])
    model.fit(X_train, y_train)
    predictions = model.predict(X_test)

    train_distribution = pd.Series(y_train).value_counts().sort_index()
    test_distribution = pd.Series(y_test).value_counts().sort_index()
    train_periods = sorted({row['period'] for row in train_rows})
    test_periods = sorted({row['period'] for row in test_rows})
    print(f"Total monthly snapshots         : {len(rows)}")
    print(f"Feature matrix dimensions       : {X_train.shape[1]} features")
    print(f"Training percentage              : {len(train_rows) / len(rows) * 100:.2f}%")
    print(f"Future test percentage           : {len(test_rows) / len(rows) * 100:.2f}%")
    print(f"Training months                  : {len(train_periods)}")
    print(f"Future test months               : {len(test_periods)}")
    print(f"Training snapshots               : {len(train_rows)}")
    print(f"Future test snapshots            : {len(test_rows)}")
    print(f"Training through                 : {split_period - 1}")
    print(f"Testing from                     : {split_period}")
    print(f"Accuracy                         : {accuracy_score(y_test, predictions) * 100:.2f}%")
    print(f"Macro Precision                  : {precision_score(y_test, predictions, average='macro', zero_division=0):.4f}")
    print(f"Macro Recall                     : {recall_score(y_test, predictions, average='macro', zero_division=0):.4f}")
    print(f"Macro F1-Score                   : {f1_score(y_test, predictions, average='macro', zero_division=0):.4f}")
    print("Training label distribution:")
    print(train_distribution.to_string())
    print("Test label distribution:")
    print(test_distribution.to_string())
    print("\nClassification Report:")
    print(classification_report(y_test, predictions, zero_division=0))


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

    snapshot_dates = [row[0] for row in rows]
    train_dates = snapshot_dates[:split]
    test_dates = snapshot_dates[split:]
    print(f"Total maintenance snapshots     : {len(rows)}")
    print(f"Feature matrix dimensions        : {X_train.shape[1]} features")
    print(f"Training percentage              : {len(X_train) / len(rows) * 100:.2f}%")
    print(f"Test percentage                  : {len(X_test) / len(rows) * 100:.2f}%")
    print(f"Training date range              : {train_dates[0]} through {train_dates[-1]}")
    print(f"Test date range                  : {test_dates[0]} through {test_dates[-1]}")
    print(f"Training target mean             : {y_train.mean():.2f} days")
    print(f"Test target mean                 : {y_test.mean():.2f} days")
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

    print(f"Total Unique Destinations Analyzed: {len(X)}")
    print(f"Source trip rows used             : {len(raw_trips)}")
    k_val = min(3, len(X))
    kmeans = KMeans(n_clusters=k_val, random_state=42, n_init=10)
    labels = kmeans.fit_predict(X_scaled)

    try:
        score = silhouette_score(X_scaled, labels)
    except ValueError:
        score = 0.0

    print(f"Cluster assignment distribution   : {pd.Series(labels).value_counts().sort_index().to_dict()}")
    print(f"Number of Clusters (k)        : {k_val}")
    print(f"Silhouette Coefficient        : {score:.4f}")
    
    if score > 0.50:
        print("Interpretation                : Strong structural separation. Routes have distinct volume profiles.")
    elif score > 0.25:
        print("Interpretation                : Moderate separation; clusters capture real demand trends.")
    else:
        print("Interpretation                : Overlapping variance profiles; route demands are highly homogenous.")


if __name__ == '__main__':
    evaluate_objective_3_1_temporal()
    evaluate_objective_3_2_live()
    evaluate_objective_3_3_kmeans()
    print("\n=======================================================\n")
