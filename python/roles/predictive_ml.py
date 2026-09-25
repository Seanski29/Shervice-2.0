"""Vehicle maintenance forecasting from real trip and service history."""
from datetime import date, datetime
import re

import numpy as np
from flask import Blueprint, jsonify
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import StandardScaler

predictive_bp = Blueprint('predictive_ml', __name__)
supabase = None

FEATURE_NAMES = [
    'age_years', 'trips_last_90_days', 'passengers_last_90_days',
    'average_passengers_per_trip', 'average_load_factor', 'heavy_load_trips',
    'lifetime_trips', 'past_repairs_count', 'days_since_last_repair',
]
model = LinearRegression()
scaler = StandardScaler()
is_trained = False
training_samples = 0


def _fetch_all(table_name, columns):
    rows, offset, page_size = [], 0, 1000
    while True:
        page = (supabase.table(table_name).select(columns)
                .range(offset, offset + page_size - 1).execute().data or [])
        rows.extend(page)
        if len(page) < page_size:
            return rows
        offset += page_size


def _parse_date(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace('Z', '+00:00')).date()
    except (TypeError, ValueError):
        try:
            return date.fromisoformat(str(value)[:10])
        except (TypeError, ValueError):
            return None


def _number(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _vehicle_capacity(vehicle):
    direct = _number(vehicle.get('seating_capacity'), 0.0)
    if direct > 0:
        return direct
    match = re.search(r'(\d+)\s*seat', str(vehicle.get('bus_type') or '').lower())
    return float(match.group(1)) if match else 15.0


def _trip_capacity(trip, vehicle):
    direct = _number(trip.get('seating_capacity'), 0.0)
    return direct if direct > 0 else _vehicle_capacity(vehicle)


def _feature_row(vehicle, vehicle_trips, vehicle_repairs, snapshot_date):
    window_start = snapshot_date.fromordinal(snapshot_date.toordinal() - 90)
    recent = []
    for trip in vehicle_trips:
        trip_date = _parse_date(trip.get('schedule_date'))
        if trip_date and window_start <= trip_date <= snapshot_date:
            recent.append(trip)
    passengers = [_number(t.get('passenger_count')) for t in recent]
    loads = [_number(t.get('passenger_count')) / _trip_capacity(t, vehicle) for t in recent]
    repair_dates = sorted(
        d for d in (_parse_date(r.get('repair_date') or r.get('incident_date'))
                    for r in vehicle_repairs)
        if d and d <= snapshot_date
    )
    last_repair = repair_dates[-1] if repair_dates else None
    days_since = (snapshot_date - last_repair).days if last_repair else 365.0
    lifetime = sum(
        1 for t in vehicle_trips
        if (_parse_date(t.get('schedule_date')) or date.max) <= snapshot_date
    )
    model_year = _number(vehicle.get('model_year'), snapshot_date.year)
    return [
        max(0.0, snapshot_date.year - model_year),
        float(len(recent)),
        float(sum(passengers)),
        float(np.mean(passengers)) if passengers else 0.0,
        float(np.mean(loads)) if loads else 0.0,
        float(sum(1 for load in loads if load >= 0.85)),
        float(lifetime),
        float(len(repair_dates)),
        float(min(days_since, 3650.0)),
    ]


def _load_history():
    vehicles = _fetch_all(
        'vehicle',
        'vehicle_id, model_year, bus_type, vehicle_type, is_available, plate_number',
    )
    trips = _fetch_all(
        'trip_schedule', 'vehicle_id, schedule_date, passenger_count, seating_capacity',
    )
    repairs = _fetch_all(
        'maintenance_log',
        'vehicle_id, repair_date, incident_date, maintenance_type',
    )
    # Routine maintenance checks are visible in the UI but are not treated as
    # repair outcomes for the maintenance-cycle target. Only explicit repair
    # records provide the failure/service events the regression forecasts.
    repairs = [
        row for row in repairs
        if str(row.get('maintenance_type') or 'maintenance').lower() == 'repair'
    ]
    return vehicles, trips, repairs


def _maintenance_type_counts(vehicle_id):
    logs = _fetch_all(
        'maintenance_log',
        'vehicle_id, maintenance_type',
    )
    counts = {'repair': 0, 'maintenance': 0}
    for log in logs:
        if log.get('vehicle_id') != vehicle_id:
            continue
        record_type = str(log.get('maintenance_type') or 'maintenance').lower()
        if record_type in counts:
            counts[record_type] += 1
    return counts


def train_model():
    """Train on snapshots whose next maintenance event is known."""
    global is_trained, training_samples, model, scaler
    try:
        vehicles, trips, repairs = _load_history()
        trips_by_vehicle, repairs_by_vehicle = {}, {}
        for trip in trips:
            trips_by_vehicle.setdefault(trip.get('vehicle_id'), []).append(trip)
        for repair in repairs:
            repairs_by_vehicle.setdefault(repair.get('vehicle_id'), []).append(repair)

        features, targets = [], []
        for vehicle in vehicles:
            vehicle_id = vehicle.get('vehicle_id')
            vehicle_trips = trips_by_vehicle.get(vehicle_id, [])
            vehicle_repairs = repairs_by_vehicle.get(vehicle_id, [])
            repair_dates = sorted(
                d for d in (_parse_date(r.get('repair_date') or r.get('incident_date'))
                            for r in vehicle_repairs) if d
            )
            for trip in sorted(vehicle_trips, key=lambda r: _parse_date(r.get('schedule_date')) or date.min):
                snapshot = _parse_date(trip.get('schedule_date'))
                if not snapshot:
                    continue
                future = [d for d in repair_dates if d > snapshot]
                if future:
                    features.append(_feature_row(vehicle, vehicle_trips, vehicle_repairs, snapshot))
                    targets.append(min(float((future[0] - snapshot).days), 365.0))

        training_samples = len(features)
        if training_samples < 10:
            is_trained = False
            print(f'Maintenance ML needs more history; found {training_samples} snapshots.')
            return False
        X = np.asarray(features, dtype=float)
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        model = LinearRegression()
        model.fit(X_scaled, np.asarray(targets, dtype=float))
        is_trained = True
        print(f'Maintenance Multiple Linear Regression trained with {training_samples} real snapshots.')
        return True
    except Exception as exc:
        is_trained = False
        print(f'Maintenance ML training exception: {exc}')
        return False


def _fallback_days(features):
    age, recent_trips, recent_passengers, _, _, heavy_loads, _, repairs, days_since = features
    score = 180.0 - min(age * 5.0, 45.0)
    score -= min(recent_trips * 0.45, 45.0)
    score -= min(recent_passengers * 0.04, 35.0)
    score -= min(heavy_loads * 1.5, 25.0)
    score -= min(repairs * 4.0, 25.0)
    if days_since < 30:
        score += 15.0
    return max(0.0, round(score, 1))


def _forecast(vehicle, vehicle_trips, vehicle_repairs):
    features = _feature_row(vehicle, vehicle_trips, vehicle_repairs, date.today())
    if is_trained:
        days = float(model.predict(scaler.transform(np.asarray([features], dtype=float)))[0])
    else:
        days = _fallback_days(features)
    return max(0.0, round(days, 1)), features


def _apply_forecast(vehicle, days, message):
    # ML must not create or resolve a staff maintenance issue.  Due
    # Maintenance is driven by unresolved maintenance_log records.
    payload = {'risk_score': days}
    supabase.table('vehicle').update(payload).eq('vehicle_id', vehicle['vehicle_id']).execute()


def _response(vehicle, days, features, type_counts):
    metrics = dict(zip(FEATURE_NAMES, features))
    metrics.update({
        'total_trips': int(metrics['lifetime_trips']),
        'past_repairs_count': int(metrics['past_repairs_count']),
        'repair_count': type_counts.get('repair', 0),
        'maintenance_count': type_counts.get('maintenance', 0),
        'passengers_last_90_days': int(metrics['passengers_last_90_days']),
        'model': 'Multiple Linear Regression' if is_trained else 'Workload baseline',
        'training_samples': training_samples,
    })
    return {'success': True, 'vehicle_id': vehicle['vehicle_id'],
            'plate_number': vehicle.get('plate_number'), 'risk_index': days,
            'telemetry_metrics': metrics}


@predictive_bp.route('/api/vehicles/predict/<string:vehicle_id>', methods=['GET'])
def predict_maintenance_risk(vehicle_id):
    try:
        vehicle_id = int(vehicle_id) if vehicle_id.isdigit() else 0
        vehicles, trips, repairs = _load_history()
        vehicle = next((v for v in vehicles if v.get('vehicle_id') == vehicle_id), None)
        if not vehicle:
            return jsonify({'success': False, 'message': 'Vehicle asset not found.'}), 404
        if not is_trained:
            train_model()
        vehicle_trips = [t for t in trips if t.get('vehicle_id') == vehicle_id]
        vehicle_repairs = [r for r in repairs if r.get('vehicle_id') == vehicle_id]
        days, features = _forecast(vehicle, vehicle_trips, vehicle_repairs)
        type_counts = _maintenance_type_counts(vehicle_id)
        _apply_forecast(vehicle, days, f'ML forecast: maintenance due within {days} days.')
        return jsonify(_response(vehicle, days, features, type_counts)), 200
    except Exception as exc:
        return jsonify({'success': False, 'message': str(exc)}), 500


@predictive_bp.route('/api/vehicles/predict/fleet-sweep', methods=['POST', 'GET'])
def evaluate_entire_fleet():
    try:
        train_model()
        vehicles, trips, repairs = _load_history()
        flagged = []
        for vehicle in vehicles:
            vehicle_id = vehicle.get('vehicle_id')
            vehicle_trips = [t for t in trips if t.get('vehicle_id') == vehicle_id]
            vehicle_repairs = [r for r in repairs if r.get('vehicle_id') == vehicle_id]
            days, _ = _forecast(vehicle, vehicle_trips, vehicle_repairs)
            _apply_forecast(vehicle, days, f'ML fleet forecast: maintenance due within {days} days.')
            if days <= 7.0:
                flagged.append({'plate': vehicle.get('plate_number'), 'forecast_days': days})
        return jsonify({'success': True, 'message': 'Fleet maintenance forecast complete.',
                        'total_evaluated': len(vehicles), 'newly_flagged_count': len(flagged),
                        'flagged_assets': flagged,
                        'model': 'Multiple Linear Regression' if is_trained else 'Workload baseline',
                        'training_samples': training_samples}), 200
    except Exception as exc:
        return jsonify({'success': False, 'message': str(exc)}), 500
