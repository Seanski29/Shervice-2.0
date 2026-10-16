import unittest

from flask import Flask

from roles.errors import internal_error


class ApiErrorResponseTests(unittest.TestCase):
    def test_internal_error_hides_exception_and_preserves_response_fields(self):
        app = Flask(__name__)

        @app.get('/api/example')
        def example():
            try:
                raise RuntimeError('private database connection details')
            except RuntimeError:
                return internal_error('Unable to load data.', connection_status='FAILED')

        response = app.test_client().get('/api/example')
        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json['message'], 'Unable to load data.')
        self.assertEqual(response.json['error'], 'Unable to load data.')
        self.assertEqual(response.json['connection_status'], 'FAILED')
        self.assertNotIn('private database', response.get_data(as_text=True))


if __name__ == '__main__':
    unittest.main()
