import numpy as np
from flask import Blueprint, jsonify, request
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
from datetime import datetime, timedelta

route_ml_bp = Blueprint('route_ml', __name__)
supabase = None  

def _parse_db_time(date_str, time_val):
    try:
        if not time_val or not date_str: 
            return None
        clean_date = str(date_str).split('T')[0]
        time_str = str(time_val)[:8] 
        return datetime.strptime(f"{clean_date} {time_str}", "%Y-%m-%d %H:%M:%S")
    except Exception as e:
        return None

def _parse_iso_timestamp(timestamp_str):
    try:
        if not timestamp_str: 
            return None
        clean_str = str(timestamp_str).replace('T', ' ').split('.')[0].split('+')[0].replace('Z', '')
        return datetime.strptime(clean_str, "%Y-%m-%d %H:%M:%S")
    except Exception as e:
        return None

# Supports both URL variants and GET/POST to avoid routing mismatches
@route_ml_bp.route('/routes/cluster', methods=['GET', 'POST'])
@route_ml_bp.route('/api/routes/cluster', methods=['GET', 'POST'])
def cluster_route_delays():
    try:
        time_filter = request.args.get('filter', 'all') 
        target_date = request.args.get('date')          
        target_month = request.args.get('month')        
        target_year = request.args.get('year', '2026')  

        query = supabase.table('trip_schedule').select(
            'trip_id, route_name, schedule_date, departure_time, estimated_arrival_time, actual_start_time, actual_end_time, vehicle_id, user_id, route_distance'
        ).eq('trip_status', 'Completed').not_.is_('actual_start_time', 'null').not_.is_('actual_end_time', 'null')

        # Time range filtering
        today_str = datetime.now().strftime('%Y-%m-%d')
        if time_filter == 'today':
            query = query.eq('schedule_date', today_str)
        elif time_filter == 'date' and target_date:
            query = query.eq('schedule_date', target_date)
        elif time_filter == 'week':
            curr = datetime.now()
            start_week = (curr - timedelta(days=curr.weekday())).strftime('%Y-%m-%d')
            end_week = (curr + timedelta(days=6 - curr.weekday())).strftime('%Y-%m-%d')
            query = query.gte('schedule_date', start_week).lte('schedule_date', end_week)
        elif time_filter == 'month' and target_month:
            m = int(target_month)
            y = int(target_year)
            start_m = f"{y}-{m:02d}-01"
            next_m = m + 1 if m < 12 else 1
            next_y = y if m < 12 else y + 1
            end_m = f"{next_y}-{next_m:02d}-01"
            query = query.gte('schedule_date', start_m).lt('schedule_date', end_m)

        trips_res = query.execute()
        raw_trips = trips_res.data or []

        if len(raw_trips) < 3:
            return jsonify({
                "success": True, 
                "status": "Insufficient Data", 
                "message": f"Found only {len(raw_trips)} completed trips for this time filter. Need at least 3 for K-Means clustering."
            }), 200

        # Reference lookup maps for driver & vehicle display
        try:
            drivers_res = supabase.table('driver_profile').select('user_id, full_name').execute()
            vehicles_res = supabase.table('vehicle').select('vehicle_id, plate_number').execute()
            d_map = {d['user_id']: d['full_name'] for d in (drivers_res.data or [])}
            v_map = {v['vehicle_id']: v['plate_number'] for v in (vehicles_res.data or [])}
        except Exception:
            d_map = {}
            v_map = {}

        features = []
        valid_trips = []

        # Feature Engineering: identical calculation as original working file
        for t in raw_trips:
            date_str = t.get('schedule_date')
            sched_dep = _parse_db_time(date_str, t.get('departure_time'))
            sched_arr = _parse_db_time(date_str, t.get('estimated_arrival_time'))
            act_dep = _parse_iso_timestamp(t.get('actual_start_time'))
            act_arr = _parse_iso_timestamp(t.get('actual_end_time'))

            if not all([sched_dep, sched_arr, act_dep, act_arr]):
                continue

            dep_delay = (act_dep - sched_dep).total_seconds() / 60.0
            arr_delay = (act_arr - sched_arr).total_seconds() / 60.0
            trip_duration = (act_arr - act_dep).total_seconds() / 60.0

            # Matches original logic to allow anomaly clustering
            if trip_duration <= 0: 
                continue

            features.append([dep_delay, arr_delay, trip_duration])
            
            t['dep_delay'] = round(dep_delay, 1)
            t['arr_delay'] = round(arr_delay, 1)
            t['duration'] = round(trip_duration, 1)
            t['driver_name'] = d_map.get(t.get('user_id'), 'Assigned Driver')
            t['plate_number'] = v_map.get(t.get('vehicle_id'), 'Assigned Shuttle')
            valid_trips.append(t)

        if len(features) < 3:
            return jsonify({
                "success": True, 
                "status": "Insufficient Data", 
                "message": "Valid timestamp records failed sanity validation."
            }), 200

        X = np.array(features)
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        
        n_clusters = min(3, len(X))
        kmeans = KMeans(n_clusters=n_clusters, random_state=42, n_init=10)
        labels = kmeans.fit_predict(X_scaled)

        cluster_summaries = []
        label_mapping = {}

        for i in range(n_clusters):
            cluster_pts = X[labels == i]
            avg_dep = float(np.mean(cluster_pts[:, 0]))
            avg_arr = float(np.mean(cluster_pts[:, 1]))
            avg_dur = float(np.mean(cluster_pts[:, 2]))

            # Categorization logic
            if avg_dep > 120 or avg_arr < -120 or avg_arr > 120:
                c_name = "Needs Review"
                desc = "Extreme time variance detected. Likely a manual data entry or AM/PM error."
            elif avg_arr > 25 and avg_dep <= 15:
                c_name = "Transit/Traffic Delay Risk"
                desc = "Trips leave on time but hit severe road delays."
            elif avg_dep > 15:
                c_name = "Departure Bottleneck Risk"
                desc = "Trips are consistently leaving the garage late."
            else:
                c_name = "Optimal Baseline"
                desc = "Trips operating within acceptable schedule variance."

            label_mapping[i] = c_name

            cluster_summaries.append({
                "cluster_id": i,
                "label": c_name,
                "description": desc,
                "count": len(cluster_pts),
                "avg_departure_delay_mins": round(avg_dep, 1),
                "avg_arrival_delay_mins": round(avg_arr, 1),
                "avg_duration_mins": round(avg_dur, 1)
            })

        for idx, t in enumerate(valid_trips):
            c_id = int(labels[idx])
            t['cluster_id'] = c_id
            t['cluster_label'] = label_mapping.get(c_id, "Cluster")

        # Actionable insights (filtered for realistic delays)
        route_stats = {}
        for t in valid_trips:
            r_name = t['route_name']
            if r_name not in route_stats:
                route_stats[r_name] = []
            route_stats[r_name].append(t['arr_delay'])

        recommendations = []
        for r_name, delays in route_stats.items():
            avg_d = sum(delays) / len(delays)
            if 15 < avg_d <= 120:
                recommendations.append({
                    "route": r_name,
                    "insight": f"Averages {round(avg_d)} mins late.",
                    "action": f"Adjust scheduled arrival time forward by {round(avg_d / 5) * 5} minutes to reflect actual traffic conditions."
                })

        return jsonify({
            "success": True,
            "status": "Clustered",
            "total_evaluated": len(valid_trips),
            "clusters": cluster_summaries,
            "recommendations": recommendations,
            "trips": valid_trips
        }), 200

    except Exception as e:
        print(f"❌ Route Clustering ML Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500