/// Runtime endpoints and application-wide configuration.
///
/// Keep environment-specific values in this file so feature code does not
/// need to own or duplicate backend configuration.
const bool useHostedBackend = true;

const String _localBackendRoot = 'http://localhost:5000';
const String _hostedBackendRoot = 'https://gtlantinshervice.com';
const String _localEncryptedSocketRoot = 'ws://localhost:5001';
const String _hostedEncryptedSocketRoot = 'wss://gtlantinshervice.com/ws';

const String localIp = useHostedBackend
    ? _hostedBackendRoot
    : _localBackendRoot;
const String backendUrl = '$localIp/api';
const String encryptedSocketUrl = useHostedBackend
    ? _hostedEncryptedSocketRoot
    : _localEncryptedSocketRoot;
