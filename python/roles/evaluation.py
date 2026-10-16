import hashlib
import os
import secrets
import time
from collections import defaultdict, deque
from datetime import datetime, timezone, timedelta
from functools import wraps
from uuid import uuid4

from flask import Blueprint, current_app, jsonify, render_template, request

evaluate_bp = Blueprint('evaluate', __name__)
supabase = None

_public_submit_attempts = defaultdict(deque)
_PUBLIC_SUBMIT_LIMIT = 12
_PUBLIC_SUBMIT_WINDOW = 3600


def _token_hash(token):
    return hashlib.sha256(token.encode('utf-8')).hexdigest()


def _json_body():
    return request.get_json(silent=True) or {}


def _auth_user():
    authorization = request.headers.get('Authorization', '')
    if not authorization.lower().startswith('bearer '):
        return None
    token = authorization.split(' ', 1)[1].strip()
    if not token:
        return None
    try:
        return supabase.auth.get_user(token).user
    except Exception:
        return None


def _staff_required(handler):
    @wraps(handler)
    def wrapped(*args, **kwargs):
        user = _auth_user()
        if user is None:
            return jsonify({'success': False, 'message': 'Staff authentication is required.'}), 401
        account = supabase.table('user_account').select('role').eq(
            'user_id', user.id
        ).limit(1).execute().data or []
        role = str(account[0].get('role', '')).lower() if account else ''
        if role not in {'staff', 'admin'}:
            return jsonify({'success': False, 'message': 'Staff access is required.'}), 403
        request.evaluation_user = user
        return handler(*args, **kwargs)
    return wrapped


def _driver_id(value):
    try:
        parsed = int(value)
        return parsed if parsed > 0 else None
    except (TypeError, ValueError):
        return None


def _rating(value):
    try:
        parsed = int(value)
        return parsed if 1 <= parsed <= 5 else None
    except (TypeError, ValueError):
        return None


def _public_survey_url(token):
    configured = os.getenv('PUBLIC_SURVEY_BASE_URL') or os.getenv('PUBLIC_APP_URL')
    base = (
        configured or 'https://shervice-python-production.up.railway.app'
    ).rstrip('/')
    return f'{base}/passenger-evaluation/{token}'


def _load_survey(token):
    if not token or len(token) < 32:
        return None
    rows = supabase.table('passenger_evaluation_survey').select(
        'survey_id, expires_at, is_active'
    ).eq('token_hash', _token_hash(token)).limit(1).execute().data or []
    if not rows:
        return None
    survey = rows[0]
    if not survey.get('is_active'):
        return None
    expires_at = str(survey.get('expires_at', '')).replace('Z', '+00:00')
    try:
        if datetime.fromisoformat(expires_at).astimezone(timezone.utc) <= datetime.now(timezone.utc):
            return None
    except ValueError:
        return None
    return survey


def _rate_limited_public_submit():
    client = (request.headers.get('X-Forwarded-For') or request.remote_addr or 'unknown').split(',')[0].strip()
    now = time.time()
    attempts = _public_submit_attempts[client]
    while attempts and now - attempts[0] > _PUBLIC_SUBMIT_WINDOW:
        attempts.popleft()
    if len(attempts) >= _PUBLIC_SUBMIT_LIMIT:
        return True
    attempts.append(now)
    return False


def _all_drivers():
    return supabase.table('driver_profile').select(
        'driver_id, full_name'
    ).order('full_name').execute().data or []


def _passenger_payload(data):
    driver_id = _driver_id(data.get('driver_id'))
    ratings = {
        'safety_score': _rating(data.get('safety_score')),
        'punctuality_score': _rating(data.get('punctuality_score')),
        'professionalism_score': _rating(data.get('professionalism_score')),
    }
    if not driver_id or any(value is None for value in ratings.values()):
        return None, 'Select a driver and provide all 1–5 ratings.'
    driver = supabase.table('driver_profile').select('driver_id').eq(
        'driver_id', driver_id
    ).limit(1).execute().data or []
    if not driver:
        return None, 'Selected driver was not found.'
    now = datetime.now(timezone.utc)
    return {
        **ratings,
        'submit_date': now.strftime('%Y-%m-%d'),
        'submit_time': now.strftime('%H:%M:%S'),
        'comments': str(data.get('comments') or '')[:2000],
        'driver_id': driver_id,
        'source': 'passenger',
    }, None


@evaluate_bp.route('/api/evaluate/driver/<int:driver_id>', methods=['GET'])
def get_driver_evaluations(driver_id):
    try:
        evals = supabase.table('evaluation').select('*').eq(
            'driver_id', driver_id
        ).order('submit_date', desc=True).execute()
        return jsonify({'success': True, 'data': evals.data or []}), 200
    except Exception:
        return jsonify({'success': False, 'message': 'Unable to load evaluations.'}), 500


@evaluate_bp.route('/api/evaluate/staff-submit', methods=['POST'])
def staff_submit_evaluation():
    """Legacy staff endpoint, retained for the existing staff screen."""
    try:
        data = _json_body()
        driver_id = _driver_id(data.get('driver_id'))
        ratings = {
            'safety_score': _rating(data.get('safety_score', 5)),
            'punctuality_score': _rating(data.get('punctuality_score', 5)),
            'professionalism_score': _rating(data.get('professionalism_score', 5)),
        }
        if not driver_id or any(value is None for value in ratings.values()):
            return jsonify({'success': False, 'message': 'A valid driver and 1–5 ratings are required.'}), 400
        trip = supabase.table('trip_schedule').select(
            'trip_id, vehicle_id'
        ).eq('driver_id', driver_id).order('schedule_date', desc=True).limit(1).execute().data or []
        now = datetime.now()
        payload = {
            **ratings,
            'submit_date': now.strftime('%Y-%m-%d'),
            'submit_time': now.strftime('%H:%M:%S'),
            'comments': str(data.get('comments') or '')[:2000],
            'driver_id': driver_id,
            'trip_id': trip[0].get('trip_id') if trip else None,
            'vehicle_id': trip[0].get('vehicle_id') if trip else None,
            'source': 'staff',
        }
        supabase.table('evaluation').insert(payload).execute()
        return jsonify({'success': True, 'message': 'Staff evaluation submitted successfully!'}), 200
    except Exception:
        return jsonify({'success': False, 'message': 'Unable to submit staff evaluation.'}), 500


@evaluate_bp.route('/api/evaluate/passenger-survey', methods=['POST'])
@_staff_required
def create_passenger_survey():
    """Create the link staff give to the OIC for passenger distribution."""
    try:
        days = int(_json_body().get('expires_in_days', 7))
        days = min(max(days, 1), 30)
    except (TypeError, ValueError):
        days = 7
    token = secrets.token_urlsafe(32)
    survey_id = str(uuid4())
    expires_at = datetime.now(timezone.utc).replace(microsecond=0) + timedelta(days=days)
    try:
        supabase.table('passenger_evaluation_survey').insert({
            'survey_id': survey_id,
            'token_hash': _token_hash(token),
            'created_by': str(request.evaluation_user.id),
            'expires_at': expires_at.isoformat(),
        }).execute()
        return jsonify({
            'success': True,
            'survey_id': survey_id,
            'url': _public_survey_url(token),
            'expires_at': expires_at.isoformat(),
        }), 201
    except Exception:
        current_app.logger.exception('Passenger survey link creation failed')
        return jsonify({'success': False, 'message': 'Unable to create passenger survey link.'}), 500


@evaluate_bp.route('/api/evaluate/passenger-survey', methods=['GET'])
def get_permanent_passenger_survey():
    try:
        return jsonify({'success': True, 'drivers': _all_drivers(), 'permanent': True}), 200
    except Exception:
        return jsonify({'success': False, 'message': 'Unable to load this survey.'}), 500


@evaluate_bp.route('/api/evaluate/passenger-survey/<token>', methods=['GET'])
def get_passenger_survey(token):
    try:
        survey = _load_survey(token)
        if survey is None:
            return jsonify({'success': False, 'message': 'This survey link is invalid or expired.'}), 404
        return jsonify({
            'success': True,
            'survey_id': survey.get('survey_id'),
            'drivers': _all_drivers(),
            'expires_at': survey.get('expires_at'),
        }), 200
    except Exception:
        return jsonify({'success': False, 'message': 'Unable to load this survey.'}), 500


@evaluate_bp.route('/api/evaluate/passenger-survey/<token>', methods=['POST'])
def submit_passenger_evaluation(token):
    if _rate_limited_public_submit():
        return jsonify({'success': False, 'message': 'Too many submissions. Please try again later.'}), 429
    try:
        survey = _load_survey(token)
        if survey is None:
            return jsonify({'success': False, 'message': 'This survey link is invalid or expired.'}), 404
        payload, error = _passenger_payload(_json_body())
        if error:
            return jsonify({'success': False, 'message': error}), 400
        supabase.table('evaluation').insert({
            **payload,
            'source': 'passenger',
            'survey_id': survey.get('survey_id'),
        }).execute()
        return jsonify({'success': True, 'message': 'Thank you for your anonymous feedback.'}), 201
    except Exception:
        return jsonify({'success': False, 'message': 'Unable to submit your evaluation.'}), 500


@evaluate_bp.route('/api/evaluate/passenger-submit', methods=['POST'])
def submit_permanent_passenger_evaluation():
    if _rate_limited_public_submit():
        return jsonify({'success': False, 'message': 'Too many submissions. Please try again later.'}), 429
    try:
        payload, error = _passenger_payload(_json_body())
        if error:
            return jsonify({'success': False, 'message': error}), 400
        supabase.table('evaluation').insert(payload).execute()
        return jsonify({'success': True, 'message': 'Thank you for your anonymous feedback.'}), 201
    except Exception:
        current_app.logger.exception('Permanent passenger evaluation submission failed')
        return jsonify({'success': False, 'message': 'Unable to submit your evaluation.'}), 500


@evaluate_bp.route('/passenger-evaluation', methods=['GET'])
def permanent_passenger_evaluation_page():
    return render_template('passenger_evaluation.html', token=None)


@evaluate_bp.route('/passenger-evaluation/<token>', methods=['GET'])
def passenger_evaluation_page(token):
    return render_template('passenger_evaluation.html', token=token)
