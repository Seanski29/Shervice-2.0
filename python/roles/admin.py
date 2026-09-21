import os
from io import BytesIO
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple
import traceback
import re
import numpy as np

from flask import Blueprint, jsonify, request
from supabase import create_client

try:
    from driver_ml import is_trained, train_driver_classification_model, model, scaler
except ImportError:
    is_trained = False

import xlrd
from openpyxl import Workbook

admin_bp = Blueprint('admin', __name__)
supabase = None

def get_admin_client():
    admin_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not admin_key or admin_key == "your_service_role_key_here":
        raise RuntimeError("Missing SUPABASE_SERVICE_ROLE_KEY for admin auth operations.")
    return create_client(os.getenv("SUPABASE_URL"), admin_key)

def _normalize_xls_cell(value: Any, cell_type: Optional[int] = None, datemode: int = 0) -> Any:
    if value is None:
        return ""
    if cell_type == xlrd.XL_CELL_DATE:
        try:
            parsed = xlrd.xldate_as_datetime(value, datemode)
            if parsed.date().isoformat() == "1899-12-31":
                return parsed.strftime("%H:%M")
            if parsed.hour or parsed.minute or parsed.second:
                return parsed.strftime("%Y-%m-%d %H:%M:%S")
            return parsed.date().isoformat()
        except (ValueError, TypeError, OverflowError):
            pass
    if isinstance(value, float):
        if value.is_integer():
            return str(int(value))
        return str(value)
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return str(value).strip()

def parse_legacy_xls_bytes(file_bytes: bytes) -> Dict[str, Any]:
    try:
        workbook = xlrd.open_workbook(file_contents=file_bytes)
        sheet = workbook.sheet_by_index(0)

        rows: List[List[Any]] = []
        for row_idx in range(sheet.nrows):
            values = []
            for col_idx in range(sheet.ncols):
                values.append(
                    _normalize_xls_cell(
                        sheet.cell_value(row_idx, col_idx),
                        sheet.cell_type(row_idx, col_idx),
                        workbook.datemode,
                    )
                )
            rows.append(values)

        if not rows:
            return {"success": False, "error": "Uploaded file has no rows."}

        headers = []
        for index, header in enumerate(rows[0]):
            normalized = _normalize_xls_cell(header)
            headers.append(normalized or f"Column {index + 1}")

        has_table_header = any(
            str(header).strip().lower()
            in {"employee id", "employee name", "employee", "date", "time in"}
            for header in headers
        )

        data_rows: List[Any] = []
        for row in rows[1:]:
            record = {}
            for index, header in enumerate(headers):
                value = row[index] if index < len(row) else ""
                record[header] = _normalize_xls_cell(value)
            if any(str(value).strip() for value in record.values()):
                data_rows.append(record if has_table_header else row)

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


def _clean_attendance_value(value: Any) -> str:
    normalized = _normalize_xls_cell(value).strip()
    return "" if normalized.lower() in {"", "nan", "null", "none"} else normalized


def _coerce_attendance_date(value: Any) -> Optional[str]:
    raw = _clean_attendance_value(value)
    if not raw:
        return None

    raw = raw.split("T")[0].strip()
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%d/%m/%Y", "%d/%m/%y"):
        try:
            return datetime.strptime(raw, fmt).date().isoformat()
        except ValueError:
            continue

    try:
        return datetime.fromisoformat(raw).date().isoformat()
    except ValueError:
        return None


def _split_employee_label(label: str) -> Tuple[str, str]:
    match = re.match(r"^(.*?)\s*\((.*?)\)\s*$", label.strip())
    if not match:
        return label.strip(), ""
    return match.group(1).strip(), match.group(2).strip()


def _attendance_int(value: Any) -> int:
    try:
        return int(float(_clean_attendance_value(value) or 0))
    except (TypeError, ValueError):
        return 0


def _attendance_driver_id(value: Any) -> Optional[int]:
    raw = _clean_attendance_value(value)
    if not raw:
        return None
    match = re.search(r"\d+", raw)
    if not match:
        return None
    try:
        return int(match.group(0))
    except ValueError:
        return None


def _attendance_payload_from_row(
    row: Dict[str, Any],
    source_file: str,
    valid_driver_ids: Optional[set[int]] = None,
) -> Dict[str, Any]:
    employee_label = _clean_attendance_value(
        row.get("employee")
        or row.get("employee_name")
        or row.get("name")
        or row.get("Employee")
        or row.get("Employee Name")
    )
    employee_name, employee_id = _split_employee_label(employee_label)
    employee_id = employee_id or _clean_attendance_value(
        row.get("employee_id") or row.get("Employee ID")
    )
    candidate_driver_id = _attendance_driver_id(employee_id)
    driver_id = (
        candidate_driver_id
        if candidate_driver_id is not None
        and (valid_driver_ids is None or candidate_driver_id in valid_driver_ids)
        else None
    )
    raw_date = _clean_attendance_value(row.get("date") or row.get("work_date") or row.get("Date"))

    return {
        "driver_id": driver_id,
        "employee_name": employee_name or "Unknown",
        "employee_id": employee_id or None,
        "pay_period": _clean_attendance_value(row.get("pay_period") or row.get("Pay Period")) or None,
        "day_label": _clean_attendance_value(row.get("day") or row.get("Day")) or None,
        "work_date": _coerce_attendance_date(raw_date),
        "raw_date": raw_date or None,
        "time_in": _clean_attendance_value(row.get("in_time") or row.get("time_in") or row.get("IN") or row.get("Time In")) or None,
        "time_out": _clean_attendance_value(row.get("out_time") or row.get("time_out") or row.get("OUT") or row.get("Time Out")) or None,
        "work_time": _clean_attendance_value(row.get("work_time") or row.get("work_hours") or row.get("Work Time")) or None,
        "daily_total": _clean_attendance_value(row.get("daily_total") or row.get("total_hours") or row.get("Daily Total")) or None,
        "morning_in": _clean_attendance_value(row.get("morning_in") or row.get("Morning IN")) or None,
        "morning_out": _clean_attendance_value(row.get("morning_out") or row.get("Morning OUT")) or None,
        "afternoon_in": _clean_attendance_value(row.get("afternoon_in") or row.get("Afternoon IN")) or None,
        "afternoon_out": _clean_attendance_value(row.get("afternoon_out") or row.get("Afternoon OUT")) or None,
        "overtime_in": _clean_attendance_value(row.get("overtime_in") or row.get("Overtime IN")) or None,
        "overtime_out": _clean_attendance_value(row.get("overtime_out") or row.get("Overtime OUT")) or None,
        "total_minutes_late": _attendance_int(row.get("total_minutes_late") or row.get("Total Minutes Late")),
        "note": _clean_attendance_value(row.get("note") or row.get("notes") or row.get("remarks") or row.get("Note")) or None,
        "source_file": source_file or None,
        "raw_payload": row,
    }


def _save_attendance_rows(rows: List[Dict[str, Any]], source_file: str) -> List[Dict[str, Any]]:
    candidate_driver_ids = {
        driver_id
        for row in rows
        if isinstance(row, dict)
        for driver_id in [_attendance_driver_id(row.get("employee_id") or row.get("employee") or row.get("Employee ID"))]
        if driver_id is not None
    }
    valid_driver_ids: set[int] = set()
    if candidate_driver_ids:
        drivers = (
            supabase.table("driver_profile")
            .select("driver_id")
            .in_("driver_id", list(candidate_driver_ids))
            .execute()
        )
        valid_driver_ids = {
            int(row["driver_id"])
            for row in (drivers.data or [])
            if row.get("driver_id") is not None
        }

    payloads = [
        _attendance_payload_from_row(row, source_file, valid_driver_ids)
        for row in rows
        if isinstance(row, dict)
    ]
    payloads = [
        row
        for row in payloads
        if row["employee_name"] != "Unknown" or row["work_date"] or row["time_in"] or row["time_out"]
    ]

    if not payloads:
        return []

    result = supabase.table("attendance_record").upsert(
        payloads,
        on_conflict="source_file,employee_name,work_date,time_in,time_out",
    ).execute()
    return result.data or []


@admin_bp.route('/api/test-db', methods=['GET'])
@admin_bp.route('/driver/all', methods=['GET'])
def diagnostic_database_check():
    try:
        driver_query = supabase.table('driver_profile').select(
            'driver_id, full_name, birthday, phone_no, date_hired, '
            'employment_status, is_backup, ml_classification'
        ).limit(10000).execute()
        raw_data = driver_query.data or []

        evals_query = supabase.table('evaluation').select('driver_id, safety_score, punctuality_score, professionalism_score').limit(10000).execute()
        
        driver_scores = {}
        for ev in evals_query.data or []:
            driver_id = ev.get('driver_id')
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
            row['username'] = ''
            
            if not row.get('phone_no'):
                row['phone_no'] = '09123456789'
                
            d_id = row.get('driver_id')
            scores = driver_scores.get(d_id, [])
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
    
@admin_bp.route('/trips', methods=['GET'])
@admin_bp.route('/api/trips', methods=['GET'])
def get_admin_schedules():
    try:
        query = supabase.table('trip_schedule').select(
            'trip_id, schedule_date, departure_time, route_name, '
            'passenger_count, estimated_arrival_time, company_id, '
            'vehicle_id, vehicle(plate_number, bus_type), '
            'driver_id, user_account(full_name)'
        )

        # Apply the year filter so the DB doesn't cut off data at 1000 rows
        year_param = request.args.get('year')
        if year_param and year_param.isdigit():
            query = query.gte('schedule_date', f'{year_param}-01-01').lt('schedule_date', f'{int(year_param)+1}-01-01')

        # Limit safely increased to 10000 for heavy payloads
        trips_res = query.order('schedule_date', desc=False).limit(10000).execute()
        raw_trips = trips_res.data or []

        clients_res = supabase.table('client_company').select('company_id, company_name').execute()
        company_map = {
            str(c['company_id']): c['company_name'] 
            for c in (clients_res.data or []) 
            if c.get('company_id') is not None
        }

        # Safe limit for evaluations
        evals_res = supabase.table('evaluation').select('trip_id, safety_score, punctuality_score, professionalism_score').limit(10000).execute()
        
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

@admin_bp.route('/api/admin/attendance/upload-legacy-xls', methods=['POST'])
@admin_bp.route('/api/staff/attendance/upload-legacy-xls', methods=['POST'])
def upload_legacy_xls_attendance():
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


@admin_bp.route('/api/admin/attendance', methods=['GET'])
@admin_bp.route('/api/staff/attendance', methods=['GET'])
@admin_bp.route('/api/admin/timecards', methods=['GET'])
@admin_bp.route('/api/staff/timecards', methods=['GET'])
def get_attendance_records():
    try:
        result = (
            supabase.table("attendance_record")
            .select(
                "attendance_id, driver_id, employee_id, employee_name, work_date, "
                "raw_date, pay_period, day_label, morning_in, morning_out, afternoon_in, "
                "afternoon_out, overtime_in, overtime_out, time_in, time_out, "
                "work_time, daily_total, note, total_minutes_late, source_file, "
                "created_at"
            )
            .order("work_date", desc=True)
            .order("created_at", desc=True)
            .limit(10000)
            .execute()
        )
        return jsonify({
            "success": True,
            "data": result.data or [],
            "attendance": result.data or [],
        }), 200
    except Exception as exc:
        return jsonify({"success": False, "error": f"Unable to load attendance records: {exc}"}), 500


@admin_bp.route('/api/admin/attendance/import', methods=['POST'])
@admin_bp.route('/api/staff/attendance/import', methods=['POST'])
def import_attendance_records():
    try:
        payload = request.get_json(silent=True) or {}
        rows = payload.get("rows") or []
        source_file = _clean_attendance_value(payload.get("source_file")) or "Imported attendance"

        if not isinstance(rows, list):
            return jsonify({"success": False, "error": "Rows must be a list."}), 400

        saved_rows = _save_attendance_rows(rows, source_file)
        return jsonify({
            "success": True,
            "saved_count": len(saved_rows),
            "data": saved_rows,
        }), 200
    except Exception as exc:
        return jsonify({"success": False, "error": f"Unable to save attendance import: {exc}"}), 500


@admin_bp.route('/api/dashboard/metrics', methods=['GET'])
def get_dashboard_metrics():
    def safe_query(label, query, default=None):
        try:
            result = query()
            return result.data or default or []
        except Exception as query_error:
            print(f"Dashboard metrics query failed for {label}: {query_error}")
            return default or []

    try:
        # FIX: Removed 'user_id' from the select statement and removed the separate user mapping
        all_drivers = safe_query(
            'driver_profile',
            lambda: supabase.table('driver_profile').select(
                'driver_id, full_name, phone_no, employment_status, date_hired, birthday'
            ).execute()
        )
        
        total_drivers = len(all_drivers)
        active_driver_rows = [
            driver for driver in all_drivers
            if str(driver.get('employment_status') or 'Active').strip().lower() == 'active'
        ]
        active_drivers_count = len(active_driver_rows)
        
        driver_details = [
            {
                "label": driver.get('full_name') or f"Driver {driver.get('driver_id', 'Unknown')}",
                "driver_id": driver.get('driver_id'),
                "phone_no": driver.get('phone_no', '09123456789'),
                "employment_status": driver.get('employment_status', 'Active'),
                "date_hired": driver.get('date_hired'),
                "birthday": driver.get('birthday')
            }
            for driver in all_drivers
        ]

        available_vehicles = safe_query(
            'available vehicles',
            lambda: supabase.table('vehicle')
            .select('vehicle_id, plate_number')
            .eq('is_available', True)
            .execute()
        )
        active_vehicles = len(available_vehicles)
        vehicle_details = [
            {"label": vehicle.get('plate_number') or f"Vehicle {vehicle.get('vehicle_id', 'Unknown')}"}
            for vehicle in available_vehicles
        ]

        unavailable_vehicles = safe_query(
            'maintenance vehicle count',
            lambda: supabase.table('vehicle')
            .select('vehicle_id')
            .eq('is_available', False)
            .execute()
        )
        maintenance_alerts_count = len(unavailable_vehicles)

        alerts_log = safe_query(
            'maintenance alert logs',
            lambda: supabase.table('maintenance_log')
            .select('maintenance_id, description, vehicle_id, vehicle(plate_number)')
            .order('repair_date', desc=True)
            .limit(100)
            .execute()
        )

        formatted_alerts = []
        for log in alerts_log:
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

        selected_month = int(request.args.get('month', datetime.now().month))
        selected_year = int(request.args.get('year', datetime.now().year))
        if selected_month < 1 or selected_month > 12:
            selected_month = datetime.now().month
        period_start_dt = datetime(selected_year, selected_month, 1)
        if selected_month == 12:
            period_end_dt = datetime(selected_year + 1, 1, 1)
        else:
            period_end_dt = datetime(selected_year, selected_month + 1, 1)
        period_start = period_start_dt.date().isoformat()
        period_end = period_end_dt.date().isoformat()

        monthly_trips = safe_query(
            'monthly trips',
            lambda: supabase.table('trip_schedule')
            .select('trip_id, passenger_count, route_name, schedule_date')
            .gte('schedule_date', period_start)
            .lt('schedule_date', period_end)
            .execute()
        )
        total_trips_count = len(monthly_trips)
        total_passengers_count = sum(int(trip.get('passenger_count') or 0) for trip in monthly_trips)
        total_trip_details = [
            {
                "label": f"Trip {trip.get('trip_id', 'Unknown')}",
                "status": trip.get('route_name') or 'Recorded trip',
                "schedule_date": trip.get('schedule_date'),
            }
            for trip in monthly_trips
        ]
        passenger_details = [
            {
                "label": trip.get('route_name') or f"Trip {trip.get('trip_id', 'Unknown')}",
                "status": f"{int(trip.get('passenger_count') or 0)} passengers",
                "schedule_date": trip.get('schedule_date'),
            }
            for trip in monthly_trips
        ]

        monthly_maintenance = safe_query(
            'monthly maintenance',
            lambda: supabase.table('maintenance_log')
            .select('maintenance_id, description, repair_date, incident_date, vehicle_id, vehicle(plate_number)')
            .gte('repair_date', period_start)
            .lt('repair_date', period_end)
            .execute()
        )
        monthly_maintenance_count = len(monthly_maintenance)
        monthly_maintenance_details = []
        for log in monthly_maintenance:
            vehicle = log.get('vehicle') or {}
            if isinstance(vehicle, list):
                vehicle = vehicle[0] if vehicle else {}
            monthly_maintenance_details.append({
                "label": vehicle.get('plate_number') or f"Asset {log.get('vehicle_id', 'Unknown')}",
                "status": log.get('repair_date') or log.get('incident_date') or '',
                "description": log.get('description') or 'Maintenance record',
            })

        company_monthly_metrics = []
        company_map = {}
        try:
            companies_fetch = supabase.table('client_company').select('company_id, company_name').execute()
            
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
                .select('trip_id, company_id')\
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
                "label": "0 evaluations recorded"
            },
            "top_driver": None
        }
        try:
            period_trips = supabase.table('trip_schedule').select(
                'trip_id, company_id, passenger_count, driver_id'
            ).gte('schedule_date', period_start).lt('schedule_date', period_end).execute().data or []
            
            evaluations = supabase.table('evaluation').select(
                'driver_id, safety_score, punctuality_score, professionalism_score'
            ).gte('submit_date', period_start).lt('submit_date', period_end).execute().data or []

            company_stats = {}
            for trip in period_trips:
                name = company_map.get(str(trip.get('company_id')), 'Unassigned Company')
                stats = company_stats.setdefault(name, {
                    'company_name': name,
                    'trip_count': 0,
                    'passengers': 0,
                })
                stats['trip_count'] += 1
                stats['passengers'] += int(trip.get('passenger_count') or 0)

            analytics['companies'] = sorted(company_stats.values(), key=lambda item: item['company_name'])
            analytics['evaluation_participation'] = {
                'evaluated': len(evaluations),
                'passengers': sum(int(trip.get('passenger_count') or 0) for trip in period_trips),
                'label': f"{len(evaluations)} staff evaluations logged this period."
            }
            scores_by_driver = {}
            for evaluation in evaluations:
                driver_id = evaluation.get('driver_id')
                if not driver_id: continue
                score = sum(float(evaluation.get(field) or 0) for field in (
                    'safety_score', 'punctuality_score', 'professionalism_score'
                )) / 3
                scores_by_driver.setdefault(driver_id, []).append(score)
                
            if scores_by_driver:
                driver_ids = list(scores_by_driver.keys())
                driver_rows = supabase.table('driver_profile').select(
                    'driver_id, full_name'
                ).in_('driver_id', driver_ids).execute().data or []
                names = {row.get('driver_id'): row.get('full_name') for row in driver_rows}
                leader_id, leader_scores = max(
                    scores_by_driver.items(),
                    key=lambda item: sum(item[1]) / len(item[1])
                )
                analytics['top_driver'] = {
                    'driver_id': leader_id,
                    'full_name': names.get(leader_id, 'Unknown Driver'),
                    'rating': round(sum(leader_scores) / len(leader_scores), 2),
                    'evaluation_count': len(leader_scores)
                }
        except Exception as analytics_error:
            print(f"⚠️ Analytics summary failed: {analytics_error}")

        return jsonify({
            "success": True,
            "metrics": {
                "totalTrips": total_trips_count,
                "monthlyMaintenance": monthly_maintenance_count,
                "totalPassengers": total_passengers_count,
                "activeDrivers": active_drivers_count,
                "totalDrivers": total_drivers,
                "activeVehicles": active_vehicles,
                "maintenanceAlerts": maintenance_alerts_count
            },
            "details": {
                "Total Trips": total_trip_details,
                "Monthly Maintenance": monthly_maintenance_details,
                "Total Passengers": passenger_details,
                "Active Drivers": [
                    detail for detail in driver_details
                    if str(detail.get('employment_status') or 'Active').strip().lower() == 'active'
                ],
                "All Drivers": driver_details,
                "Active Vehicles": vehicle_details,
                "Maintenance Alerts": formatted_alerts
            },
            "alerts": formatted_alerts,
            "company_monthly_metrics": company_monthly_metrics,
            "analytics": analytics
        }), 200
    except Exception as e:
        print(f"❌ Dashboard Metrics Engine Failure: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@admin_bp.route('/api/dashboard/driver-leaderboard', methods=['GET'])
def get_driver_leaderboard():
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
        
        drivers_res = supabase.table('driver_profile').select(
            'driver_id, full_name, phone_no, employment_status, ml_classification'
        ).limit(5000).execute()
        all_drivers = drivers_res.data or []
        
        driver_scores = {d['driver_id']: [] for d in all_drivers if d.get('driver_id') is not None}
        driver_details = {d['driver_id']: d for d in all_drivers if d.get('driver_id') is not None}

        raw_evals = []
        batch_size = 1000
        offset = 0
        
        is_all_time = (raw_period == 'all' or raw_year == 'all' or raw_year == '0' or not raw_year.isdigit())

        while True:
            evals_query = supabase.table('evaluation').select('driver_id, safety_score, punctuality_score, professionalism_score, submit_date')
            
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
        driver_eval_scores = {d['driver_id']: [] for d in all_drivers if d.get('driver_id') is not None}

        for ev in raw_evals:
            driver_id = ev.get('driver_id')
            
            if driver_id and driver_id in driver_scores:
                s = float(ev.get('safety_score') if ev.get('safety_score') is not None else 5.0)
                p = float(ev.get('punctuality_score') if ev.get('punctuality_score') is not None else 5.0)
                pr = float(ev.get('professionalism_score') if ev.get('professionalism_score') is not None else 5.0)
                
                eval_avg = (s + p + pr) / 3.0
                all_trip_scores.append(eval_avg)
                driver_scores[driver_id].append(eval_avg)
                driver_eval_scores[driver_id].append({'safety': s, 'punctuality': p, 'professionalism': pr})

        top_drivers = []
        for d_id, scores in driver_scores.items():
            review_count = len(scores)
            avg_rating = sum(scores) / review_count if review_count > 0 else 0.0
            
            drv_info = driver_details.get(d_id, {})
            phone_val = drv_info.get("phone_no") or "09123456789"

            top_drivers.append({
                "driver_id": d_id,
                "full_name": drv_info.get("full_name") or "Unknown Driver",
                "ml_classification": drv_info.get("ml_classification") or "Pending Sweep",
                "employment_status": drv_info.get("employment_status") or "Active",
                "phone_no": phone_val,
                "rating": round(avg_rating, 2),
                "review_count": review_count,
                "eval_count": review_count
            })

        top_drivers.sort(key=lambda x: (x['rating'], x['review_count']), reverse=True)
        total_rated = len([d for d in top_drivers if d['review_count'] > 0])

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

@admin_bp.route('/api/auth/update-user/<user_id>', methods=['PUT'])
def update_system_user(user_id):
    try:
        data = request.get_json() or {}
        account = supabase.table("user_account").select("user_id").eq(
            "staff_id", user_id
        ).maybe_single().execute().data or {}
        auth_user_id = account.get("user_id") or user_id
        new_email = data.get("email", "").strip().lower()
        raw_role = data.get("role")
        role_map = {'Dispatch Staff': 'staff'}
        normalized_role = role_map.get(raw_role, 'staff')

        if new_email:
            try:
                admin_supabase = get_admin_client()
                admin_supabase.auth.admin.update_user_by_id(
                    auth_user_id,
                    attributes={"email": new_email, "email_confirm": True}
                )
            except Exception as auth_err:
                print(f"⚠️ Auth Vault Sync bypassed: {auth_err}")

        supabase.table("user_account").update({
            "full_name": data.get("full_name"),
            "username": new_email,
            "role": normalized_role
        }).eq("staff_id", user_id).execute()

        return jsonify({"success": True, "message": "User profiles synchronized successfully."}), 200
    except Exception as e:
        print(f"❌ System User Update Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@admin_bp.route('/api/auth/delete-user/<user_id>', methods=['DELETE'])
def delete_system_user(user_id):
    try:
        account = supabase.table("user_account").select("user_id").eq(
            "staff_id", user_id
        ).maybe_single().execute().data or {}
        auth_user_id = account.get("user_id") or user_id
        supabase.table("user_account").delete().eq("staff_id", user_id).execute()

        try:
            admin_supabase = get_admin_client()
            admin_supabase.auth.admin.delete_user(auth_user_id)
        except Exception as auth_err:
            print(f"⚠️ Auth microservice reference absent or skipped: {auth_err}")

        return jsonify({"success": True, "message": "User accounts entirely removed from records."}), 200
    except Exception as e:
        print(f"❌ System User Deletion Crash: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@admin_bp.route('/api/companies', methods=['GET'])
def get_client_companies():
    try:
        res = supabase.table('client_company').select('*').order('company_name', desc=False).execute()
        companies = res.data or []
        for company in companies:
            company['user_count'] = 0
        return jsonify({"success": True, "data": companies}), 200
    except Exception as e:
        print(f"❌ Fetch Companies Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@admin_bp.route('/api/companies', methods=['POST'])
def add_client_company():
    try:
        data = request.get_json() or {}
        name = (data.get('company_name') or '').strip()
        if not name:
            return jsonify({"success": False, "message": "Company name is required."}), 400

        address = (data.get('address') or '').strip()
        if not address:
            return jsonify({"success": False, "message": "Company address is required."}), 400

        res = supabase.table('client_company').insert({"company_name": name, "address": address}).execute()
        return jsonify({"success": True, "message": "Company added successfully!", "data": res.data}), 201
    except Exception as e:
        print(f"❌ Add Company Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@admin_bp.route('/api/companies/<int:company_id>', methods=['DELETE'])
def delete_client_company(company_id):
    try:
        comp_res = supabase.table('client_company').select('company_name').eq('company_id', company_id).execute()
        if not comp_res.data:
            return jsonify({"success": False, "message": "Company not found."}), 404

        comp_name = comp_res.data[0]['company_name']

        supabase.table('trip_schedule').update({
            "company_id": None
        }).eq('company_id', company_id).execute()

        supabase.table('client_company').delete().eq('company_id', company_id).execute()
        return jsonify({"success": True, "message": f"'{comp_name}' deleted successfully."}), 200
    except Exception as e:
        print(f"❌ Delete Company Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@admin_bp.route('/api/companies/<int:company_id>', methods=['PUT'])
def update_client_company(company_id):
    try:
        data = request.get_json() or {}
        name = (data.get('company_name') or '').strip()
        address = (data.get('address') or '').strip()
        if not name or not address:
            return jsonify({'success': False, 'message': 'Company name and address are required.'}), 400

        result = supabase.table('client_company').update({
            'company_name': name,
            'address': address,
        }).eq('company_id', company_id).execute()
        if not result.data:
            return jsonify({'success': False, 'message': 'Company not found.'}), 404
        return jsonify({'success': True, 'data': result.data}), 200
    except Exception as e:
        print(f"Company update error: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500
