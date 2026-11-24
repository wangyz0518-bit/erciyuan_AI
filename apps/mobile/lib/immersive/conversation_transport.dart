import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'model_gateway.dart' show GatewayException;

/// One role-scoped WebSocket. Reconnect restores history without replaying input.
class ConversationTransport {
  ConversationTransport(
    this.baseUrl,
    this.token, {
    this.accountSession = false,
  });
  final bool accountSession;
  final String baseUrl, token;
  // An isolated Mac test gateway can supply its own development CA. Normal
  // HTTPS gateways continue to use the system roots.
  static SecurityContext? localTrust() {
    const encoded = String.fromEnvironment('MODEL_GATEWAY_CA_DER');
    if (encoded.isEmpty) return null;
    final context = SecurityContext();
    if (Platform.isIOS) {
      try {
        context.setTrustedCertificatesBytes(base64Decode(encoded));
        return context;
      } on TlsException {
        // Dart runtimes using BoringSSL's trust loader accept PEM.
      }
    }
    final pem =
        '-----BEGIN CERTIFICATE-----\n$encoded\n-----END CERTIFICATE-----\n';
    return context..setTrustedCertificatesBytes(ascii.encode(pem));
  }

  late final SecurityContext? _trust = localTrust();
  late final HttpClient? _secureSocketClient = _trust == null
      ? null
      : HttpClient(context: _trust);
  WebSocket? _socket;
  String? _session;
  int _epoch = 0;
  String mode = '';
  final _events = StreamController<Map<String, Object?>>.broadcast(sync: true);
  Stream<Map<String, Object?>> get events => _events.stream;

  bool get connected =>
      _session != null && _socket?.readyState == WebSocket.open;

  Uri _uri(String path) => Uri.parse(baseUrl).replace(path: path);

  Future<List<Map<String, Object?>>> open(String character) async {
    await close();
    final epoch = ++_epoch;
    final uri = _uri('/v3/conversations/$character/stream');
    final handshake = Completer<List<Map<String, Object?>>>();
    // A dropped or superseded handshake is consumed even if the socket opens late.
    final ready = handshake.future.timeout(const Duration(seconds: 8));
    unawaited(ready.then<void>((_) {}, onError: (Object _) {}));
    try {
      final upgrade = WebSocket.connect(
        uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString(),
        customClient: _secureSocketClient,
      );
      // Dart cannot cancel an in-flight WebSocket upgrade. Close any late result.
      unawaited(
        upgrade.then<void>((socket) {
          if (epoch != _epoch) unawaited(socket.close());
        }, onError: (Object _) {}),
      );
      final socket = await upgrade.timeout(const Duration(seconds: 8));
      if (epoch != _epoch) {
        await socket.close();
        throw const GatewayException('SESSION_SUPERSEDED');
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 25);
      void lost(Object error) {
        if (!identical(_socket, socket)) return;
        _socket = null;
        _session = null;
        if (!handshake.isCompleted) {
          handshake.completeError(error);
        } else if (!_events.isClosed) {
          _events.add({'event': 'connection.lost'});
        }
      }

      socket.listen(
        (dynamic value) {
          if (!identical(_socket, socket)) return;
          try {
            final packet = _decode(value);
            if (!handshake.isCompleted) {
              if (packet['event'] == 'session.failed') {
                throw GatewayException(
                  packet['code'] as String? ?? 'SESSION_FAILED',
                );
              }
              if (packet['event'] != 'session.ready' ||
                  packet['protocol'] != 3 ||
                  packet['character_id'] != character) {
                throw const GatewayException('INVALID_SESSION');
              }
              _session = packet['session_id'] as String;
              mode = packet['mode'] as String;
              handshake.complete(_rows(packet['history']));
            } else if (packet['session_id'] == _session) {
              _events.add(packet);
            }
          } catch (error) {
            lost(error);
            unawaited(socket.close());
          }
        },
        onError: (Object _) => lost(const GatewayException('CONNECTION_LOST')),
        onDone: () => lost(const GatewayException('CONNECTION_LOST')),
      );
      socket.add(jsonEncode({'command': 'session.start', 'token': token}));
      return await ready;
    } catch (_) {
      if (epoch == _epoch) await close();
      rethrow;
    }
  }

  static List<Map<String, Object?>> _rows(Object? value) =>
      (value as List).map((e) => Map<String, Object?>.from(e as Map)).toList();

  static Map<String, Object?> _decode(dynamic value) {
    if (value is String) {
      return Map<String, Object?>.from(jsonDecode(value) as Map);
    }
    if (value is! List<int> ||
        value.length < 7 ||
        value.length > 192000 + 4100) {
      throw const FormatException('Invalid audio message');
    }
    final data = value is Uint8List ? value : Uint8List.fromList(value);
    final count = ByteData.sublistView(data).getUint32(0);
    if (count == 0 ||
        count > 4096 ||
        4 + count >= data.length ||
        (data.length - 4 - count).isOdd) {
      throw const FormatException('Invalid audio header');
    }
    final header = Map<String, Object?>.from(
      jsonDecode(utf8.decode(Uint8List.sublistView(data, 4, count + 4))) as Map,
    );
    if (header['event'] != 'audio.chunk') throw const FormatException();
    return header..['pcm'] = Uint8List.sublistView(data, count + 4);
  }

  void send(String command, [Map<String, Object?> fields = const {}]) {
    if (!connected) throw const GatewayException('CONNECTION_LOST');
    _socket!.add(jsonEncode({'command': command, ...fields}));
  }

  void samples(String id, int seq, Uint8List pcm) {
    if (!connected) throw const GatewayException('CONNECTION_LOST');
    final header = utf8.encode(jsonEncode({'input_id': id, 'seq': seq}));
    final bytes = Uint8List(4 + header.length + pcm.length);
    ByteData.sublistView(bytes).setUint32(0, header.length);
    bytes.setRange(4, 4 + header.length, header);
    bytes.setRange(4 + header.length, bytes.length, pcm);
    _socket!.add(bytes);
  }

  Future<void> close() async {
    ++_epoch;
    final socket = _socket;
    final wasConnected = connected;
    _socket = null;
    _session = null;
    if (socket == null) return;
    if (wasConnected) socket.add('{"command":"session.end"}');
    await socket.close().timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  Future<void> dispose() async {
    try {
      await close();
    } finally {
      _secureSocketClient?.close(force: true);
      await _events.close();
    }
  }

  Future<Uint8List> _request(
    String path, {
    Map<String, Object?>? update,
  }) async {
    final client = HttpClient(context: _trust)
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(
        update == null ? 'GET' : 'PUT',
        _uri(path),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (update != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(update));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final body = await response
          .timeout(const Duration(seconds: 8))
          .fold<BytesBuilder>(BytesBuilder(copy: false), (b, chunk) {
            if (b.length + chunk.length > 2 * 1024 * 1024) {
              throw const FormatException();
            }
            return b..add(chunk);
          });
      final bytes = body.takeBytes();
      if (response.statusCode != 200) {
        var code = 'REQUEST_FAILED';
        try {
          code =
              (jsonDecode(utf8.decode(bytes)) as Map)['error']['code']
                  as String;
        } catch (_) {
          /* HTTP response was not a gateway error. */
        }
        throw GatewayException(code);
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> recording(String id) => _request('/v3/recordings/$id');

  Future<List<Map<String, Object?>>> voices() async => _rows(
    (jsonDecode(
      utf8.decode(
        await _request(
          accountSession ? '/community/voices' : '/v1/voice-profiles',
        ),
      ),
    ) as Map)['items'],
  );

  Future<Map<String, Object?>> binding(
    String role,
  ) async => Map<String, Object?>.from(
    jsonDecode(
      utf8.decode(
        await _request(
          '${accountSession ? '/community' : '/v1'}/characters/$role/voice-binding',
        ),
      ),
    ) as Map,
  );

  Future<void> bind(String role, String? id, int revision) async {
    await _request(
      '${accountSession ? '/community' : '/v1'}/characters/$role/voice-binding',
      update: {'profile_id': id, 'revision': revision},
    );
  }
}
