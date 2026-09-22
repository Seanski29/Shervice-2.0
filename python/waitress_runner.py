import os

from app import TransportBackendApp
from waitress import serve

server = TransportBackendApp()
app = server.app

if __name__ == '__main__':
    serve(
        app,
        host=os.getenv("FLASK_HOST", "127.0.0.1"),
        port=int(os.getenv("FLASK_PORT", "5000")),
    )
