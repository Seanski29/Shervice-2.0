/// Runtime endpoints and application-wide configuration.
///
/// Keep environment-specific values in this file so feature code does not
/// need to own or duplicate backend configuration.
const bool useHostedBackend = false;

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
