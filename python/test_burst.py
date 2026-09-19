import requests, time
url='http://127.0.0.1:5000/api/notifications?user_id=c1ae8857-78ea-4248-bc8b-eb6c2eb8dfac&role=Staff&company=GT%20Lantin%20Internal'
for i in range(200):
    try:
        r=requests.get(url, timeout=10)
        print(i, r.status_code)
    except Exception as e:
        print('err', i, type(e).__name__, e)
    time.sleep(0.02)
