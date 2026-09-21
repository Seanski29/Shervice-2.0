from dotenv import load_dotenv
import os
from supabase import create_client
import traceback

load_dotenv()
url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_KEY')
print('url=', url)
print('key set=', bool(key))
client = create_client(url, key)
try:
    resp = client.table('app_notification').select('*').limit(1).execute()
    print('data=', getattr(resp, 'data', None))
    print('error=', getattr(resp, 'error', None))
except Exception as e:
    traceback.print_exc()
