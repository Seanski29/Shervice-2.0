from flask import Blueprint, request, jsonify
from .notifs import trigger_notification

# Create the Blueprint for vehicle routes
vehicles_bp = Blueprint('vehicles', __name__)

# This will be assigned dynamically in app.py
supabase = None 

@vehicles_bp.route('/api/vehicles', methods=['GET', 'POST'])
def handle_vehicles():
    """Handles fetching all vehicles (GET) and registering a new vehicle (POST)"""
    try:
        if request.method == 'POST':
            data = request.get_json() or {}
            def clean_field(val):
                if val is None: return None
                cleaned = str(val).strip()
                return cleaned if cleaned != "" and cleaned.lower() != "n/a" else None

            def to_int(val):
                cleaned = clean_field(val)
                return int(cleaned) if cleaned and cleaned.isdigit() else None

            new_vehicle = {
                "plate_number": clean_field(data.get('plate_number')),
                "bus_type": clean_field(data.get('bus_type')) or 'Standard Shuttle',
                "model_year": to_int(data.get('model_year')),
                "engine_no": clean_field(data.get('engine_no')),
                "insurance_policy_no": clean_field(data.get('insurance_policy_no')),
                "insurance_expiry": clean_field(data.get('insurance_expiry')),
                "franchise_no": clean_field(data.get('franchise_no')),
                "franchise_expiry": clean_field(data.get('franchise_expiry')),
                "cr_no": clean_field(data.get('cr_no')),
                "cr_date": clean_field(data.get('cr_date')),
                "or_no": clean_field(data.get('or_no')),
                "or_expiry": clean_field(data.get('or_expiry')),
                "health_status": "Good",
                "is_available": True,
                "last_maintenance_description": "No recent service entries registered."
            }

            if not new_vehicle["plate_number"]:
                return jsonify({"success": False, "message": "Plate number is required."}), 400

            query = supabase.table('vehicle').insert(new_vehicle).execute()
            return jsonify({"success": True, "message": "Vehicle registered securely!", "data": query.data}), 201

        query = supabase.table('vehicle').select('*').order('plate_number').execute()
        vehicles = query.data or []
        logs = supabase.table('maintenance_log').select(
            'vehicle_id, incident_date, repair_date, is_resolved'
        ).order('repair_date', desc=True).execute().data or []
        
        target_dates = {}
        for log in logs:
            if log.get('is_resolved') is False and log.get('vehicle_id') not in target_dates:
                target_dates[log.get('vehicle_id')] = log.get('incident_date') or log.get('repair_date')
                
        for vehicle in vehicles:
            vehicle['needs_attention'] = (
                not vehicle.get('is_available', True) or
                'maintenance' in str(vehicle.get('health_status', '')).lower() or
                'repair' in str(vehicle.get('health_status', '')).lower()
            )
            vehicle['maintenance_target_date'] = target_dates.get(vehicle.get('vehicle_id'))
            
        return jsonify({"success": True, "data": vehicles}), 200
    except Exception as e:
        print(f"❌ Exception: {e}")
        return jsonify({"success": False, "message": str(e)}), 500


@vehicles_bp.route('/api/vehicles/<string:vehicle_identifier>', methods=['DELETE'])
def delete_vehicle(vehicle_identifier):
    try:
        is_numeric = vehicle_identifier.isdigit()
        try:
            if is_numeric:
                supabase.table('maintenance_log').delete().eq('vehicle_id', int(vehicle_identifier)).execute()
            else:
                vehicle_data = supabase.table('vehicle').select('vehicle_id').eq('plate_number', vehicle_identifier).execute()
                if vehicle_data.data:
                    supabase.table('maintenance_log').delete().eq('vehicle_id', vehicle_data.data[0]['vehicle_id']).execute()
        except Exception as log_err:
            print(f"⚠️ Log clear warning: {log_err}")
        
        for table_name in ['schedules', 'schedule']:
            try:
                if is_numeric:
                    supabase.table(table_name).update({"vehicle_id": None}).eq('vehicle_id', int(vehicle_identifier)).execute()
                else:
                    vehicle_data = supabase.table('vehicle').select('vehicle_id').eq('plate_number', vehicle_identifier).execute()
                    if vehicle_data.data:
                        supabase.table(table_name).update({"vehicle_id": None}).eq('vehicle_id', vehicle_data.data[0]['vehicle_id']).execute()
            except Exception:
                pass

        if is_numeric:
            supabase.table('vehicle').delete().eq('vehicle_id', int(vehicle_identifier)).execute()
        else:
            supabase.table('vehicle').delete().eq('plate_number', vehicle_identifier).execute()
            
        return jsonify({"success": True, "message": "Erased from fleet records."}), 200
    except Exception as e:
        print(f"❌ Deletion error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500


@vehicles_bp.route('/api/vehicles/maintenance', methods=['GET'])
def get_maintenance_logs():
    try:
        query = supabase.table('maintenance_log').select(
            'maintenance_id, repair_date, description, vehicle_id, user_id, category, incident_date, incident_time, repair_time, is_resolved, vehicle(plate_number), user_account(full_name)'
        ).order('repair_date', desc=True).execute()
        
        return jsonify({"success": True, "data": query.data}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


# ─────────── UPGRADED MAINTENANCE LOGGING (ROLLOVER LOGIC) ───────────

@vehicles_bp.route('/api/vehicles/maintenance', methods=['POST'])
def add_maintenance_log():
    try:
        data = request.get_json() or {}
        target_vehicle_id = int(data.get('vehicle_id'))
        
        # Grab the toggle value
        is_resolved = data.get('is_resolved', True)

        # Prepare the new log entry
        new_log = {
            "repair_date": data.get('repair_date'), 
            "description": data.get('description', ''), 
            "vehicle_id": target_vehicle_id, 
            "user_id": data.get('user_id'),
            "category": data.get('category', 'General'),
            "incident_date": data.get('incident_date'),
            "incident_time": data.get('incident_time'),
            "repair_time": data.get('repair_time'),
            "is_resolved": is_resolved
        }

        if not new_log["description"] or not new_log["vehicle_id"] or not new_log.get("user_id"):
            return jsonify({"success": False, "message": "Missing required fields."}), 400

        # ✅ Insert the updated fresh maintenance record to the history
        supabase.table('maintenance_log').insert(new_log).execute()
        
        # ✅ Handle Status and Availability Changes based on the Toggle
        if is_resolved:
            updated_health = 'Good'
            is_available = True
        else:
            updated_health = 'Needs Maintenance'
            is_available = False

        supabase.table('vehicle').update({
            "health_status": updated_health, 
            "is_available": is_available, 
            "last_maintenance_description": new_log["description"]
        }).eq('vehicle_id', target_vehicle_id).execute()

        # ✅ Fetch plate number for the notification message
        veh_res = supabase.table('vehicle').select('plate_number').eq('vehicle_id', target_vehicle_id).execute()
        plate_number = veh_res.data[0]['plate_number'] if veh_res.data else f"ID {target_vehicle_id}"

        # Build a detailed, multi-line message
        status_text = "Repaired / Resolved" if is_resolved else "Ongoing / Needs Attention"
        detailed_message = (
            f"Vehicle {plate_number} has a new maintenance record.\n\n"
            f"Category: {new_log['category']}\n"
            f"Status: {status_text}\n"
            f"Notes: {new_log['description']}"
        )

        # ✅ Trigger the notification across all requested roles
        roles_to_notify = ["admin", "staff", "oic"]
        for target_role in roles_to_notify:
            trigger_notification(
                title="New Maintenance Log",
                message=detailed_message,
                target_role=target_role,
                source_tag="maintenance",
                db_client=supabase
            )

        return jsonify({"success": True, "message": "Maintenance log added to history successfully!"}), 201
    except Exception as e:
        print(f"❌ Maintenance Logging failure: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@vehicles_bp.route('/api/vehicles/maintenance', methods=['PUT'])
def update_maintenance_log():
    """Updates an 'Ongoing' maintenance log to 'Repaired'"""
    try:
        data = request.get_json() or {}
        maintenance_id = data.get('maintenance_id')
        vehicle_id = data.get('vehicle_id')
        
        if not maintenance_id or not vehicle_id:
            return jsonify({"success": False, "message": "Missing required maintenance or vehicle ID."}), 400

        # 1. Update the existing log with the repair details and mark as resolved
        update_data = {
            "repair_date": data.get('repair_date'),
            "repair_time": data.get('repair_time'),
            "is_resolved": True  # Changes the status from Ongoing to Repaired
        }
        
        supabase.table('maintenance_log').update(update_data).eq('maintenance_id', maintenance_id).execute()
        
        # 2. Release the vehicle back to the active dispatch fleet
        supabase.table('vehicle').update({
            "health_status": "Good",
            "is_available": True
        }).eq('vehicle_id', vehicle_id).execute()

        # ✅ Notify roles when a vehicle is repaired
        veh_res = supabase.table('vehicle').select('plate_number').eq('vehicle_id', vehicle_id).execute()
        plate_number = veh_res.data[0]['plate_number'] if veh_res.data else f"ID {vehicle_id}"

        # Build a detailed completion message
        repair_date = data.get('repair_date', 'N/A')
        repair_time = data.get('repair_time', 'N/A')
        completion_message = (
            f"Vehicle {plate_number} has been marked as repaired and is available for dispatch.\n\n"
            f"Date Completed: {repair_date}\n"
            f"Time Completed: {repair_time}"
        )

        roles_to_notify = ["admin", "staff", "oic"]
        for target_role in roles_to_notify:
            trigger_notification(
                title="Vehicle Repaired",
                message=completion_message,
                target_role=target_role,
                source_tag="maintenance",
                db_client=supabase
            )

        return jsonify({"success": True, "message": "Vehicle marked as repaired and ready for dispatch!"}), 200
        
    except Exception as e:
        print(f"❌ Maintenance Update failure: {e}")
        return jsonify({"success": False, "message": str(e)}), 500