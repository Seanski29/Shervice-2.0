import os
import time
import traceback
import logging
from dotenv import load_dotenv
from flask import Blueprint, request, jsonify
from supabase import create_client

notifs_bp = Blueprint('notifs', __name__)
supabase = None
logger = logging.getLogger(__name__)

def _authenticated_account():
    authorization = request.headers.get('Authorization', '')
    if not authorization.startswith('Bearer '):
        logger.warning('Notification auth rejected: bearer token missing')
        return None

    token = authorization[7:].strip()
    if not token:
        logger.warning('Notification auth rejected: bearer token empty')
        return None

    try:
        supabase_client = supabase or _create_supabase_client()
        user_response = supabase_client.auth.get_user(token)
        user = getattr(user_response, 'user', None)
        user_id = getattr(user, 'id', None)
        user_email = str(getattr(user, 'email', '') or '').strip().lower()
        if not user_id:
            logger.warning('Notification auth rejected: Supabase returned no user')
            return None

        account_response = supabase_client.table('user_account').select(
            'user_id, role'
        ).eq('user_id', user_id).limit(1).execute()
        account = (account_response.data or [None])[0]
        if account is None and user_email:
            legacy_response = supabase_client.table('user_account').select(
                'user_id, role'
            ).eq('username', user_email).limit(2).execute()
            legacy_accounts = legacy_response.data or []
            if len(legacy_accounts) == 1:
                account = legacy_accounts[0]
    except Exception:
        logger.exception('Notification auth lookup failed')
        return None

    if not account or str(account.get('role', '')).lower() not in ('admin', 'staff'):
        logger.warning('Notification auth rejected: account or role not found')
        return None
    return {
        'user_id': str(user_id),
        'role': str(account.get('role', '')).lower(),
        'company': 'GT Lantin Internal',
    }


def _can_access_notification(notification, identity):
    if identity['role'] == 'admin':
        return True

    target_user_id = notification.get('target_user_id')
    target_role = str(notification.get('target_role') or '').strip().lower()
    target_company = str(notification.get('target_company') or '').strip()
    company = identity['company']

    return (
        str(target_user_id) == identity['user_id']
        or (not target_role and not target_company)
        or (not target_role and company and target_company.lower() == company.lower())
        or (target_role == identity['role'] and not target_company)
        or (target_role == identity['role'] and company and target_company.lower() == company.lower())
    )

def _is_schedule_blackout_notification(notification):
    # Older alerts can still exist after the blackout feature is retired.
    title = ' '.join(str(notification.get('title') or '').lower().replace('_', ' ').replace('-', ' ').split())
    source = ' '.join(str(notification.get('source_tag') or '').lower().replace('_', ' ').replace('-', ' ').split())
    return 'schedule blackout' in title or source in ('blackout', 'schedule blackout')

def _create_supabase_client():
    load_dotenv()
    url = os.getenv('SUPABASE_URL')
    key = os.getenv('SUPABASE_ANON_KEY') or os.getenv('SUPABASE_KEY')
    if not url or not key:
        raise RuntimeError('Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variables.')
    return create_client(url, key)

def _execute_supabase(action, retries=3, backoff=0.25):
    last_exc = None
    for attempt in range(1, retries + 1):
        try:
            return action()
        except Exception as e:
            last_exc = e
            message = str(e).lower()
            retryable = (
                isinstance(e, OSError)
                or '10035' in message
                or 'non-blocking socket operation' in message
                or 'temporarily unavailable' in message
                or 'timeout' in message
            )
            print(f'⚠️ Supabase retry attempt {attempt}/{retries}: {e}')
            traceback.print_exc()
            if not retryable or attempt >= retries:
                break
            time.sleep(backoff * attempt)
    raise last_exc

# ==========================================
# 1. FETCH NOTIFICATIONS
# ==========================================
@notifs_bp.route('/api/notifications', methods=['GET'])
def get_notifications():
    try:
        identity = _authenticated_account()
        if not identity:
            return jsonify({"success": False, "message": "Authentication required."}), 401
        user_id = identity['user_id']
        role = identity['role']
        company = identity['company']
        supabase_client = supabase or _create_supabase_client()
        response = _execute_supabase(
            lambda: supabase_client.table('app_notification')
            .select(
                'notification_id, title, message, created_at, related_trip_id, '
                'source_tag, is_read, target_user_id, target_role, target_company'
            )
            .order('created_at', desc=True)
            .execute()
        )

        raw_notifs = [
            notification for notification in (response.data or [])
            if not _is_schedule_blackout_notification(notification)
        ]
        logger.info(
            'Notification fetch: role=%s user_id_present=%s rows=%s',
            role,
            bool(user_id),
            len(raw_notifs),
        )
        filtered_notifications = []

        if role == 'admin':
            filtered_notifications = raw_notifs
            
        else:
            for notification in raw_notifs:
                target_user_id = notification.get('target_user_id')
                target_role = (notification.get('target_role') or '').strip().lower()
                target_company = (notification.get('target_company') or '').strip()

                if _can_access_notification(notification, identity):
                    filtered_notifications.append(notification)

        return jsonify({"success": True, "data": filtered_notifications}), 200

    except Exception as e:
        print(f"❌ Notification Fetch Error: {e}")
        return jsonify({"success": False, "message": "Internal server error."}), 500


# ==========================================
# 2. MARK NOTIFICATION AS READ
# ==========================================
@notifs_bp.route('/api/notifications/<int:notif_id>/read', methods=['PUT'])
def mark_as_read(notif_id):
    try:
        identity = _authenticated_account()
        if not identity:
            return jsonify({"success": False, "message": "Authentication required."}), 401
        supabase_client = supabase or _create_supabase_client()
        notification_response = supabase_client.table('app_notification').select(
            'target_user_id, target_role, target_company'
        ).eq('notification_id', notif_id).limit(1).execute()
        notification = (notification_response.data or [None])[0]
        if not notification or not _can_access_notification(notification, identity):
            return jsonify({"success": False, "message": "Notification not found."}), 404
        query = supabase_client.table('app_notification').update({'is_read': True}).eq('notification_id', notif_id)
        response = _execute_supabase(
            lambda: query.execute()
        )

        if response.data:
            return jsonify({"success": True, "message": "Notification marked as read."}), 200
        else:
            return jsonify({"success": False, "message": "Notification not found."}), 404
    except Exception as e:
        print(f"❌ Notification Update Error: {e}")
        return jsonify({"success": False, "message": "Internal server error."}), 500


# ==========================================
# 3. MARK ALL AS READ
# ==========================================
@notifs_bp.route('/api/notifications/read-all', methods=['PUT'])
def mark_all_as_read():
    try:
        identity = _authenticated_account()
        if not identity:
            return jsonify({"success": False, "message": "Authentication required."}), 401
        data = request.json or {}
        user_id = identity['user_id']
        role = identity['role']

        supabase_client = supabase or _create_supabase_client()
        
        # Fetch unread notifications
        response = _execute_supabase(
            lambda: supabase_client.table('app_notification')
            .select(
                'notification_id, title, message, created_at, related_trip_id, '
                'source_tag, is_read, target_user_id, target_role, target_company'
            )
            .eq('is_read', False)
            .execute()
        )
        raw_notifs = [
            notification for notification in (response.data or [])
            if not _is_schedule_blackout_notification(notification)
        ]
        ids_to_update = []

        if role == 'admin':
            ids_to_update = [n['notification_id'] for n in raw_notifs]
        else:
            company = identity['company']
            if company.lower() in ('internal', 'gt lantin internal', 'unknown'):
                company = ''
                
            for n in raw_notifs:
                target_user_id = n.get('target_user_id')
                target_role = (n.get('target_role') or '').strip().lower()
                target_company = (n.get('target_company') or '').strip()

                if _can_access_notification(n, identity):
                    ids_to_update.append(n['notification_id'])

        if ids_to_update:
            _execute_supabase(
                lambda: supabase_client.table('app_notification')
                .update({'is_read': True})
                .in_('notification_id', ids_to_update)
                .execute()
            )

        return jsonify({"success": True, "message": f"Marked {len(ids_to_update)} notifications as read."}), 200

    except Exception as e:
        print(f"❌ Notification Read-All Error: {e}")
        return jsonify({"success": False, "message": "Internal server error."}), 500


# ==========================================
# 4. DELETE NOTIFICATION
# ==========================================
@notifs_bp.route('/api/notifications/<int:notif_id>', methods=['DELETE'])
def delete_notification(notif_id):
    try:
        identity = _authenticated_account()
        if not identity:
            return jsonify({"success": False, "message": "Authentication required."}), 401
        supabase_client = supabase or _create_supabase_client()
        notification_response = supabase_client.table('app_notification').select(
            'target_user_id, target_role, target_company'
        ).eq('notification_id', notif_id).limit(1).execute()
        notification = (notification_response.data or [None])[0]
        if not notification or not _can_access_notification(notification, identity):
            return jsonify({"success": False, "message": "Notification not found."}), 404
        query = supabase_client.table('app_notification').delete().eq('notification_id', notif_id)
        _execute_supabase(lambda: query.execute())
        return jsonify({"success": True, "message": "Notification deleted."}), 200
    except Exception as e:
        print(f"❌ Notification Delete Error: {e}")
        return jsonify({"success": False, "message": "Internal server error."}), 500


# ==========================================
# 5. UNIVERSAL TRIGGER HELPER
# ==========================================
def trigger_notification(title, message, target_user_id=None, target_role=None, target_company=None, related_trip_id=None, source_tag='system', db_client=None):
    """
    Call this function from anywhere in your backend to generate a notification.
    """
    if _is_schedule_blackout_notification({'title': title, 'source_tag': source_tag}):
        return True
    try:
        # ✅ Prioritize the injected database client to guarantee connection
        supabase_client = db_client or supabase or _create_supabase_client()
        payload = {
            'title': title,
            'message': message,
            'source_tag': source_tag
        }
        if target_user_id: payload['target_user_id'] = target_user_id
        if target_role: payload['target_role'] = target_role
        if target_company: payload['target_company'] = target_company
        if related_trip_id: payload['related_trip_id'] = related_trip_id

        _execute_supabase(
            lambda: supabase_client.table('app_notification').insert(payload).execute()
        )
        print(f'✅ Notification triggered successfully: {title}')
        return True
    except Exception as e:
        print(f"❌ Failed to trigger notification: {e}")
        return False
