from app import TransportBackendApp

server = TransportBackendApp()
app = server.app

if __name__ == '__main__':
    # Fallback: run directly for quick local debugging
    server.run()
