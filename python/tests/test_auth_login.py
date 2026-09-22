import json

from app import app
import roles.auth as auth_module


class FakeUser:
    def __init__(self, user_id):
        self.id = user_id


class FakeSession:
    def __init__(self, token):
        self.access_token = token


class FakeAuth:
    def __init__(self, *, raise_error=False):
        self.raise_error = raise_error

    def sign_in_with_password(self, payload):
        if self.raise_error:
            raise RuntimeError('bad credentials or database issue')
        return type('Response', (), {
            'user': FakeUser('auth-user-123'),
            'session': FakeSession('secret-token'),
        })()


class FakeTable:
    def __init__(self, data):
        self.data = data

    def select(self, *_args, **_kwargs):
        return self

    def eq(self, *_args, **_kwargs):
        return self

    def in_(self, *_args, **_kwargs):
        return self

    def execute(self):
        return type('Result', (), {'data': self.data})()


def test_login_success_for_staff_account():
    auth_module.supabase = type('Supabase', (), {
        'auth': FakeAuth(),
        'table': lambda *_args, **_kwargs: FakeTable([
            {'user_id': 'auth-user-123', 'role': 'staff', 'full_name': 'Jane Staff', 'staff_id': 'S-42'}
        ]),
    })()

    client = app.test_client()
    response = client.post('/api/auth/login', json={'email': 'jane@company.com', 'password': 'secret'})

    assert response.status_code == 200
    payload = response.get_json()
    assert payload['success'] is True
    assert payload['data']['role'] == 'staff'
    assert payload['data']['token'] == 'secret-token'


def test_login_error_logs_traceback_and_returns_401(caplog):
    auth_module.supabase = type('Supabase', (), {
        'auth': FakeAuth(raise_error=True),
        'table': lambda *_args, **_kwargs: FakeTable([]),
    })()

    client = app.test_client()
    response = client.post('/api/auth/login', json={'email': 'bad@company.com', 'password': 'wrong'})

    assert response.status_code == 401
    payload = response.get_json()
    assert payload['success'] is False
    assert 'Invalid email or password credentials.' in payload['message']
    assert 'Login failed for email=bad@company.com' in caplog.text
    assert 'bad credentials or database issue' in caplog.text


def test_cors_allows_localhost_origin():
    client = app.test_client()
    response = client.options(
        '/api/auth/login',
        headers={
            'Origin': 'http://localhost:3000',
            'Access-Control-Request-Method': 'POST',
            'Access-Control-Request-Headers': 'Content-Type, Authorization',
        },
    )

    assert response.status_code == 200
    assert response.headers.get('Access-Control-Allow-Origin') == 'http://localhost:3000'
