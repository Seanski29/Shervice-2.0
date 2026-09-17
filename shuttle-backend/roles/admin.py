import os
from io import BytesIO
from datetime import datetime
from typing import Any, Dict, List
import traceback
import numpy as np

from flask import Blueprint, jsonify, request
from supabase import create_client
import xlrd
from openpyxl import Workbook
from roles.schedules import _sweep_expired_trips

try:
    from driver_ml import is_trained, train_driver_classification_model, model, scaler
except ImportError:
    is_trained = False

# Blueprint must be defined first so decorators can use it down the line
admin_bp = Blueprint('admin', __name__)

# Dynamically assigned by app.py upon initialization
supabase = None

def get_admin_client():
    """Helper to create a dedicated Admin Client for secure Auth modifications"""
    return create_client(os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY"))


def _normalize_xls_cell(value: Any) -> Any:
    """Normalizes raw .xls cell values to strings and plain Python values."""
    if value is None:
        return ""
    if isinstance(value, float):
        if value.is_integer():
            return str(int(value))
        return str(value)
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return str(value).strip()


def parse_legacy_xls_bytes(file_bytes: bytes) -> Dict[str, Any]:
    """Reads a legacy .xls workbook, normalizes rows, and converts it to XLSX in memory."""
    try:
        workbook = xlrd.open_workbook(file_contents=file_bytes)
        sheet = workbook.sheet_by_index(0)

        rows: List[List[Any]] = []
        for row_idx in range(sheet.nrows):
            values = []
            for col_idx in range(sheet.ncols):
                values.append(sheet.cell_value(row_idx, col_idx))
            rows.append(values)

        if not rows:
            return {"success": False, "error": "Uploaded file has no rows."}

        headers = []
        for index, header in enumerate(rows[0]):
            normalized = _normalize_xls_cell(header)
            headers.append(normalized or f"Column {index + 1}")

        data_rows = []
        for row in rows[1:]:
            record = {}
            for index, header in enumerate(headers):
                value = row[index] if index < len(row) else ""
                record[header] = _normalize_xls_cell(value)
            if any(str(value).strip() for value in record.values()):
                data_rows.append(record)

        workbook_out = Workbook()
        ws = workbook_out.active
        ws.title = 'Attendance'
        ws.append(headers)

        for row in rows[1:]:
            converted_row = []
            for index in range(len(headers)):
                value = row[index] if index < len(row) else ""
                converted_row.append(_normalize_xls_cell(value))
            ws.append(converted_row)

        buffer = BytesIO()
        workbook_out.save(buffer)
        xlsx_bytes = buffer.getvalue()

        return {
            "success": True,
            "sheet_name": sheet.name,
            "headers": headers,
            "rows": data_rows,
            "xlsx_bytes": xlsx_bytes,
            "row_count": len(data_rows),
            "xlsx_size": len(xlsx_bytes),
        }
    except Exception as exc:
        return {"success": False, "error": f"Unable to convert legacy .xls file: {exc}"}


# ─────────── DIAGNOSTIC DATABASE CHECKS (DRIVERS USE THIS) ───────────
@admin_bp.route('/api/test-db', methods=['GET'])
def diagnostic_database_check():
    """Fetches all driver profiles, calculates ratings, and links them to the Flutter UI"""
    try:
        test_query = supabase.table('driver_profile').select(
            '*, user_account(username)'
        ).execute()
        raw_data = test_query.data or []

        trips_res = supabase.table('trip_schedule').select('trip_id, user_id').execute()
        trip_to_driver = {
            str(t['trip_id']): t['user_id']
            for t in trips_res.data
            if t.get('user_id') is not None and t.get('trip_id') is not None
        }
        evals_query = supabase.table('passenger_evaluation').select('trip_id, safety_score, punctuality_score, professionalism_score').limit(10000).execute()
        
        driver_scores = {}
        for ev in evals_query.data or []:
            t_id = ev.get('trip_id')
            driver_id = trip_to_driver.get(str(t_id)) if t_id is not None else None
            if driver_id:
                s = float(ev.get('safety_score') or 0)
                p = float(ev.get('punctuality_score') or 0)
                pr = float(ev.get('professionalism_score') or 0)
                eval_avg = (s + p + pr) / 3.0
                
                if driver_id not in driver_scores:
                    driver_scores[driver_id] = []
                driver_scores[driver_id].append(eval_avg)

        flattened_drivers = []
        for row in raw_data:
            linked_account = row.get('user_account') or {}
            row['username'] = linked_account.get('username', '')
            
            d_uuid = row.get('user_id')
            scores = driver_scores.get(d_uuid, [])
            row['rating'] = sum(scores) / len(scores) if scores else 0.0
            
            flattened_drivers.append(row)

        return jsonify({
            "connection_status": "SUCCESS",
            "message": "Driver profiles and ratings successfully aggregated!",
            "total_rows_found": len(flattened_drivers),
            "sample_data_payload": flattened_drivers
        }), 200
    except Exception as e:
        print(f"❌ Diagnostic database connection failed: {e}")
        return jsonify({"connection_status": "FAILED", "error_details": str(e)}), 500

# ─────────── TRIP SCHEDULES ───────────
@admin_bp.route('/trips', methods=['GET'])
def get_admin_schedules():
    """Fetches all trip schedules, fetches actual company safely, and attaches passenger CSAT ratings."""
    try:
        _sweep_expired_trips()
        trips_res = supabase.table('trip_schedule').select(
            'trip_id, schedule_date, departure_time, route_name, route_distance, '
            'trip_status, passenger_count, estimated_arrival_time, '
            'actual_start_time, actual_end_time, company_id, '
            'vehicle_id, vehicle(plate_number, bus_type), '
            'user_id, user_account(full_name)'
        ).order('schedule_date', desc=False).execute()
        
        raw_trips = trips_res.data or []

        clients_res = supabase.table('client_company').select('company_id, company_name').execute()
        company_map = {
            str(c['company_id']): c['company_name'] 
            for c in (clients_res.data or []) 
            if c.get('company_id') is not None
        }

        evals_res = supabase.table('passenger_evaluation').select('trip_id, safety_score, punctuality_score, professionalism_score').execute()
        
        trip_evals = {}
        for ev in (evals_res.data or []):
            t_id = ev.get('trip_id')
            if t_id is not None:
                s = float(ev.get('safety_score') or 0.0)
                p = float(ev.get('punctuality_score') or 0.0)
                pr = float(ev.get('professionalism_score') or 0.0)
                eval_avg = (s + p + pr) / 3.0
                
                t_id_str = str(t_id)
                if t_id_str not in trip_evals:
                    trip_evals[t_id_str] = []
                trip_evals[t_id_str].append(eval_avg)

        for trip in raw_trips:
            comp_id = trip.get('company_id')
            if comp_id is not None and str(comp_id) in company_map:
                resolved_company = company_map[str(comp_id)]
            else:
                resolved_company = "Unassigned Company"

            trip['client_company'] = {"company_name": resolved_company}
            trip['client_name'] = resolved_company

            t_id_str = str(trip.get('trip_id'))
            if t_id_str in trip_evals and trip_evals[t_id_str]:
                scores = trip_evals[t_id_str]
                trip['evaluation_score'] = sum(scores) / len(scores)
            else:
                trip['evaluation_score'] = None

        return jsonify({"success": True, "trips": raw_trips}), 200
    except Exception as e:
        print(f"❌ Admin Schedule Fetch Exception: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

# ─────────── UNIFIED MUTUAL EVALUATIONS SINGLE-TABLE ENDPOINT ───────────
@admin_bp.route('/api/admin/attendance/upload-legacy-xls', methods=['POST'])
def upload_legacy_xls_attendance():
    """Reads legacy .xls uploads, converts them in memory to xlsx, and returns the normalized rows."""
    try:
        if 'file' not in request.files:
            return jsonify({"success": False, "error": "No file uploaded."}), 400

        uploaded = request.files['file']
        if uploaded.filename == '':
            return jsonify({"success": False, "error": "No selected file."}), 400

        file_bytes = uploaded.read()
        if not file_bytes:
            return jsonify({"success": False, "error": "Uploaded file is empty."}), 400

        result = parse_legacy_xls_bytes(file_bytes)
        if not result.get('success'):
            return jsonify({"success": False, "error": result.get('error', 'Unable to convert legacy .xls file.')}), 400

        return jsonify({
            "success": True,
            "sheet_name": result.get('sheet_name'),
            "headers": result.get('headers', []),
            "rows": result.get('rows', []),
            "xlsx_size": result.get('xlsx_size', 0),
            "row_count": result.get('row_count', 0),
        }), 200
    except Exception as exc:
        return jsonify({"success": False, "error": f"Unable to convert legacy .xls file: {exc}"}), 500


@admin_bp.route('/api/dashboard/metrics', methods=['GET'])
def get_dashboard_metrics():
    """Calculates unified fleet parameters, active counts, and monthly completed trip metrics live"""
    try:
        drivers_query = supabase.table('driver_profile').select(
            'driver_id, user_id, full_name, license_no, license_expiry, '
            'employment_status, date_hired, birthday, user_account(username)'
        ).execute()
        all_drivers = drivers_query.data or []
        total_drivers = len(all_drivers)
        driver_details = [
            {
                "label": driver.get('full_name') or f"Driver {driver.get('user_id', 'Unknown')}",
                "driver_id": driver.get('driver_id'),
                "user_id": driver.get('user_id'),
                "username": (driver.get('user_account') or {}).get('username'),
                "license_no": driver.get('license_no'),
                "license_expiry": driver.get('license_expiry'),
                "employment_status": driver.get('employment_status', 'Active'),
                "date_hired": driver.get('date_hired'),
                "birthday": driver.get('birthday')
            }
            for driver in all_drivers
        ]

        vehicles_query = supabase.table('vehicle').select('vehicle_id, plate_number').eq('is_available', True).execute()
        active_vehicles = len(vehicles_query.data) if vehicles_query.data else 0
        vehicle_details = [
            {"label": vehicle.get('plate_number') or f"Vehicle {vehicle.get('vehicle_id', 'Unknown')}"}
            for vehicle in (vehicles_query.data or [])
        ]

        alerts_count_query = supabase.table('vehicle').select('vehicle_id').eq('is_available', False).execute()
        maintenance_alerts_count = len(alerts_count_query.data) if alerts_count_query.data else 0

        alerts_log_query = supabase.table('maintenance_log')\
            .select('maintenance_id, description, vehicle_id, vehicle(plate_number)')\
            .order('repair_date', desc=True)\
            .execute()

        formatted_alerts = []
        if alerts_log_query.data:
            for log in alerts_log_query.data:
                raw_v_id = log.get('vehicle_id')
                vehicle = log.get('vehicle') or {}
                if isinstance(vehicle, list):
                    vehicle = vehicle[0] if vehicle else {}
                resolved_plate = vehicle.get('plate_number', f"Asset {raw_v_id}")
                formatted_alerts.append({
                    "id": str(log.get('maintenance_id')),
                    "vehicle_id": resolved_plate,
                    "plate_number": resolved_plate,
                    "description": log.get('description', 'No details provided.')
                })

        ongoing_query = supabase.table('trip_schedule').select('trip_id, trip_status')\
            .in_('trip_status', ['Ongoing', 'ongoing', 'ONGOING', 'In Progress', 'in progress', 'IN PROGRESS'])\
            .execute()
        ongoing_trips_count = len(ongoing_query.data) if ongoing_query.data else 0
        ongoing_trip_details = [
            {"label": f"Trip {trip.get('trip_id', 'Unknown')}", "status": trip.get('trip_status', 'Ongoing')}
            for trip in (ongoing_query.data or [])
        ]

        pending_query = supabase.table('trip_schedule').select('trip_id, user_id, vehicle_id')\
            .in_('trip_status', ['Pending Staff Assignment', 'pending staff assignment', 'Pending', 'pending', 'Scheduled', 'scheduled'])\
            .execute()
        
        unassigned_count = 0
        if pending_query.data:
            unassigned_count = sum(1 for t in pending_query.data if t.get('user_id') is None or t.get('vehicle_id') is None)
        unassigned_details = [
            {"label": f"Trip {trip.get('trip_id', 'Unknown')}", "status": "Needs assignment"}
            for trip in (pending_query.data or [])
            if trip.get('user_id') is None or trip.get('vehicle_id') is None
        ]

        company_monthly_metrics = []
        selected_month = int(request.args.get('month', datetime.now().month))
        selected_year = int(request.args.get('year', datetime.now().year))
        try:
            if selected_month < 1 or selected_month > 12:
                raise ValueError('month must be between 1 and 12')
            
            period_start = datetime(selected_year, selected_month, 1).date().isoformat()
            if selected_month == 12:
                next_month = datetime(selected_year + 1, 1, 1)
            else:
                next_month = datetime(selected_year, selected_month + 1, 1)
            period_end = next_month.date().isoformat()
            
            companies_fetch = supabase.table('client_company').select('company_id, company_name').execute()
            
            company_map = {}
            company_list = []
            if companies_fetch.data:
                for c in companies_fetch.data:
                    name = c.get('company_name')
                    if name and 'INTERNAL' not in name.upper() and 'GT LANTIN' not in name.upper():
                        company_list.append(name)
                        company_map[str(c['company_id'])] = name
            
            if not company_list:
                company_list = ["Bandai", "NX Logistics", "EPSON"]

            trips_fetch = supabase.table('trip_schedule')\
                .select('trip_id, company_id, trip_status')\
                .in_('trip_status', ['Completed', 'COMPLETED', 'completed'])\
                .gte('schedule_date', period_start)\
                .lt('schedule_date', period_end)\
                .execute()
            
            counts = {name: 0 for name in company_list}
            
            if trips_fetch.data:
                for trip in trips_fetch.data:
                    comp_id = trip.get('company_id')
                    assigned_company = company_map.get(str(comp_id))
                    
                    if assigned_company and assigned_company in counts:
                        counts[assigned_company] += 1
            
            max_trips = max(counts.values()) if counts and max(counts.values()) > 0 else 1
            for idx, (comp, count) in enumerate(counts.items()):
                company_monthly_metrics.append({
                    "id": idx,
                    "company_name": comp,
                    "trip_count": count,
                    "utilization": float(count / max_trips)
                })
        except Exception as table_err:
            print(f"⚠️ Monthly trips completed filter failed: {table_err}")

        analytics = {
            "timeframe": datetime(selected_year, selected_month, 1).strftime('%B %Y'),
            "companies": [],
            "evaluation_participation": {
                "evaluated": 0,
                "passengers": 0,
                "label": "0 out of 0 passengers evaluated"
            },
            "top_driver": None
        }
        try:
            period_trips = supabase.table('trip_schedule').select(
                'trip_id, company_id, passenger_count, user_id'
            ).gte('schedule_date', period_start).lt('schedule_date', period_end).execute().data or []
            trip_ids = [trip['trip_id'] for trip in period_trips if trip.get('trip_id') is not None]
            evaluations = supabase.table('passenger_evaluation').select(
                'trip_id, safety_score, punctuality_score, professionalism_score'
            ).in_('trip_id', trip_ids).execute().data if trip_ids else []
            evaluations = evaluations or []

            company_stats = {}
            for trip in period_trips:
                name = company_map.get(str(trip.get('company_id')), 'Unassigned Company')
                stats = company_stats.setdefault(name, {
                    'company_name': name,
                    'trip_count': 0,
                    'passengers': 0,
                    'evaluated': 0
                })
                stats['trip_count'] += 1
                stats['passengers'] += int(trip.get('passenger_count') or 0)
                stats['evaluated'] += sum(1 for evaluation in evaluations if evaluation.get('trip_id') == trip.get('trip_id'))

            for stats in company_stats.values():
                stats['participation_rate'] = round(
                    stats['evaluated'] / stats['passengers'] * 100, 2
                ) if stats['passengers'] else 0
                stats['participation_label'] = f"{stats['evaluated']} out of {stats['passengers']} passengers evaluated"
            analytics['companies'] = sorted(company_stats.values(), key=lambda item: item['company_name'])
            analytics['evaluation_participation'] = {
                'evaluated': len(evaluations),
                'passengers': sum(int(trip.get('passenger_count') or 0) for trip in period_trips),
                'label': f"{len(evaluations)} out of {sum(int(trip.get('passenger_count') or 0) for trip in period_trips)} passengers evaluated"
            }
            scores_by_driver = {}
            for trip in period_trips:
                driver_id = trip.get('user_id')
                if not driver_id:
                    continue
                for evaluation in evaluations:
                    if evaluation.get('trip_id') != trip.get('trip_id'):
                        continue
                    score = sum(float(evaluation.get(field) or 0) for field in (
                        'safety_score', 'punctuality_score', 'professionalism_score'
                    )) / 3
                    scores_by_driver.setdefault(driver_id, []).append(score)
            if scores_by_driver:
                driver_ids = list(scores_by_driver.keys())
                driver_rows = supabase.table('driver_profile').select(
                    'user_id, full_name'
                ).in_('user_id', driver_ids).execute().data or []
                names = {row.get('user_id'): row.get('full_name') for row in driver_rows}
                leader_id, leader_scores = max(
                    scores_by_driver.items(),
                    key=lambda item: sum(item[1]) / len(item[1])
                )
                analytics['top_driver'] = {
                    'user_id': leader_id,
                    'full_name': names.get(leader_id, 'Unknown Driver'),
                    'rating': round(sum(leader_scores) / len(leader_scores), 2),
                    'evaluation_count': len(leader_scores)
                }
        except Exception as analytics_error:
            print(f"⚠️ Analytics summary failed: {analytics_error}")

        return jsonify({
            "success": True,
            "metrics": {
                "totalDrivers": total_drivers,
                "activeVehicles": active_vehicles,
                "ongoingTrips": ongoing_trips_count,
                "unassignedSchedules": unassigned_count,
                "maintenanceAlerts": maintenance_alerts_count
            },
            "details": {
                "All Drivers": driver_details,
                "Active Vehicles": vehicle_details,
                "Ongoing Trips": ongoing_trip_details,
                "Unscheduled": unassigned_details,
                "Maintenance Alerts": formatted_alerts
            },
            "alerts": formatted_alerts,
            "company_monthly_metrics": company_monthly_metrics,
            "analytics": analytics
        }), 200
    except Exception as e:
        print(f"❌ Dashboard Metrics Engine Failure: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

# ─────────── NEW: MONTHLY DRIVER LEADERBOARD & OVERALL AVERAGE ───────────

@admin_bp.route('/api/dashboard/driver-leaderboard', methods=['GET'])
def get_driver_leaderboard():
    """Fetches top drivers with a unified evaluation loop that correctly handles All-Time and filtered periods."""
    global is_trained, model, scaler
    try:
        if not is_trained:
            try:
                train_driver_classification_model()
            except Exception:
                pass

        raw_period = request.args.get('period', 'all').lower()
        raw_year = request.args.get('year', '0').lower()
        raw_month = request.args.get('month', '0').lower()
        limit_param = request.args.get('limit', '10').lower()
        
        # 1. Grab ALL driver profiles (Guarantees all 41+ show up)
        drivers_res = supabase.table('driver_profile').select('*').limit(5000).execute()
        all_drivers = drivers_res.data or []
        
        driver_scores = {str(d['user_id']): [] for d in all_drivers}
        driver_details = {str(d['user_id']): d for d in all_drivers}

        # 2. Grab ALL trips to map evaluations safely
        trips_res = supabase.table('trip_schedule').select('trip_id, user_id').limit(20000).execute()
        trip_to_driver = {str(t['trip_id']): str(t['user_id']) for t in (trips_res.data or []) if t.get('user_id')}

        # 3. UNIFIED EVALUATION FETCH: Paginate through ALL evaluations cleanly
        raw_evals = []
        batch_size = 1000
        offset = 0
        
        # Determine if we are filtering by date or pulling everything
        is_all_time = (raw_period == 'all' or raw_year == 'all' or raw_year == '0' or not raw_year.isdigit())

        while True:
            evals_query = supabase.table('passenger_evaluation').select('trip_id, safety_score, punctuality_score, professionalism_score, submit_date')
            
            if not is_all_time and raw_year.isdigit():
                selected_year = int(raw_year)
                if raw_month == 'all' or raw_month == '0' or raw_period == 'year':
                    period_start = f"{selected_year}-01-01"
                    period_end = f"{selected_year + 1}-01-01"
                    evals_query = evals_query.gte('submit_date', period_start).lt('submit_date', period_end)
                elif raw_month.isdigit():
                    selected_month = int(raw_month)
                    period_start = f"{selected_year}-{selected_month:02d}-01"
                    if selected_month == 12:
                        period_end = f"{selected_year + 1}-01-01"
                    else:
                        period_end = f"{selected_year}-{selected_month + 1:02d}-01"
                    evals_query = evals_query.gte('submit_date', period_start).lt('submit_date', period_end)

            batch_res = evals_query.range(offset, offset + batch_size - 1).execute()
            batch_data = batch_res.data or []
            
            raw_evals.extend(batch_data)
            
            if len(batch_data) < batch_size:
                break
            offset += batch_size

        all_trip_scores = []
        driver_eval_scores = {str(d['user_id']): [] for d in all_drivers}

        # 4. Match scores to drivers
        for ev in raw_evals:
            t_id = str(ev.get('trip_id'))
            driver_id = trip_to_driver.get(t_id)
            
            if driver_id and driver_id in driver_scores:
                s = float(ev.get('safety_score') if ev.get('safety_score') is not None else 5.0)
                p = float(ev.get('punctuality_score') if ev.get('punctuality_score') is not None else 5.0)
                pr = float(ev.get('professionalism_score') if ev.get('professionalism_score') is not None else 5.0)
                
                eval_avg = (s + p + pr) / 3.0
                all_trip_scores.append(eval_avg)
                driver_scores[driver_id].append(eval_avg)
                driver_eval_scores[driver_id].append({'safety': s, 'punctuality': p, 'professionalism': pr})

        # 5. Auto-classification check
        for d_id, drv in driver_details.items():
            current_ml = drv.get("ml_classification")
            if not current_ml or current_ml == "Pending Sweep" or current_ml == "Needs Review":
                evals_list = driver_eval_scores.get(d_id, [])
                total_evals = len(evals_list)
                
                if total_evals > 0:
                    try:
                        avg_s = sum(e['safety'] for e in evals_list) / total_evals
                        avg_p = sum(e['punctuality'] for e in evals_list) / total_evals
                        avg_pr = sum(e['professionalism'] for e in evals_list) / total_evals
                        
                        if is_trained:
                            live_features = np.array([[avg_s, avg_p, avg_pr, total_evals]])
                            scaled = scaler.transform(live_features)
                            predicted_class = str(model.predict(scaled)[0])
                        else:
                            predicted_class = "Consistent Performer"
                        
                        supabase.table('driver_profile').update({"ml_classification": predicted_class}).eq('user_id', d_id).execute()
                        drv["ml_classification"] = predicted_class
                    except Exception:
                        pass
                else:
                    drv["ml_classification"] = "Pending Sweep"

        # 6. Compile Final Payload
        top_drivers = []
        for d_id, scores in driver_scores.items():
            review_count = len(scores)
            avg_rating = sum(scores) / review_count if review_count > 0 else 0.0
            
            drv_info = driver_details.get(d_id, {})
            license_val = drv_info.get("license_no") or drv_info.get("license_number") or drv_info.get("driver_license") or "N/A"

            top_drivers.append({
                "driver_id": d_id,
                "user_id": d_id,
                "full_name": drv_info.get("full_name") or "Unknown Driver",
                "ml_classification": drv_info.get("ml_classification") or "Pending Sweep",
                "employment_status": drv_info.get("employment_status") or "Active",
                "license_no": license_val,
                "rating": round(avg_rating, 2),
                "review_count": review_count,
                "eval_count": review_count
            })

        # Sort all drivers by Rating -> Total Reviews -> Alphabetical name
        top_drivers.sort(key=lambda x: (x['rating'], x['review_count']), reverse=True)

        # Count EVERY single rated driver across the entire database BEFORE slicing
        total_rated = len([d for d in top_drivers if d['review_count'] > 0])

        # Conditionally slice the list (Returns all 41+ if limit_param is 'all')
        if limit_param != 'all' and limit_param.isdigit():
            display_top_drivers = top_drivers[:int(limit_param)]
        else:
            display_top_drivers = top_drivers

        overall_avg = sum(all_trip_scores) / len(all_trip_scores) if all_trip_scores else 0.0

        return jsonify({
            "success": True,
            "top_drivers": display_top_drivers, 
            "overall_average": round(overall_avg, 2),
            "total_rated_drivers": total_rated 
        }), 200

    except Exception as e:
        print(f"❌ Driver Leaderboard Error: {e}")
        traceback.print_exc()
        return jsonify({"success": False, "error": str(e), "top_drivers": [], "total_rated_drivers": 0, "overall_average": 0.0}), 500

# ─────────── USER INTERFACE ACCOUNT MASTER KEYS ───────────
@admin_bp.route('/api/auth/update-user/<user_id>', methods=['PUT'])
def update_system_user(user_id):
    try:
        data = request.get_json() or {}
        new_email = data.get("email", "").strip().lower()
        raw_role = data.get("role")
        company_name = data.get("company_name")

        role_map = {'Administrator': 'admin', 'Dispatch Staff': 'staff', 'Officer-in-Charge': 'oic'}
        normalized_role = role_map.get(raw_role, 'staff')

        if new_email:
            try:
                admin_supabase = get_admin_client()
                admin_supabase.auth.admin.update_user_by_id(
                    user_id,
                    attributes={"email": new_email, "email_confirm": True}
                )
            except Exception as auth_err:
                print(f"⚠️ Auth Vault Sync bypassed: {auth_err}")

        supabase.table("user_account").update({
            "full_name": data.get("full_name"),
            "username": new_email,
            "role": normalized_role
        }).eq("user_id", user_id).execute()

        if normalized_role == 'oic':
            supabase.table("oic_profile").upsert({
                "user_id": user_id,
                "company_name": company_name
            }).execute()
        else:
            supabase.table("oic_profile").delete().eq("user_id", user_id).execute()

        return jsonify({"success": True, "message": "User profiles synchronized successfully."}), 200
    except Exception as e:
        print(f"❌ System User Update Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500


@admin_bp.route('/api/auth/delete-user/<user_id>', methods=['DELETE'])
def delete_system_user(user_id):
    try:
        supabase.table("oic_profile").delete().eq("user_id", user_id).execute()
        supabase.table("user_account").delete().eq("user_id", user_id).execute()

        try:
            admin_supabase = get_admin_client()
            admin_supabase.auth.admin.delete_user(user_id)
        except Exception as auth_err:
            print(f"⚠️ Auth microservice reference absent or skipped: {auth_err}")

        return jsonify({"success": True, "message": "User accounts entirely removed from records."}), 200
    except Exception as e:
        print(f"❌ System User Deletion Crash: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

# ─────────── CLIENT COMPANY MANAGEMENT ───────────
@admin_bp.route('/api/companies', methods=['GET'])
def get_client_companies():
    """Fetch all registered client companies with assigned-user totals."""
    try:
        res = supabase.table('client_company').select('*').order('company_name', desc=False).execute()
        profiles = supabase.table('oic_profile').select('company_name').execute().data or []
        counts = {}
        for profile in profiles:
            name = profile.get('company_name')
            if name:
                counts[name] = counts.get(name, 0) + 1
        companies = res.data or []
        for company in companies:
            company['user_count'] = counts.get(company.get('company_name'), 0)
        return jsonify({"success": True, "data": companies}), 200
    except Exception as e:
        print(f"❌ Fetch Companies Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500


@admin_bp.route('/api/companies', methods=['POST'])
def add_client_company():
    """Add a new client company."""
    try:
        data = request.get_json() or {}
        name = (data.get('company_name') or '').strip()
        if not name:
            return jsonify({"success": False, "message": "Company name is required."}), 400

        res = supabase.table('client_company').insert({"company_name": name}).execute()
        return jsonify({"success": True, "message": "Company added successfully!", "data": res.data}), 201
    except Exception as e:
        print(f"❌ Add Company Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500


@admin_bp.route('/api/companies/<int:company_id>', methods=['DELETE'])
def delete_client_company(company_id):
    """Delete a company and prevent deletion if referenced."""
    try:
        comp_res = supabase.table('client_company').select('company_name').eq('company_id', company_id).execute()
        if not comp_res.data:
            return jsonify({"success": False, "message": "Company not found."}), 404

        comp_name = comp_res.data[0]['company_name']

        oic_check = supabase.table('oic_profile').select('oic_id').eq('company_name', comp_name).execute()
        if oic_check.data and len(oic_check.data) > 0:
            return jsonify({
                "success": False, 
                "message": f"Cannot delete '{comp_name}' because active Officer-in-Charge profiles are assigned to it."
            }), 400

        supabase.table('client_company').delete().eq('company_id', company_id).execute()
        return jsonify({"success": True, "message": f"'{comp_name}' deleted successfully."}), 200
    except Exception as e:
        print(f"❌ Delete Company Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500