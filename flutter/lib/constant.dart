// Flip this only when switching between your PC backend and Railway.
const bool useHostedBackend = true;

const String _localBackendRoot = 'http://localhost:5000';
const String _hostedBackendRoot =
    'https://shervice-python-production.up.railway.app';
const String _localEncryptedSocketRoot = 'ws://localhost:5001';
const String _hostedEncryptedSocketRoot =
    'wss://shervice-python-production.up.railway.app/ws';

const String localIp = useHostedBackend
    ? _hostedBackendRoot
    : _localBackendRoot;
const String backendUrl = '$localIp/api';
const String encryptedSocketUrl = useHostedBackend
    ? _hostedEncryptedSocketRoot
    : _localEncryptedSocketRoot;

// Public URL used for passenger evaluation links and QR codes.
// Keep this separate from the backend URL so evaluation links never point to
// localhost when the application is running in production.
const String publicEvaluationBaseUrl = 'https://gtlantinshervice.com';
