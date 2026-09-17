from flask import Blueprint, jsonify, request
from datetime import datetime

oic_bp = Blueprint('oic', __name__)
supabase = None # Assigned by app.py

# ─────────── 1. CORE TRIPS & SCHEDULES PIPELINE ───────────
@oic_bp.route('/api/trips', methods=['GET', 'POST'])
def handle_trips_pipeline():
    if request.method == 'GET':
        try:
            # Resolves user_account names and vehicle plates simultaneously
            trips_res = supabase.table('trip_schedule').select(
                '*, user_account(full_name), vehicle(plate_number, bus_type)'
            ).execute()
            
            raw_trips = trips_res.data or []
            oic_res = supabase.table('oic_profile').select('oic_id, company_name').execute()
            company_by_oic_id = {
                row['oic_id']: row.get('company_name')
                for row in (oic_res.data or [])
                if row.get('oic_id') is not None
            }
            
            # NEW: Fetch Passenger Evaluations to calculate CSAT per trip
            evals_res = supabase.table('passenger_evaluation').select('trip_id, safety_score, punctuality_score, professionalism_score').execute()
            trip_evals = {}
            for ev in (evals_res.data or []):
                t_id = ev.get('trip_id')
                if t_id:
                    s = float(ev.get('safety_score') or 0.0)
                    p = float(ev.get('punctuality_score') or 0.0)
                    pr = float(ev.get('professionalism_score') or 0.0)
                    if t_id not in trip_evals:
                        trip_evals[t_id] = []
                    trip_evals[t_id].append((s + p + pr) / 3.0)

            for trip in raw_trips:
                trip['client_company'] = company_by_oic_id.get(trip.get('oic_id'))
                
                # Inject the calculated CSAT rating for this specific trip
                t_id = trip.get('trip_id')
                if t_id in trip_evals and trip_evals[t_id]:
                    trip['evaluation_score'] = sum(trip_evals[t_id]) / len(trip_evals[t_id])
                else:
                    trip['evaluation_score'] = None
                    
            return jsonify({"success": True, "trips": raw_trips}), 200
        except Exception as e:
            print(f"❌ Admin Schedule Fetch Exception: {e}")
            return jsonify({"success": False, "error": str(e)}), 500


# ─────────── 2. MUTUAL EVALUATIONS PIPELINE ───────────

@oic_bp.route('/api/evaluations/mutual', methods=['GET', 'POST'])
def handle_evaluations():
    try:
        if request.method == 'POST':
            data = request.get_json() or {}
            
            # Safe parsing to prevent type errors on missing elements
            trip_id_raw = data.get("trip_id")
            oic_id_raw = data.get("oic_id")
            
            if trip_id_raw is None or oic_id_raw is None:
                return jsonify({"success": False, "message": "Missing trip_id or oic_id"}), 400

            new_eval = {
                "trip_id": int(trip_id_raw),
                "oic_id": int(oic_id_raw),
                "overall_rating": int(data.get("overall_rating", 5)),
                "comments": str(data.get("comments", "")).strip(),
                "evaluator_type": "OIC",
                "submit_date": datetime.utcnow().strftime('%Y-%m-%d')
            }
            supabase.table('oic_evaluation').insert(new_eval).execute()
            return jsonify({"success": True}), 201
        
        # GET: Includes the join for company_name
        res = supabase.table('oic_evaluation').select('*, oic_profile(company_name)').execute()
        return jsonify({"success": True, "evaluations": res.data or []}), 200
    except Exception as e:
        print(f"❌ Evaluation Handler Exception: {e}")
        return jsonify({"success": False, "message": str(e)}), 500


@oic_bp.route('/api/evaluations/summary', methods=['GET'])
def get_evaluation_summary():
    try:
        res = supabase.table('oic_evaluation').select('overall_rating, oic_profile(company_name)').execute()
        summary = {}
        for entry in (res.data or []):
            oic_prof = entry.get('oic_profile', {})
            if isinstance(oic_prof, list) and len(oic_prof) > 0:
                oic_prof = oic_prof[0]
                
            comp = oic_prof.get('company_name', 'Unknown') if isinstance(oic_prof, dict) else 'Unknown'
            
            if comp not in summary: 
                summary[comp] = {'total': 0, 'sum': 0}
            summary[comp]['total'] += 1
            summary[comp]['sum'] += entry.get('overall_rating', 5)
        
        return jsonify([
            {
                "name": k, 
                "avg": round(v['sum'] / v['total'], 1) if v['total'] > 0 else 0.0, 
                "count": v['total']
            } for k, v in summary.items()
        ]), 200
    except Exception as e:
        print(f"❌ Summary Calculation Exception: {e}")
        return jsonify({"success": False, "message": str(e)}), 500