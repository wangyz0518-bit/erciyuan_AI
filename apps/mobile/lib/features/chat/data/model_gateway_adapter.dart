import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../characters/domain/character.dart';
import '../../audio/domain/audio_ports.dart';
import '../../voice/data/character_reply_playback.dart';
import '../../memory/domain/memory_models.dart';
import '../../timeline/data/person_database.dart';
import '../../timeline/domain/raw_event.dart';

enum ModelTurnStatus { completed, failed, cancelled, unknown }

enum ModelTurnUpdateType {
  started,
  delta,
  completed,
  failed,
  cancelled,
  unknown,
}

class ModelTurnUpdate {
  const ModelTurnUpdate({
    required this.scope,
    required this.requestId,
    required this.type,
    this.delta,
    this.content,
    this.errorCode,
  });

  final PersonScope scope;
  final String requestId;
  final ModelTurnUpdateType type;
  final String? delta;
  final String? content;
  final String? errorCode;
}

class ModelTurnResult {
  const ModelTurnResult({
    required this.scope,
    required this.requestId,
    required this.status,
    this.content = '',
    this.errorCode,
  });

  final PersonScope scope;
  final String requestId;
  final ModelTurnStatus status;
  final String content;
  final String? errorCode;
}

class ModelGatewayException implements Exception {
  const ModelGatewayException(this.code);

  final String code;

  @override
  String toString() => 'ModelGatewayException($code)';
}

typedef ModelTurnUpdateCallback = void Function(ModelTurnUpdate update);

/// HTTP/SSE adapter for one character turn.
///
/// The provider key never enters this class. The access token is a local
/// development gateway token and must be injected at runtime, not hardcoded.
final class ModelGatewayAdapter {
  ModelGatewayAdapter({
    required Uri baseUri,
    required String accessToken,
    required this.database,
    HttpClient? httpClient,
    Duration requestTimeout = const Duration(seconds: 45),
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _client = httpClient ?? HttpClient(),
       _requestTimeout = requestTimeout {
    if (!baseUri.hasAuthority ||
        !const ['http', 'https'].contains(baseUri.scheme)) {
      throw ArgumentError.value(baseUri, 'baseUri', 'Expected an HTTP(S) URI');
    }
    if (accessToken.trim().isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken');
    }
    _client.connectionTimeout = requestTimeout;
  }

  final Uri _baseUri;
  final String _accessToken;
  final PersonDatabase database;
  final HttpClient _client;
  final Duration _requestTimeout;
  final Map<String, HttpClientRequest> _activeRequests = {};
  bool _closed = false;

  String _requestKey(PersonScope scope, String requestId) =>
      '${scope.ownerId}|${scope.characterId}|$requestId';

  Uri _endpoint(String relativePath) {
    final base = _baseUri.path.endsWith('/')
        ? _baseUri
        : _baseUri.replace(path: '${_baseUri.path}/');
    return base.resolve(relativePath);
  }

  static final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{16,100}$');

  CharacterReplyPlayback createSpeechPlayback(
    PersonScope scope,
    AudioPcmPlaybackPort player,
  ) => CharacterReplyPlayback(
    _endpoint('v1/characters/${Uri.encodeComponent(scope.characterId)}/turns/'),
    _accessToken,
    player,
  );
  static final RegExp _identityVersionPattern = RegExp(
    r'^identity_version=(\d+)$',
    multiLine: true,
  );

  static int _identityVersion(String stablePrefix) {
    final match = _identityVersionPattern.firstMatch(stablePrefix);
    if (match == null) {
      throw const ModelGatewayException('INVALID_IDENTITY_PREFIX');
    }
    return int.parse(match.group(1)!);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('ModelGatewayAdapter is closed');
  }

  void _notify(ModelTurnUpdateCallback? callback, ModelTurnUpdate update) {
    if (callback == null) return;
    try {
      callback(update);
    } catch (_) {
      // A presentation callback must not interrupt persistence or protocol work.
    }
  }

  Map<String, Object?> _eventJson(RawEvent event) => {
    'event_id': event.eventId,
    'role': event.speaker == 'assistant' ? 'assistant' : 'user',
    'content': event.content,
  };

  Map<String, Object?> _requestBody({
    required PersonScope scope,
    required String requestId,
    required String eventId,
    required String content,
    required MemoryContext context,
    required String? retryOf,
  }) {
    return {
      'protocol_version': 1,
      'request_id': requestId,
      'character_id': scope.characterId,
      'current_input': {'event_id': eventId, 'content': content},
      'context': {
        'prefix_version': context.promptTemplateVersion,
        'identity_version': _identityVersion(context.stablePrefix),
        'stable_prefix': context.stablePrefix,
        'selected_summaries': [
          for (final summary in context.recalledSummaries)
            {
              'summary_id': summary.summaryId,
              'text': summary.text,
              'source_event_ids': summary.sourceEventIds,
            },
        ],
        'recent_events': context.recentEvents.map(_eventJson).toList(),
        'expanded_sources': context.expandedSourceEvents
            .map(_eventJson)
            .toList(),
      },
      'model_profile': 'default-text',
      'retry_of': retryOf,
    };
  }

  /// Starts a new generation request. Retry must use a new requestId and may
  /// reuse the original userEventId; the current input is excluded from its own
  /// assembled context so a retry does not duplicate the user message.
  Future<ModelTurnResult> sendTurn({
    required PersonScope scope,
    required String requestId,
    required String userEventId,
    required String content,
    String? retryOf,
    ModelTurnUpdateCallback? onUpdate,
  }) async {
    _ensureOpen();
    if (!_requestIdPattern.hasMatch(requestId) ||
        (retryOf != null && !_requestIdPattern.hasMatch(retryOf))) {
      throw const ModelGatewayException('INVALID_REQUEST_ID');
    }
    if (content.trim().isEmpty || userEventId.trim().isEmpty) {
      throw const ModelGatewayException('INVALID_CURRENT_INPUT');
    }

    final existingUserEvent = await database.rawEventById(
      scope: scope,
      eventId: userEventId,
    );
    if (existingUserEvent != null &&
        (existingUserEvent.speaker != 'user' ||
            existingUserEvent.status != 'complete' ||
            existingUserEvent.content != content)) {
      throw const ModelGatewayException('CURRENT_EVENT_CONFLICT');
    }

    final context = await database.memory.assembleContext(
      scope: scope,
      currentInput: content,
      expandSources: true,
      excludeEventId: userEventId,
    );
    final body = _requestBody(
      scope: scope,
      requestId: requestId,
      eventId: userEventId,
      content: content,
      context: context,
      retryOf: retryOf,
    );

    final registered = await database.registerGeneration(
      scope: scope,
      requestId: requestId,
      retryOf: retryOf,
    );
    if (!registered) throw const ModelGatewayException('DUPLICATE_REQUEST');

    try {
      if (existingUserEvent == null) {
        await database.appendEvent(
          scope: scope,
          eventId: userEventId,
          speaker: 'user',
          kind: 'message',
          content: content,
          status: 'complete',
          requestId: requestId,
        );
      }
    } catch (_) {
      await database.setGenerationStatus(
        scope: scope,
        requestId: requestId,
        status: 'failed',
      );
      rethrow;
    }

    final key = _requestKey(scope, requestId);
    HttpClientRequest? request;
    try {
      request = await _client.postUrl(
        _endpoint(
          'v1/characters/${Uri.encodeComponent(scope.characterId)}/turns',
        ),
      );
      _activeRequests[key] = request;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_accessToken',
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.write(jsonEncode(body));

      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        final responseBody = await utf8
            .decodeStream(response)
            .timeout(_requestTimeout);
        final code = _errorCode(responseBody) ?? 'HTTP_${response.statusCode}';
        if (response.statusCode >= 500) {
          return await reconcileTurn(
            scope: scope,
            requestId: requestId,
            onUpdate: onUpdate,
          );
        }
        await database.setGenerationStatus(
          scope: scope,
          requestId: requestId,
          status: 'failed',
        );
        return ModelTurnResult(
          scope: scope,
          requestId: requestId,
          status: ModelTurnStatus.failed,
          errorCode: code,
        );
      }

      return await _consumeSse(
        response: response,
        scope: scope,
        requestId: requestId,
        onUpdate: onUpdate,
      );
    } on TimeoutException {
      request?.abort();
      return await reconcileTurn(
        scope: scope,
        requestId: requestId,
        onUpdate: onUpdate,
      );
    } on SocketException {
      return await reconcileTurn(
        scope: scope,
        requestId: requestId,
        onUpdate: onUpdate,
      );
    } on HttpException {
      return await reconcileTurn(
        scope: scope,
        requestId: requestId,
        onUpdate: onUpdate,
      );
    } on FormatException {
      await _markUnknown(scope, requestId);
      return ModelTurnResult(
        scope: scope,
        requestId: requestId,
        status: ModelTurnStatus.unknown,
        errorCode: 'INVALID_SSE_RESPONSE',
      );
    } catch (_) {
      await _markUnknown(scope, requestId);
      rethrow;
    } finally {
      _activeRequests.remove(key);
    }
  }

  Future<ModelTurnResult> _consumeSse({
    required HttpClientResponse response,
    required PersonScope scope,
    required String requestId,
    required ModelTurnUpdateCallback? onUpdate,
  }) async {
    final dataLines = <String>[];
    final streamed = StringBuffer();
    var receivedDelta = false;
    ModelTurnResult? terminal;

    Future<void> dispatchFrame(String data) async {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('SSE data must be a JSON object');
      }
      if (decoded['request_id'] != requestId) {
        throw const FormatException('SSE request_id mismatch');
      }
      final responseCharacter = decoded['character_id'];
      if (responseCharacter is String &&
          responseCharacter != scope.characterId) {
        throw const FormatException('SSE character_id mismatch');
      }

      final event = decoded['event'];
      switch (event) {
        case 'message.started':
          _notify(
            onUpdate,
            ModelTurnUpdate(
              scope: scope,
              requestId: requestId,
              type: ModelTurnUpdateType.started,
            ),
          );
          break;
        case 'message.delta':
          final delta = decoded['delta'];
          if (delta is! String) {
            throw const FormatException('SSE delta must be a string');
          }
          receivedDelta = true;
          streamed.write(delta);
          _notify(
            onUpdate,
            ModelTurnUpdate(
              scope: scope,
              requestId: requestId,
              type: ModelTurnUpdateType.delta,
              delta: delta,
            ),
          );
          break;
        case 'message.completed':
          final content = decoded['content'];
          if (content is! String || content.trim().isEmpty) {
            throw const FormatException('Completed SSE content is missing');
          }
          if (receivedDelta && streamed.toString() != content) {
            throw const FormatException(
              'SSE final content does not match deltas',
            );
          }
          await database.completeGeneration(
            scope: scope,
            requestId: requestId,
            eventId: 'assistant-$requestId',
            content: content,
          );
          terminal = ModelTurnResult(
            scope: scope,
            requestId: requestId,
            status: ModelTurnStatus.completed,
            content: content,
          );
          _notify(
            onUpdate,
            ModelTurnUpdate(
              scope: scope,
              requestId: requestId,
              type: ModelTurnUpdateType.completed,
              content: content,
            ),
          );
          break;
        case 'message.failed':
          final code = decoded['code'] is String
              ? decoded['code'] as String
              : 'MODEL_UNAVAILABLE';
          await database.setGenerationStatus(
            scope: scope,
            requestId: requestId,
            status: 'failed',
          );
          terminal = ModelTurnResult(
            scope: scope,
            requestId: requestId,
            status: ModelTurnStatus.failed,
            errorCode: code,
          );
          _notify(
            onUpdate,
            ModelTurnUpdate(
              scope: scope,
              requestId: requestId,
              type: ModelTurnUpdateType.failed,
              errorCode: code,
            ),
          );
          break;
        case 'message.cancelled':
          await database.setGenerationStatus(
            scope: scope,
            requestId: requestId,
            status: 'cancelled',
          );
          terminal = ModelTurnResult(
            scope: scope,
            requestId: requestId,
            status: ModelTurnStatus.cancelled,
            errorCode: 'REQUEST_CANCELLED',
          );
          _notify(
            onUpdate,
            ModelTurnUpdate(
              scope: scope,
              requestId: requestId,
              type: ModelTurnUpdateType.cancelled,
            ),
          );
          break;
        case 'message.unknown':
          final code = decoded['code'] is String
              ? decoded['code'] as String
              : 'RESULT_UNKNOWN';
          await database.setGenerationStatus(
            scope: scope,
            requestId: requestId,
            status: 'unknown',
          );
          terminal = ModelTurnResult(
            scope: scope,
            requestId: requestId,
            status: ModelTurnStatus.unknown,
            errorCode: code,
          );
          _notify(
            onUpdate,
            ModelTurnUpdate(
              scope: scope,
              requestId: requestId,
              type: ModelTurnUpdateType.unknown,
              errorCode: code,
            ),
          );
          break;
        case 'turn.status':
          terminal = await _applyStatus(
            scope: scope,
            requestId: requestId,
            data: decoded,
            onUpdate: onUpdate,
          );
          break;
        default:
          throw FormatException('Unsupported SSE event: $event');
      }
    }

    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(_requestTimeout);
    await for (final line in lines) {
      if (line.isEmpty) {
        if (dataLines.isNotEmpty) {
          await dispatchFrame(dataLines.join('\n'));
          dataLines.clear();
          if (terminal != null) break;
        }
      } else if (line.startsWith(':')) {
        continue;
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (terminal != null) return terminal!;
    if (dataLines.isNotEmpty) {
      await dispatchFrame(dataLines.join('\n'));
      if (terminal != null) return terminal!;
    }
    return await reconcileTurn(
      scope: scope,
      requestId: requestId,
      onUpdate: onUpdate,
    );
  }

  Future<ModelTurnResult> _applyStatus({
    required PersonScope scope,
    required String requestId,
    required Map<String, dynamic> data,
    required ModelTurnUpdateCallback? onUpdate,
  }) async {
    final responseCharacter = data['character_id'];
    if (responseCharacter is String && responseCharacter != scope.characterId) {
      await _markUnknown(scope, requestId);
      return ModelTurnResult(
        scope: scope,
        requestId: requestId,
        status: ModelTurnStatus.unknown,
        errorCode: 'SCOPE_MISMATCH',
      );
    }

    final status = data['status'];
    switch (status) {
      case 'completed':
        final content = data['content'];
        if (content is! String || content.trim().isEmpty) {
          await _markUnknown(scope, requestId);
          return ModelTurnResult(
            scope: scope,
            requestId: requestId,
            status: ModelTurnStatus.unknown,
            errorCode: 'RESULT_CONTENT_MISSING',
          );
        }
        await database.completeGeneration(
          scope: scope,
          requestId: requestId,
          eventId: 'assistant-$requestId',
          content: content,
        );
        _notify(
          onUpdate,
          ModelTurnUpdate(
            scope: scope,
            requestId: requestId,
            type: ModelTurnUpdateType.completed,
            content: content,
          ),
        );
        return ModelTurnResult(
          scope: scope,
          requestId: requestId,
          status: ModelTurnStatus.completed,
          content: content,
        );
      case 'failed':
        await database.setGenerationStatus(
          scope: scope,
          requestId: requestId,
          status: 'failed',
        );
        return ModelTurnResult(
          scope: scope,
          requestId: requestId,
          status: ModelTurnStatus.failed,
          errorCode: data['error'] is String
              ? data['error'] as String
              : data['code'] as String?,
        );
      case 'cancelled':
        await database.setGenerationStatus(
          scope: scope,
          requestId: requestId,
          status: 'cancelled',
        );
        return ModelTurnResult(
          scope: scope,
          requestId: requestId,
          status: ModelTurnStatus.cancelled,
          errorCode: 'REQUEST_CANCELLED',
        );
      case 'unknown':
      case 'running':
      default:
        await _markUnknown(scope, requestId);
        return ModelTurnResult(
          scope: scope,
          requestId: requestId,
          status: ModelTurnStatus.unknown,
          errorCode: data['error'] is String
              ? data['error'] as String
              : data['code'] as String? ?? 'RESULT_UNKNOWN',
        );
    }
  }

  /// Reconciles an interrupted stream by querying the existing request ID.
  /// It never starts another provider request.
  Future<ModelTurnResult> reconcileTurn({
    required PersonScope scope,
    required String requestId,
    ModelTurnUpdateCallback? onUpdate,
  }) async {
    _ensureOpen();
    try {
      final request = await _client.getUrl(
        _endpoint(
          'v1/characters/${Uri.encodeComponent(scope.characterId)}'
          '/turns/${Uri.encodeComponent(requestId)}',
        ),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_accessToken',
      );
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await _markUnknown(scope, requestId);
        return ModelTurnResult(
          scope: scope,
          requestId: requestId,
          status: ModelTurnStatus.unknown,
          errorCode: 'RESULT_UNKNOWN',
        );
      }
      final decoded = jsonDecode(await utf8.decodeStream(response));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Status response must be a JSON object');
      }
      return await _applyStatus(
        scope: scope,
        requestId: requestId,
        data: decoded,
        onUpdate: onUpdate,
      );
    } on TimeoutException {
      await _markUnknown(scope, requestId);
    } on SocketException {
      await _markUnknown(scope, requestId);
    } on HttpException {
      await _markUnknown(scope, requestId);
    } on FormatException {
      await _markUnknown(scope, requestId);
    }
    return ModelTurnResult(
      scope: scope,
      requestId: requestId,
      status: ModelTurnStatus.unknown,
      errorCode: 'RESULT_UNKNOWN',
    );
  }

  /// Requests server cancellation, then aborts the local SSE stream. If the
  /// server cannot confirm cancellation, the result remains unknown.
  Future<ModelTurnResult> cancelTurn({
    required PersonScope scope,
    required String requestId,
  }) async {
    _ensureOpen();
    final key = _requestKey(scope, requestId);
    final activeRequest = _activeRequests[key];
    try {
      final request = await _client.postUrl(
        _endpoint(
          'v1/characters/${Uri.encodeComponent(scope.characterId)}'
          '/turns/${Uri.encodeComponent(requestId)}/cancel',
        ),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_accessToken',
      );
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode == HttpStatus.ok) {
        final decoded = jsonDecode(await utf8.decodeStream(response));
        if (decoded is Map<String, dynamic>) {
          final result = await _applyStatus(
            scope: scope,
            requestId: requestId,
            data: decoded,
            onUpdate: null,
          );
          activeRequest?.abort();
          return result;
        }
      }
    } on TimeoutException {
      // Fall through to local abort and status reconciliation.
    } on SocketException {
      // Fall through to local abort and status reconciliation.
    } on HttpException {
      // Fall through to local abort and status reconciliation.
    } on FormatException {
      // Fall through to local abort and status reconciliation.
    }
    activeRequest?.abort();
    return await reconcileTurn(scope: scope, requestId: requestId);
  }

  Future<void> _markUnknown(PersonScope scope, String requestId) async {
    try {
      await database.setGenerationStatus(
        scope: scope,
        requestId: requestId,
        status: 'unknown',
      );
    } on StateError {
      // A completed/failed/cancelled task must not be downgraded to unknown.
    }
  }

  static String? _errorCode(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic> &&
          decoded['error'] is Map<String, dynamic>) {
        final error = decoded['error'] as Map<String, dynamic>;
        return error['code'] is String ? error['code'] as String : null;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final request in _activeRequests.values) {
      request.abort();
    }
    _activeRequests.clear();
    _client.close(force: true);
  }
}
