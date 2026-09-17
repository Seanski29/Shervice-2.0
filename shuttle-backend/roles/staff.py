from flask import Blueprint

staff_bp = Blueprint('staff', __name__)

# Dynamically assigned by app.py upon initialization
supabase = None

# 💡 Ready for your future staff custom updates! Add your new routes underneath this comment block.