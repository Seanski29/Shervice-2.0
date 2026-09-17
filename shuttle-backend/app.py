import os
from flask import Flask
from flask_cors import CORS
from dotenv import load_dotenv
from supabase import create_client, Client

# Import your blueprint role modules from the folder structures
import roles.auth as auth_module
import roles.notifs as notifs_module  #new
import roles.admin as admin_module
import roles.oic as oic_module
import roles.drivers as drivers_module
import roles.staff as staff_module
import roles.passenger as passenger_module
import roles.vehicle as vehicles_module  
import roles.schedules as schedules_module
import roles.predictive_ml as predictive_ml
import roles.driver_ml as driver_ml_module
import roles.route_ml as route_ml_module

from gemeni import ai_bp  # Kept the import here cleanly

class TransportBackendApp:
    def __init__(self):
        # 1. Initialize safe environment profile keys
        load_dotenv()
        self.app = Flask(__name__)
        
        CORS(self.app, resources={
            r"/*": {
                "origins": "*",
                "allow_headers": ["Content-Type", "Authorization", "Accept"],
                "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
            }
        })
        
        # 3. Setup core unified database engine connection parameters
        self.supabase_url = os.getenv("SUPABASE_URL")
        self.supabase_key = os.getenv("SUPABASE_KEY")
        
        if not self.supabase_url or not self.supabase_key:
            raise ValueError("Missing critical configuration parameters inside your backend .env file!")
            
        self.supabase: Client = create_client(self.supabase_url, self.supabase_key)
        
        # 4. Bind hooks and structural modular router blueprints
        self._register_hooks()
        self._inject_dependencies_and_register_blueprints()

    def _register_hooks(self):
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
        oic_module.supabase = self.supabase
        drivers_module.supabase = self.supabase
        staff_module.supabase = self.supabase
        passenger_module.supabase = self.supabase
        vehicles_module.supabase = self.supabase  
        schedules_module.supabase = self.supabase
        predictive_ml.supabase = self.supabase
        driver_ml_module.supabase = self.supabase
        route_ml_module.supabase = self.supabase
        # Register functional application blueprints cleanly
        self.app.register_blueprint(auth_module.auth_bp)
        self.app.register_blueprint(notifs_module.notifs_bp) #new
        self.app.register_blueprint(admin_module.admin_bp)
        self.app.register_blueprint(oic_module.oic_bp)
        self.app.register_blueprint(drivers_module.drivers_bp)
        self.app.register_blueprint(staff_module.staff_bp)
        self.app.register_blueprint(passenger_module.passenger_bp)
        self.app.register_blueprint(vehicles_module.vehicles_bp) 
        self.app.register_blueprint(schedules_module.schedules_bp)
        self.app.register_blueprint(predictive_ml.predictive_bp)
        self.app.register_blueprint(driver_ml_module.driver_ml_bp)
        self.app.register_blueprint(route_ml_module.route_ml_bp)
        # REGISTER THE AI BLUEPRINT HERE CORRECTLY
        self.app.register_blueprint(ai_bp)

    def run(self):
        # Force alignment to explicit loopback addresses
        # Disable the auto-reloader and debug mode for stability during testing
        # (the development reloader can cause transient connection resets)
        self.app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)


# 1. Create the server instance globally so Gunicorn can find it
backend_server = TransportBackendApp()

# 2. Expose the actual Flask application to a global variable named 'app'
app = backend_server.app

# 3. Keep this for local testing on your PC
if __name__ == '__main__':
    backend_server.run()