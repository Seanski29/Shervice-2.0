import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_config.dart';

class EncryptedSocketClient {
  EncryptedSocketClient({this.socketUrl = encryptedSocketUrl});

  final String socketUrl;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  final Random _random = Random.secure();

  WebSocketChannel? _channel;
  SimpleKeyPair? _clientKeyPair;
  List<int>? _clientNonce;
  SecretKey? _sessionKey;
  Completer<void>? _ready;
  final Map<String, Completer<EncryptedApiResponse>> _pendingRequests = {};

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  bool get isConnected => _channel != null && _sessionKey != null;

  Future<void> connect({required String accessToken}) async {
    if (_channel != null) return;

    _ready = Completer<void>();
    _clientKeyPair = await X25519().newKeyPair();
    final publicKey = await _clientKeyPair!.extractPublicKey();
    final clientNonce = _randomBytes(16);
    _clientNonce = clientNonce;

    final channel = WebSocketChannel.connect(Uri.parse(socketUrl));
    _channel = channel;
    channel.stream.listen(
      (frame) => unawaited(_handleFrame(frame)),
      onError: (error) {
        if (!(_ready?.isCompleted ?? true)) _ready?.completeError(error);
        _messages.addError(error);
      },
      onDone: () {
        _channel = null;
        _sessionKey = null;
      },
    );

    channel.sink.add(jsonEncode({
      'type': 'hello',
      'token': accessToken,
      'client_public_key': base64Encode(publicKey.bytes),
      'client_nonce': base64Encode(clientNonce),
    }));

    await _ready!.future.timeout(const Duration(seconds: 10));
  }

  Future<void> send(Map<String, dynamic> payload) async {
    final channel = _channel;
    final sessionKey = _sessionKey;
    if (channel == null || sessionKey == null) {
      throw StateError('Encrypted socket is not connected.');
    }

    final encrypted = await _encrypt(payload, sessionKey);
    channel.sink.add(jsonEncode(encrypted));
  }

  Future<EncryptedApiResponse> request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
    final completer = Completer<EncryptedApiResponse>();
    _pendingRequests[requestId] = completer;

    try {
      await send({
        'type': 'api_request',
        'request_id': requestId,
        'method': method.toUpperCase(),
        'path': path,
        if (body != null) 'body': body,
        if (query != null) 'query': query,
      });
      return await completer.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      _pendingRequests.remove(requestId);
      rethrow;
    }
  }

  Future<void> ping() {
    return send({
      'type': 'ping',
      'sent_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> close() async {
    await _channel?.sink.close();
    _channel = null;
    _sessionKey = null;
    for (final pending in _pendingRequests.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Encrypted socket was closed.'));
      }
    }
    _pendingRequests.clear();
    await _messages.close();
  }

  Future<void> _handleFrame(dynamic frame) async {
    if (frame is! String) return;
    final decoded = jsonDecode(frame);
    if (decoded is! Map) return;
    final payload = Map<String, dynamic>.from(decoded);

    if (payload['type'] == 'hello_ack') {
      await _completeHandshake(payload);
      return;
    }

    final sessionKey = _sessionKey;
    if (payload['type'] == 'secure' && sessionKey != null) {
      final message = await _decrypt(payload, sessionKey);
      final requestId = message['request_id']?.toString();
      final pending = requestId == null ? null : _pendingRequests.remove(requestId);
      if (message['type'] == 'api_response' && pending != null) {
        pending.complete(EncryptedApiResponse.fromJson(message));
        return;
      }
      _messages.add(message);
    }
  }

  Future<void> _completeHandshake(Map<String, dynamic> payload) async {
    final clientKeyPair = _clientKeyPair;
    final clientNonce = _clientNonce;
    if (clientKeyPair == null) {
      throw StateError('Missing client key pair.');
    }
    if (clientNonce == null) {
      throw StateError('Missing client nonce.');
    }

    final serverPublicKeyBytes = base64Decode(
      payload['server_public_key'].toString(),
    );
    final serverNonce = base64Decode(payload['server_nonce'].toString());
    final publicKey = SimplePublicKey(
      serverPublicKeyBytes,
      type: KeyPairType.x25519,
    );
    final sharedSecret = await X25519().sharedSecretKey(
      keyPair: clientKeyPair,
      remotePublicKey: publicKey,
    );
    _sessionKey = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(
      secretKey: sharedSecret,
      nonce: [...clientNonce, ...serverNonce],
      info: utf8.encode('shervice-encrypted-websocket-v1'),
    );

    if (!(_ready?.isCompleted ?? true)) _ready?.complete();
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }

  Future<Map<String, String>> _encrypt(
    Map<String, dynamic> payload,
    SecretKey key,
  ) async {
    final nonce = _randomBytes(12);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: nonce,
    );
    return {
      'type': 'secure',
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  Future<Map<String, dynamic>> _decrypt(
    Map<String, dynamic> payload,
    SecretKey key,
  ) async {
    final nonce = base64Decode(payload['nonce'].toString());
    final combined = base64Decode(payload['ciphertext'].toString());
    if (combined.length < 17) {
      throw const FormatException('Encrypted payload is too short.');
    }
    final cipherText = combined.sublist(0, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));
    final clearBytes = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
    final decoded = jsonDecode(utf8.decode(clearBytes));
    return Map<String, dynamic>.from(decoded as Map);
  }
}

class EncryptedApiResponse {
  const EncryptedApiResponse({
    required this.status,
    required this.body,
  });

  factory EncryptedApiResponse.fromJson(Map<String, dynamic> json) {
    return EncryptedApiResponse(
      status: int.tryParse(json['status'].toString()) ?? 0,
      body: json['body'],
    );
  }

  final int status;
  final Object? body;

  bool get isOk => status >= 200 && status < 300;
}
