// Flip this only when switching between your PC backend and Railway.
const bool useHostedBackend = false;

const String _localBackendRoot = 'http://localhost:5000';
const String _hostedBackendRoot =
    'https://shervice-python-production.up.railway.app';

const String localIp =
    useHostedBackend ? _hostedBackendRoot : _localBackendRoot;
const String backendUrl = '$localIp/api';
