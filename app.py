import os
import runpy
import sys

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
PYTHON_DIR = os.path.join(ROOT_DIR, 'python')

if PYTHON_DIR not in sys.path:
    sys.path.insert(0, PYTHON_DIR)

app_path = os.path.join(PYTHON_DIR, 'app.py')
if not os.path.exists(app_path):
    raise FileNotFoundError(f"Backend entrypoint not found: {app_path}")

runpy.run_path(app_path, run_name='__main__')
