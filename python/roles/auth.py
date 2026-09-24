import os
import logging
import re
from typing import Any, Dict, Optional, cast
from flask import Blueprint, jsonify, request
from supabase import create_client

auth_bp = Blueprint('auth', __name__)

supabase = None 
logger = logging.getLogger(__name__)
EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
PHONE_PATTERN = re.compile(r"^[0-9+\-\s()]{7,20}$")
ALLOWED_DRIVER_STATUSES = {"Active", "On Leave", "Suspended", "Absent"}

def get_admin_client():
    admin_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not admin_key or admin_key == "your_service_role_key_here":
        raise RuntimeError("Missing SUPABASE_SERVICE_ROLE_KEY for admin auth operations.")
    supabase_url = os.getenv("SUPABASE_URL")
    if not supabase_url:
        raise RuntimeError("Missing SUPABASE_URL for admin auth operations.")
    return create_client(supabase_url, admin_key)

def _json_body() -> Dict[str, Any]:
    if not request.is_json:
        return {}
    return cast(Dict[str, Any], request.get_json(silent=True) or {})

def _valid_email(email: str) -> bool:
    return bool(EMAIL_PATTERN.match(email))

def _password_error(password: Any) -> Optional[str]:
    if not isinstance(password, str) or len(password) < 8:
        return "Password must be at least 8 characters long."
    if password.lower() == password or password.upper() == password:
        return "Password must include uppercase and lowercase letters."
    if not any(char.isdigit() for char in password):
        return "Password must include at least one number."
    return None

def _safe_error(default: str, error: Exception) -> str:
    message = str(error)
    if "already registered" in message.lower() or "already exists" in message.lower():
        return message
    return default

@auth_bp.route('/api/auth/login', methods=['POST'])
def handle_api_login():
    try:
        body = _json_body()
        email = str(body.get('email', '')).strip().lower()
        password = body.get('password')

        if not email or not password:
            return jsonify({"success": False, "message": "Missing authentication parameters"}), 400
        if not _valid_email(email):
            return jsonify({"success": False, "message": "Invalid email or password credentials."}), 401

        auth_response = supabase.auth.sign_in_with_password({
            "email": email,
            "password": password
        })
        user_uuid = auth_response.user.id
        token = auth_response.session.access_token
        
        role = None
        display_name = "System User"
        company_str = "GT Lantin Internal"
        staff_id = None

        user_query = supabase.table('user_account').select('*').eq('user_id', user_uuid).execute()
        account = (user_query.data or [None])[0]

        # Some legacy Auth users were created before user_account.user_id was
        # synchronized. Resolve the role by the authenticated email only when
        # there is exactly one matching account.
        if account is None:
            legacy_query = supabase.table('user_account').select('*').eq(
                'username', email
            ).limit(2).execute()
            legacy_accounts = legacy_query.data or []
            if len(legacy_accounts) == 1:
                account = legacy_accounts[0]

        if account is None:
            return jsonify({"success": False, "message": "Invalid email or password credentials."}), 401

        role = str(account.get('role', '')).strip().lower()
        if role not in ('admin', 'staff'):
            return jsonify({"success": False, "message": "Invalid email or password credentials."}), 401
        display_name = account.get('full_name') or "System User"
        staff_id = account.get('staff_id')

        return jsonify({
            "success": True,
            "data": {
                "id": staff_id if role == 'staff' and staff_id else user_uuid,
                "staff_id": staff_id,
                "auth_user_id": user_uuid,
                "role": role,
                "name": display_name,
                "company": company_str, 
                "token": token
            }
        }), 200

    except Exception:
        logger.exception("Login failed for email=%s", email if 'email' in locals() else "unknown")
        return jsonify({"success": False, "message": "Invalid email or password credentials."}), 401

@auth_bp.route('/api/auth/register-staff', methods=['POST'])
def register_staff():
    try:
        data = _json_body()
        email = str(data.get('email', '')).strip().lower()
        full_name = str(data.get('full_name', '')).strip()
        role_raw = data.get('role')
        password = data.get('password')

        if not _valid_email(email):
            return jsonify({"success": False, "message": "A valid email is required."}), 400
        if not full_name:
            return jsonify({"success": False, "message": "Full name is required."}), 400
        password_message = _password_error(password)
        if password_message:
            return jsonify({"success": False, "message": password_message}), 400

        role_map = {'Dispatch Staff': 'staff'}
        normalized_role = role_map.get(role_raw, 'staff')

        admin_supabase = get_admin_client()
        auth_res = admin_supabase.auth.admin.create_user({
            "email": email,
            "password": password,
            "email_confirm": True
        })
        uid = auth_res.user.id

        supabase.table('user_account').insert({
            "user_id": uid,
            "role": normalized_role,
            "username": email,
            "full_name": full_name
        }).execute()

        return jsonify({"success": True, "message": "User registered!"}), 201
    except Exception as e:
        logger.exception("Staff registration failed")
        return jsonify({"success": False, "message": _safe_error("Unable to register user.", e)}), 500

@auth_bp.route('/api/auth/register-driver', methods=['POST'])
def register_driver_profile():
    try:
        data = _json_body()
        full_name = str(data.get('full_name', '')).strip()
        phone_no = str(data.get('phone_no', '09123456789')).strip()
        status = str(data.get('employment_status', 'Active')).strip() or "Active"

        if not full_name:
            return jsonify({"success": False, "message": "Driver name is required."}), 400
        if not PHONE_PATTERN.match(phone_no):
            return jsonify({"success": False, "message": "A valid phone number is required."}), 400
        if status not in ALLOWED_DRIVER_STATUSES:
            return jsonify({"success": False, "message": "Invalid employment status."}), 400

        insert_response = supabase.table('driver_profile').insert({
            "full_name": full_name,
            "birthday": data.get('birthday', '1995-05-15'),
            "phone_no": phone_no,
            "date_hired": data.get('date_hired', '2024-01-01'),
            "employment_status": status,
            "is_backup": data.get('is_backup', 'No')
        }).execute()

        created = insert_response.data[0] if insert_response.data else {}
        return jsonify({
            "success": True,
            "message": "Driver profile registered.",
            "driver_id": created.get('driver_id'),
        }), 201
    except Exception as e:
        error_message = str(e)
        if "unique_driver_phone" in error_message or "23505" in error_message:
            return jsonify({"success": False, "message": "This phone number is already registered to another driver."}), 400
        return jsonify({"success": False, "message": error_message}), 500

@auth_bp.route('/api/auth/update-password', methods=['POST'])
def update_user_password():
    try:
        data = _json_body()
        user_id = str(data.get('user_id', '')).strip()
        new_password = data.get('new_password')
        if not user_id:
            return jsonify({"success": False, "message": "User ID is required."}), 400
        password_message = _password_error(new_password)
        if password_message:
            return jsonify({"success": False, "message": password_message}), 400
        admin_client = get_admin_client()
        admin_client.auth.admin.update_user_by_id(
            user_id,
            attributes={"password": new_password}
        )
        return jsonify({"success": True, "message": "Password updated!"}), 200
    except Exception as e:
        logger.exception("Password update failed")
        return jsonify({"success": False, "message": "Unable to update password."}), 500

@auth_bp.route('/api/auth/system-users', methods=['GET'])
def get_system_users():
    try:
        users_query = supabase.table('user_account').select('*').in_('role', ['admin', 'staff']).execute()
        formatted_users = []

        for u in users_query.data:
            role = str(u.get('role', 'staff')).lower()
            actual_name = u.get('full_name') or 'System User'
            
            company = "GT Lantin Internal"
            permission = "Logistics Only"
            display_role = "Dispatch Staff"
            status_color = "green"

            if role == 'admin':
                display_role = "Administrator"
                permission = "Full Access"
            formatted_users.append({
                "id": u.get('staff_id'),
                "staff_id": u.get('staff_id'),
                "auth_user_id": u['user_id'],
                "name": actual_name,
                "email": u.get('username', ''),
                "role": display_role,
                "company": company,
                "permission": permission,
                "status": "Active",
                "color": status_color
            })

        return jsonify({"success": True, "data": formatted_users}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@auth_bp.route('/api/auth/update-driver/<driver_id>', methods=['PUT'])
def update_driver(driver_id):
    try:
        data = _json_body()
        full_name = str(data.get("full_name", "")).strip()
        phone_no = str(data.get("phone_no", "09123456789")).strip()
        status = str(data.get("employment_status", "Active")).strip() or "Active"
        if not full_name:
            return jsonify({"success": False, "message": "Driver name is required."}), 400
        if not PHONE_PATTERN.match(phone_no):
            return jsonify({"success": False, "message": "A valid phone number is required."}), 400
        if status not in ALLOWED_DRIVER_STATUSES:
            return jsonify({"success": False, "message": "Invalid employment status."}), 400
        
        driver_update = {
            "full_name": full_name,
            "birthday": data.get("birthday"),
            "phone_no": phone_no,
            "employment_status": status
        }
        if "is_backup" in data:
            driver_update["is_backup"] = data["is_backup"]

        profile_res = supabase.table("driver_profile").update(driver_update).eq("driver_id", driver_id).execute()
        
        return jsonify({"success": True, "message": "Driver profile updated successfully."}), 200
    except Exception as e:
        error_message = str(e)
        if "unique_driver_phone" in error_message or "23505" in error_message:
            return jsonify({"success": False, "message": "This phone number is already registered to another driver."}), 400
        print(f"Driver Update Error: {error_message}")
        return jsonify({"success": False, "message": error_message}), 500

@auth_bp.route('/api/auth/delete-driver/<driver_id>', methods=['DELETE'])
def delete_driver(driver_id):
    try:
        supabase.table("driver_profile").delete().eq("driver_id", driver_id).execute()
        
        return jsonify({"success": True, "message": "Driver completely expunged from system."}), 200
    except Exception as e:
        print(f"Driver Delete Error: {e}")
        return jsonify({"success": False, "message": f"Server processing error: {str(e)}"}), 500
