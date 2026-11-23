import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'streaming_gateway.dart';

class GatewayException implements Exception {
  const GatewayException(this.code);
  final String code;
  @override
  String toString() => code;
}

class ModelGateway {
  ModelGateway(
    this.baseUrl,
    this.token, {
    this.accountSession = false,
    this.useV2 = false,
    this.useV3 = false,
  });
  final String baseUrl, token;
  final bool useV2, useV3, accountSession;
  bool voiceEnabled = true;
  late final StreamingGateway streaming = StreamingGateway(baseUrl, token);
  final _turnClocks = <String, Stopwatch>{};
  void prepareTurn(String id, Stopwatch clock) => _turnClocks[id] = clock;
  void forgetTurn(String id) => _turnClocks.remove(id);
  final _clients = <String, HttpClient>{};
  static String requestId() => List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  static ModelGateway? configured() {
    const url = String.fromEnvironment('MODEL_GATEWAY_URL');
    const token = String.fromEnvironment('MODEL_GATEWAY_TOKEN');
    if (url.isEmpty || token.isEmpty) return null;
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' &&
            ['127.0.0.1', 'localhost', '10.0.2.2'].contains(uri.host))) {
      throw const GatewayException('HTTPS_REQUIRED');
    }
    const protocol = String.fromEnvironment(
      'MODEL_GATEWAY_PROTOCOL',
      defaultValue: 'v3',
    );
    return ModelGateway(
      url,
      token,
      useV2: protocol == 'v2' && Platform.isAndroid,
      useV3: protocol == 'v3' && (Platform.isAndroid || Platform.isIOS),
    );
  }

  Future<HttpClientResponse> _post(
    HttpClient client,
    String path,
    Map<String, Object?> body,
  ) async {
    client.connectionTimeout = const Duration(seconds: 10);
    final request = await client.postUrl(Uri.parse('$baseUrl$path'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    return request.close().timeout(const Duration(seconds: 100));
  }

  Future<Never> _error(HttpClientResponse response) async {
    final text = await utf8.decoder.bind(response).join();
    String code = 'GATEWAY_UNAVAILABLE';
    try {
      code = (jsonDecode(text) as Map)['error']['code'] as String;
    } catch (_) {}
    throw GatewayException(code);
  }

  Stream<String> reply({
    required String requestId,
    required String character,
    required String content,
    required List<Map<String, String>> history,
  }) async* {
    if (useV2) {
      yield* streaming.reply(
        requestId: requestId,
        character: character,
        content: content,
        history: history,
        voice: voiceEnabled,
        clock: _turnClocks.remove(requestId),
      );
      return;
    }
    final client = HttpClient();
    _clients[requestId] = client;
    var completed = false;
    var received = '';
    try {
      final response = await _post(
        client,
        '/v1/conversations/local-$character/messages',
        {
          'request_id': requestId,
          'character_id': character,
          'content': content,
          'history': history,
        },
      );
      if (response.statusCode != 200) await _error(response);
      await for (final line
          in utf8.decoder
              .bind(response)
              .transform(const LineSplitter())
              .timeout(const Duration(seconds: 100))) {
        if (!line.startsWith('data:')) continue;
        final event = jsonDecode(line.substring(5).trim()) as Map;
        switch (event['event']) {
          case 'message.delta':
            final delta = event['delta'] as String;
            received += delta;
            yield delta;
          case 'message.completed':
            final full = event['content'] as String;
            if (received.isEmpty) {
              yield full;
            } else if (received != full) {
              throw const GatewayException('INCOMPLETE_REPLY');
            }
            completed = true;
          case 'message.failed':
          case 'message.cancelled':
            throw GatewayException(
              event['code'] as String? ?? 'MODEL_UNAVAILABLE',
            );
        }
      }
      if (!completed) throw const GatewayException('INCOMPLETE_REPLY');
    } finally {
      client.close(force: true);
      _clients.remove(requestId);
    }
  }

  Future<Uint8List> speech({
    required String requestId,
    required String replyRequestId,
    required String character,
  }) async {
    final client = HttpClient();
    _clients[requestId] = client;
    try {
      final response = await _post(client, '/v1/audio/speech', {
        'request_id': requestId,
        'reply_request_id': replyRequestId,
        'character_id': character,
        'expression': 'calm',
      });
      if (response.statusCode != 200) await _error(response);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(
        const Duration(seconds: 100),
      )) {
        bytes.add(chunk);
        if (bytes.length > 13 * 1024 * 1024) {
          throw const GatewayException('VOICE_TOO_LARGE');
        }
      }
      final result = bytes.takeBytes();
      if (result.length <= 44 || ascii.decode(result.sublist(0, 4)) != 'RIFF') {
        throw const GatewayException('VOICE_EMPTY');
      }
      return result;
    } finally {
      client.close(force: true);
      _clients.remove(requestId);
    }
  }

  Future<void> cancel(String id) async {
    if (useV2) {
      streaming.cancel(id, wholeTurn: true);
      return;
    }
    _clients.remove(id)?.close(force: true);
    final client = HttpClient();
    try {
      await _post(client, '/v1/requests/$id/cancel', {})
          .then((response) => response.drain<void>())
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Local generation tokens still reject late results if the service is offline.
    } finally {
      client.close(force: true);
    }
  }

  Future<void> cancelSpeech(String id) async {
    if (useV2) {
      streaming.cancel(id);
    } else {
      await cancel(id);
    }
  }

  Future<void> close() async {
    if (useV2) await streaming.close();
  }
}
