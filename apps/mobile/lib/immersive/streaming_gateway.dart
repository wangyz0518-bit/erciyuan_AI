import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'model_gateway.dart' show GatewayException;

class StreamingTurn {
  StreamingTurn(this.id, this.character, {Stopwatch? started})
    : clock = started ?? (Stopwatch()..start());
  final String id, character;
  final text = StreamController<String>();
  StreamController<Map<String, Object?>> audio = StreamController();
  final Stopwatch clock;
  String received = '', speechId = '';
  bool completed = false, textClosed = false, audioClosed = false;
  int bytes = 0, sequence = 0;
  double? completedAtMs;
  final metrics = <String, Object?>{};
  void audioEvent(Map<String, Object?> event) {
    if (!audioClosed) audio.add(event);
  }

  void endAudio() {
    if (!audioClosed) {
      audioClosed = true;
      unawaited(audio.close());
    }
  }

  void failText(String code) {
    if (!textClosed) {
      textClosed = true;
      text.addError(GatewayException(code));
      unawaited(text.close());
    }
  }
}

/// Persistent, role-scoped channel. It never reconnects by resubmitting a paid task.
class StreamingGateway {
  StreamingGateway(this.baseUrl, this.token);
  final String baseUrl, token;
  WebSocket? _socket;
  String? _role;
  Future<void>? _connecting;
  final turns = <String, StreamingTurn>{};
  final _status = <String, Completer<Map<String, Object?>>>{};

  Future<void> connect(String character) async {
    if (_socket != null &&
        _role == character &&
        _socket!.readyState == WebSocket.open) {
      return;
    }
    if (_connecting != null) {
      await _connecting;
      return connect(character);
    }
    final ready = Completer<void>();
    _connecting = ready.future;
    try {
      final old = _socket;
      final oldRole = _role;
      _socket = null;
      _role = null;
      if (oldRole != null) _lost(oldRole);
      if (old != null) await old.close();
      final base = Uri.parse(baseUrl);
      final url = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/v2/conversations/local-$character/stream',
      );
      final socket = await WebSocket.connect(
        url.toString(),
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      ).timeout(const Duration(seconds: 12));
      _socket = socket;
      _role = character;
      socket.pingInterval = const Duration(seconds: 20);
      socket.listen(
        (data) {
          if (!identical(_socket, socket)) return;
          try {
            _receive(data);
          } catch (_) {
            unawaited(socket.close());
            _lost(character);
          }
        },
        onError: (Object _) {
          if (identical(_socket, socket)) _lost(character);
        },
        onDone: () {
          if (identical(_socket, socket)) {
            _socket = null;
            _role = null;
            _lost(character);
          }
        },
      );
      ready.complete();
    } catch (error) {
      ready.completeError(error);
      // Await the completer below so callers observe exactly one error.
    } finally {
      _connecting = null;
    }
    await ready.future;
  }

  void _lost(String character) {
    for (final turn in turns.values.where((t) => t.character == character)) {
      turn.failText('CONNECTION_LOST');
      turn.audioEvent({'event': 'audio.failed', 'code': 'CONNECTION_LOST'});
      turn.endAudio();
    }
    for (final pending in _status.values) {
      if (!pending.isCompleted) {
        pending.completeError(const GatewayException('CONNECTION_LOST'));
      }
    }
    _status.clear();
  }

  void _send(Map<String, Object?> packet) {
    if (_socket == null || _socket!.readyState != WebSocket.open) {
      throw const GatewayException('CONNECTION_LOST');
    }
    _socket!.add(jsonEncode(packet));
  }

  Stream<String> reply({
    required String requestId,
    required String character,
    required String content,
    required List<Map<String, String>> history,
    required bool voice,
    Stopwatch? clock,
  }) async* {
    await connect(character);
    turns.removeWhere((_, t) => t.textClosed && t.audioClosed);
    if (turns.length >= 8) {
      throw const GatewayException('LOCAL_CAPACITY_REACHED');
    }
    final turn = StreamingTurn(requestId, character, started: clock);
    turns[requestId] = turn;
    _send({
      'command': 'chat.send',
      'request_id': requestId,
      'character_id': character,
      'content': content,
      'history': history,
      'speech': {'enabled': voice},
    });
    try {
      yield* turn.text.stream.timeout(const Duration(seconds: 100));
    } catch (_) {
      cancel(requestId, wholeTurn: true);
      rethrow;
    }
  }

  void _receive(dynamic value) {
    Map<String, Object?> packet;
    Uint8List? pcm;
    if (value is List<int>) {
      final bytes = Uint8List.fromList(value);
      if (bytes.length < 4) throw const FormatException();
      final size = ByteData.sublistView(bytes).getUint32(0, Endian.big);
      if (size > 4096 || bytes.length <= 4 + size) {
        throw const FormatException();
      }
      packet = Map<String, Object?>.from(
        jsonDecode(utf8.decode(bytes.sublist(4, 4 + size))) as Map,
      );
      pcm = bytes.sublist(4 + size);
      if (pcm.length.isOdd || pcm.length > 192000) {
        throw const FormatException();
      }
    } else {
      packet = Map<String, Object?>.from(jsonDecode(value as String) as Map);
    }
    final id = packet['request_id'] as String? ?? '';
    if (packet['event'] == 'request.failed') {
      final pending = _status.remove(id);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(
          GatewayException(packet['code'] as String? ?? 'INVALID_REQUEST'),
        );
        return;
      }
    }
    if (packet['event'] == 'turn.status') {
      final pending = _status.remove(id);
      if (pending != null && !pending.isCompleted) pending.complete(packet);
      return;
    }
    final turn = turns[id];
    if (turn == null || packet['character_id'] != turn.character) return;
    switch (packet['event']) {
      case 'message.delta':
        if (!turn.textClosed) {
          final delta = packet['delta'] as String;
          turn.received += delta;
          turn.text.add(delta);
        }
      case 'message.completed':
        if (turn.textClosed) return;
        final full = packet['content'] as String;
        if (full.isEmpty || full != turn.received) {
          turn.failText('INCOMPLETE_REPLY');
          cancel(id, wholeTurn: true);
          return;
        }
        turn.completed = true;
        turn.textClosed = true;
        turn.completedAtMs = turn.clock.elapsedMicroseconds / 1000;
        turn.speechId = packet['speech_id'] as String? ?? '';
        unawaited(turn.text.close());
        if (turn.speechId.isEmpty) turn.endAudio();
      case 'message.failed':
      case 'message.cancelled':
      case 'request.failed':
        final code = packet['code'] as String? ?? 'MODEL_UNAVAILABLE';
        turn.failText(code);
        turn.audioEvent({'event': 'audio.failed', 'code': code});
        turn.endAudio();
      case 'audio.started':
        if (packet['speech_id'] != turn.speechId || turn.audioClosed) return;
        if (packet['format'] != 'pcm_s16le' ||
            packet['sample_rate'] != 24000 ||
            packet['channels'] != 1) {
          cancel(id);
          return;
        }
        turn.metrics.addAll(packet);
        turn.audioEvent(packet);
      case 'audio.chunk':
        if (packet['speech_id'] != turn.speechId || turn.audioClosed) return;
        if (pcm == null ||
            packet['seq'] != turn.sequence ||
            packet['offset'] != turn.bytes) {
          turn.audioEvent({
            'event': 'audio.failed',
            'code': 'AUDIO_SEQUENCE_ERROR',
          });
          cancel(id);
          return;
        }
        turn.sequence++;
        turn.bytes += pcm.length;
        if (turn.bytes > 12 * 1024 * 1024) {
          cancel(id);
          return;
        }
        turn.metrics.putIfAbsent(
          'firstChunkAtMs',
          () => turn.clock.elapsedMicroseconds / 1000,
        );
        turn.audioEvent({...packet, 'pcm': pcm});
      case 'audio.completed':
        if (packet['speech_id'] != turn.speechId || turn.audioClosed) return;
        if (turn.bytes == 0 ||
            packet['bytes'] != turn.bytes ||
            packet['chunks'] != turn.sequence) {
          turn.audioEvent({
            'event': 'audio.failed',
            'code': 'AUDIO_INCOMPLETE',
          });
        } else {
          turn.metrics.addAll(packet);
          turn.audioEvent(packet);
        }
        turn.endAudio();
      case 'audio.failed':
      case 'audio.cancelled':
        if (packet['speech_id'] == turn.speechId) {
          turn.audioEvent(packet);
          turn.endAudio();
        }
    }
  }

  void cancel(String id, {bool wholeTurn = false}) {
    final turn = turns[id];
    if (turn == null) return;
    turn.audioEvent({'event': 'audio.cancelled'});
    turn.endAudio();
    if (wholeTurn) turn.failText('CANCELLED');
    try {
      _send({
        'command': wholeTurn ? 'turn.cancel' : 'speech.cancel',
        'request_id': id,
      });
    } catch (_) {}
  }

  Future<StreamingTurn> retry(String id, String speechId) async {
    final turn = turns[id];
    if (turn == null || !turn.completed) {
      throw const GatewayException('REQUEST_NOT_FOUND');
    }
    await connect(turn.character);
    turn.endAudio();
    turn.audio = StreamController();
    turn.audioClosed = false;
    turn.speechId = speechId;
    turn.bytes = 0;
    turn.sequence = 0;
    turn.metrics.clear();
    _send({'command': 'speech.retry', 'request_id': id, 'speech_id': speechId});
    return turn;
  }

  Future<Map<String, Object?>> status(String id, String character) async {
    await connect(character);
    final pending = _status[id] = Completer();
    _send({'command': 'turn.status', 'request_id': id});
    try {
      return await pending.future.timeout(const Duration(seconds: 10));
    } finally {
      _status.remove(id);
    }
  }

  Future<void> close() async {
    final socket = _socket;
    final role = _role;
    _socket = null;
    _role = null;
    if (role != null) _lost(role);
    if (socket != null) await socket.close();
  }
}
