import time
from collections import defaultdict, deque
from datetime import datetime, timezone

from flask import Blueprint, jsonify, render_template, request
from .errors import internal_error

evaluate_bp = Blueprint('evaluate', __name__)
supabase = None

_public_submit_attempts = defaultdict(deque)
_PUBLIC_SUBMIT_LIMIT = 12
_PUBLIC_SUBMIT_WINDOW = 3600


def _json_body():
    return request.get_json(silent=True) or {}


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
        return internal_error('Unable to load evaluations.')


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
        return internal_error('Unable to submit staff evaluation.')


@evaluate_bp.route('/api/evaluate/passenger-survey', methods=['GET'])
def get_permanent_passenger_survey():
    try:
        return jsonify({'success': True, 'drivers': _all_drivers(), 'permanent': True}), 200
    except Exception:
        return internal_error('Unable to load this survey.')


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
        return internal_error('Unable to submit your evaluation.')


@evaluate_bp.route('/passenger-evaluation', methods=['GET'])
def permanent_passenger_evaluation_page():
    return render_template('passenger_evaluation.html', token=None)
