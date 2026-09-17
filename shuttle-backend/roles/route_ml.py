import numpy as np
from flask import Blueprint, jsonify, request
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
from datetime import datetime, timedelta

route_ml_bp = Blueprint('route_ml', __name__)
supabase = None  

@route_ml_bp.route('/routes/cluster', methods=['GET', 'POST'])
@route_ml_bp.route('/api/routes/cluster', methods=['GET', 'POST'])
def cluster_destination_demand():
    try:
        time_filter = request.args.get('filter', 'all') 
        target_date = request.args.get('date')          
        target_month = request.args.get('month')        
        target_year = request.args.get('year', '2026')  

        # 1. Fetch completed trips
        query = supabase.table('trip_schedule').select(
            'trip_id, route_name, schedule_date, passenger_count, vehicle_id, driver_id, departure_time'
        )

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

        if not raw_trips:
            return jsonify({
                "success": True, 
                "status": "Insufficient Data", 
                "message": "No trips were found for this timeframe. Try All Time or check that trip summaries have been saved.",
                "total_evaluated": 0,
                "total_destinations": 0
            }), 200

        # 2. Group by destination. This intentionally uses observed route names
        # rather than a fixed destination list so extended trips are included.
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

        # 3. Compile destination features: total passengers, trip frequency,
        # and distinct vehicles assigned (the available fleet-density proxy).
        features = []
        route_names = []
        for r, stats in route_stats.items():
            trip_freq = stats['trips']
            pax_vol = stats['passengers']
            fleet_density = len(stats['vehicles'])
            features.append([pax_vol, trip_freq, fleet_density])
            route_names.append(r)

        X = np.array(features)
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)

        # 4. Execute K-Means Clustering
        n_clusters = min(3, len(X))
        kmeans = KMeans(n_clusters=n_clusters, random_state=42, n_init=10)
        labels = kmeans.fit_predict(X_scaled)

        cluster_means = []
        for i in range(n_clusters):
            mean_pax = np.mean(X[labels == i][:, 0])
            cluster_means.append((i, mean_pax))

        # Sort clusters by passenger volume (low to high) to assign logical profiles
        cluster_means.sort(key=lambda x: x[1])

        label_mapping = {}
        if n_clusters == 1:
            label_mapping[cluster_means[0][0]] = {
                "name": "Single Destination Profile",
                "desc": "Only one destination is available in this timeframe. Allocation is based on its observed passenger volume, trip frequency, and assigned vehicles.",
                "color_code": "stable"
            }
        elif n_clusters == 3:
            label_mapping[cluster_means[0][0]] = {"name": "Low Demand Destinations", "desc": "Lower passenger volume and trip activity. Review fleet allocation.", "color_code": "low"}
            label_mapping[cluster_means[1][0]] = {"name": "Steady Demand Destinations", "desc": "Moderate passenger volume and trip activity. Maintain current allocation.", "color_code": "stable"}
            label_mapping[cluster_means[2][0]] = {"name": "High Demand Destinations", "desc": "Higher passenger volume and trip activity. Consider more or larger vehicles.", "color_code": "high"}
        else:
            for i in range(n_clusters):
                label_mapping[i] = {"name": f"Demand Profile {i+1}", "desc": "Automated demand grouping.", "color_code": "stable"}

        # 5. Build JSON Output
        cluster_summaries = []
        for i in range(n_clusters):
            pts = X[labels == i]
            info = label_mapping[i]
            cluster_summaries.append({
                "cluster_id": i,
                "label": info["name"],
                "description": info["desc"],
                "count": len(pts),
                "avg_pax": round(float(np.mean(pts[:, 0])), 1),
                "avg_trips": round(float(np.mean(pts[:, 1])), 1),
                "avg_fleet": round(float(np.mean(pts[:, 2])), 1)
            })

        route_to_cluster = {}
        for idx, r in enumerate(route_names):
            route_to_cluster[r] = int(labels[idx])

        try:
            drivers_res = supabase.table('driver_profile').select('driver_id, full_name').execute()
            vehicles_res = supabase.table('vehicle').select('vehicle_id, plate_number').execute()
            d_map = {d['driver_id']: d['full_name'] for d in (drivers_res.data or [])}
            v_map = {v['vehicle_id']: v['plate_number'] for v in (vehicles_res.data or [])}
        except Exception:
            d_map = {}
            v_map = {}

        valid_trips = []
        for t in raw_trips:
            r_name = str(t.get('route_name') or 'Unknown').strip()
            c_id = route_to_cluster.get(r_name, 0)
            c_info = label_mapping.get(c_id, {})

            t['driver_name'] = d_map.get(t.get('driver_id'), 'Assigned Driver')
            t['plate_number'] = v_map.get(t.get('vehicle_id'), 'Assigned Shuttle')
            t['cluster_id'] = c_id
            t['cluster_label'] = c_info.get("name", "Cluster")
            valid_trips.append(t)

        recommendations = []
        for r_name, stats in route_stats.items():
            c_id = route_to_cluster.get(r_name)
            c_info = label_mapping.get(c_id, {})
            if c_info.get("color_code") == "high":
                recommendations.append({
                    "route": r_name,
                    "insight": f"High demand detected: {stats['passengers']} pax across {stats['trips']} trips.",
                    "action": "Increase vehicle allocation or dispatch higher capacity shuttles."
                })
            elif c_info.get("color_code") == "low":
                recommendations.append({
                    "route": r_name,
                    "insight": f"Low demand mapped: Only {stats['passengers']} pax total.",
                    "action": "Consider merging schedules or deploying smaller vehicles to optimize fuel."
                })

        return jsonify({
            "success": True,
            "status": "Clustered",
            "model": "K-Means Destination Demand Profiling",
            "features": ["passenger_volume", "trip_frequency", "assigned_vehicle_count"],
            "includes_extended_trips": True,
            "destinations": route_names,
            "total_destinations": len(route_stats),
            "total_evaluated": len(valid_trips),
            "clusters": cluster_summaries,
            "recommendations": recommendations,
            "trips": valid_trips
        }), 200

    except Exception as e:
        print(f"❌ Route Clustering ML Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500
