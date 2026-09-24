import os
import time
from collections import defaultdict, deque
from flask import Flask, jsonify, request
from flask_cors import CORS
from dotenv import load_dotenv
from supabase import create_client, Client

# Import your blueprint role modules from the folder structures
import roles.auth as auth_module
import roles.notifs as notifs_module  #new
import roles.admin as admin_module
import roles.drivers as drivers_module
import roles.staff as staff_module
import roles.evaluation as evaluation_module
import roles.vehicle as vehicles_module  
import roles.schedules as schedules_module
import roles.payroll as payroll_module
import roles.predictive_ml as predictive_ml
import roles.driver_ml as driver_ml_module
import roles.route_ml as route_ml_module

# Flip this only when switching between your PC backend and Railway.
# Environment variables still override these defaults when deployed.
USE_HOSTED_CONFIG = True  # Set to False for local development, True for Railway deployment

LOCAL_CORS_ALLOWED_ORIGINS = [
    r"http://localhost:\d+",
    r"http://127\.0\.0\.1:\d+",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:5000",
    "http://127.0.0.1:5000",
]
HOSTED_CORS_ALLOWED_ORIGINS = [
    "https://shervice-python-production.up.railway.app",
]
LOGIN_RATE_LIMIT_ATTEMPTS = 8
LOGIN_RATE_LIMIT_WINDOW_SECONDS = 60


def _env_bool(name, default):
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on", "hosted"}


def _csv_env(name, default):
    value = os.getenv(name)
    if value is None:
        return default
    return [item.strip() for item in value.split(",") if item.strip()]


class TransportBackendApp:
    def __init__(self):
        # 1. Initialize safe environment profile keys
        load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
        self.app = Flask(__name__)
        self.use_hosted_config = _env_bool("USE_HOSTED_CONFIG", USE_HOSTED_CONFIG)
        
        default_origins = (
            HOSTED_CORS_ALLOWED_ORIGINS
            if self.use_hosted_config
            else LOCAL_CORS_ALLOWED_ORIGINS
        )
        allowed_origins = _csv_env("CORS_ALLOWED_ORIGINS", default_origins)
        if self.use_hosted_config and "*" in allowed_origins:
            allowed_origins = HOSTED_CORS_ALLOWED_ORIGINS
        CORS(self.app, resources={
            r"/*": {
                "origins": allowed_origins,
                "allow_headers": ["Content-Type", "Authorization", "Accept"],
                "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
                "max_age": 600,
                "supports_credentials": False,
            }
        })
        self.app.config["MAX_CONTENT_LENGTH"] = int(
            os.getenv("MAX_CONTENT_LENGTH", str(16 * 1024 * 1024))
        )
        self._login_attempts = defaultdict(deque)
        
        # 3. Setup core unified database engine connection parameters
        self.supabase_url = os.getenv("SUPABASE_URL")
        self.supabase_key = os.getenv("SUPABASE_ANON_KEY")
        
        if not self.supabase_url or not self.supabase_key:
            raise ValueError("Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variables.")
            
        self.supabase: Client = create_client(self.supabase_url, self.supabase_key)
        
        # 4. Bind hooks and structural modular router blueprints
        self._register_hooks()
        self._inject_dependencies_and_register_blueprints()

    def _register_hooks(self):
        @self.app.before_request
        def _before_request():
            request._started_at = time.perf_counter()
            if request.endpoint == "auth.handle_api_login":
                client_id = request.headers.get("X-Forwarded-For", request.remote_addr or "")
                client_id = client_id.split(",")[0].strip() or "unknown"
                now = time.time()
                attempts = self._login_attempts[client_id]
                while attempts and now - attempts[0] > LOGIN_RATE_LIMIT_WINDOW_SECONDS:
                    attempts.popleft()
                if len(attempts) >= LOGIN_RATE_LIMIT_ATTEMPTS:
                    return jsonify({
                        "success": False,
                        "message": "Too many login attempts. Please wait a minute and try again.",
                    }), 429
                attempts.append(now)

        @self.app.after_request
        def _after_request(response):
            response.headers.setdefault("X-Content-Type-Options", "nosniff")
            response.headers.setdefault("X-Frame-Options", "DENY")
            response.headers.setdefault("Referrer-Policy", "no-referrer")
            response.headers.setdefault(
                "Permissions-Policy",
                "camera=(), microphone=(), geolocation=(), payment=()",
            )
            if request.is_secure or self.use_hosted_config:
                response.headers.setdefault(
                    "Strict-Transport-Security",
                    "max-age=31536000; includeSubDomains",
                )
            if request.path.startswith("/api/"):
                response.headers.setdefault(
                    "Cache-Control",
                    "no-store, max-age=0",
                )
                started_at = getattr(request, "_started_at", None)
                if started_at is not None:
                    elapsed_ms = int((time.perf_counter() - started_at) * 1000)
                    response.headers["X-Response-Time-ms"] = str(elapsed_ms)
            return response

        @self.app.errorhandler(413)
        def _payload_too_large(_):
            return jsonify({
                "success": False,
                "message": "Uploaded payload is too large.",
            }), 413

        # A simple status check for the browser
        @self.app.route('/')
        def system_status():
            return {"status": "online", "message": "Shervice Backend is LIVE!"}, 200

    def _inject_dependencies_and_register_blueprints(self):
        """
        Injects the initialized single client connection into each role module 
        variable space before mounting blueprints into the unified server schema.
        """
        auth_module.supabase = self.supabase
        notifs_module.supabase = self.supabase #new
        admin_module.supabase = self.supabase
        drivers_module.supabase = self.supabase
        staff_module.supabase = self.supabase
        evaluation_module.supabase = self.supabase
        vehicles_module.supabase = self.supabase  
        schedules_module.supabase = self.supabase
        payroll_module.supabase = self.supabase
        predictive_ml.supabase = self.supabase
        driver_ml_module.supabase = self.supabase
        route_ml_module.supabase = self.supabase
        # Register functional application blueprints cleanly
        self.app.register_blueprint(auth_module.auth_bp)
        self.app.register_blueprint(notifs_module.notifs_bp) #new
        self.app.register_blueprint(admin_module.admin_bp)
        self.app.register_blueprint(drivers_module.drivers_bp)
        self.app.register_blueprint(staff_module.staff_bp)
        self.app.register_blueprint(evaluation_module.evaluate_bp)
        self.app.register_blueprint(vehicles_module.vehicles_bp) 
        self.app.register_blueprint(schedules_module.schedules_bp)
        self.app.register_blueprint(payroll_module.payroll_bp)
        self.app.register_blueprint(predictive_ml.predictive_bp)
        self.app.register_blueprint(driver_ml_module.driver_ml_bp)
        self.app.register_blueprint(route_ml_module.route_ml_bp)
        
    def run(self):
        default_host = "0.0.0.0" if self.use_hosted_config else "127.0.0.1"
        self.app.run(
            host=os.getenv("FLASK_HOST", default_host),
            port=int(os.getenv("PORT", os.getenv("FLASK_PORT", "5000"))), # Prioritizes Railway's native PORT variable
            debug=False,
            use_reloader=False,
        )

# 1. Create the server instance globally so Gunicorn can find it
backend_server = TransportBackendApp()

# 2. Expose the actual Flask application to a global variable named 'app'
app = backend_server.app

# 3. Keep this for local testing on your PC
if __name__ == '__main__':
    backend_server.run()
