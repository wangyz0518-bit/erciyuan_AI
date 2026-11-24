import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'audio_controller.dart';
import 'conversation_capture.dart';
import 'conversation_transport.dart';
import 'data.dart';
import 'model_gateway.dart';

class _Segment {
  _Segment(this.kind) : id = ModelGateway.requestId();
  final String id, kind;
  final frames = <Uint8List>[];
  int bytes = 0, sequence = 0, lastSpeech = 0;
  int? endpoint, committed, recognized;
  bool started = false, ended = false;
}

class _Turn {
  _Turn(this.id, this.user, this.reply, this.kind, this.recorded);
  final String id, kind;
  final Message user, reply;
  final bool recorded;
  int? origin, endpoint, committed, recognized, first, output;
}

class _Output {
  _Output(this.id);
  final String id;
  final chunks = Queue<Uint8List>();
  int sequence = 0, offset = 0, pendingBytes = 0, played = 0;
  bool ended = false, pumping = false;
}

class ConversationController extends ChangeNotifier {
  ConversationController(
    ModelGateway gateway,
    this.audio, {
    ConversationCapture? capture,
    this.onTimelineMessage,
  }) : _capture = capture ?? ConversationCapture(),
       transport = ConversationTransport(
         gateway.baseUrl,
         gateway.token,
         accountSession: gateway.accountSession,
       ) {
    _segmenter = SpeechSegmenter(
      onStart: _speechStart,
      onFrame: _callFrame,
      onEnd: _finishCallSegment,
    );
    _events = transport.events.listen(_event);
    audio.onStreamEvent = _audioEvent;
  }
  final AudioController audio;
  final void Function(Message)? onTimelineMessage;
  final ConversationTransport transport;
  final ConversationCapture _capture;
  late final SpeechSegmenter _segmenter;
  late final StreamSubscription<Map<String, Object?>> _events;
  final _clock = Stopwatch()..start();
  final _turns = <String, _Turn>{};
  final _byMessage = <int, _Turn>{};
  final _queued = Queue<_Segment>();
  final _ignored = <String>{};
  final _textSaves = <String, Completer<bool>>{};
  final _sent = <String, int>{};
  _Segment? _captureSegment, _pending;
  _Output? _output;
  Timer? _progress;
  String? _reply;
  Future<void>? _opening;
  int _epoch = 0, _messageId = 0, _outputEpoch = 0;
  String role = 'xing';
  String status = '';
  String subtitle = '';
  bool calling = false, muted = false, holding = false, preparing = false;
  bool _disposed = false;
  bool get busy => _reply != null || _textSaves.isNotEmpty;
  bool get inputBusy => calling || holding || preparing || _pending != null;
  bool get playing => _output != null;
  bool get recording => _captureSegment?.kind == 'hold';
  List<Message> get messages =>
      _turns.values.expand((t) => [t.user, t.reply]).toList();
  bool hasRecording(Message m) =>
      m.author == 'user' && (_byMessage[m.id]?.recorded ?? false);
  int get _now => _clock.elapsedMilliseconds;
  int get recordingSeconds => (_captureSegment?.bytes ?? 0) ~/ 32000;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _status(String value) {
    status = value;
    _notify();
  }

  Future<void> connect(String character) async {
    if (character == role && transport.connected) return;
    final pending = _opening;
    if (pending != null) {
      await pending;
      if (character == role && transport.connected) return;
    }
    final epoch = _epoch;
    role = character;
    final work = () async {
      final history = await transport.open(character);
      if (epoch != _epoch || _disposed) {
        throw const GatewayException('SESSION_SUPERSEDED');
      }
      _turns.clear();
      _byMessage.clear();
      _ignored.clear();
      for (final row in history) {
        _turn(row);
      }
      _notify();
    }();
    _opening = work;
    try {
      await work;
    } finally {
      if (identical(_opening, work)) _opening = null;
    }
  }

  Future<void> load(String character) async {
    if (role != character) {
      await close();
      _turns.clear();
      _byMessage.clear();
      _notify();
    }
    try {
      await connect(character);
      _status(transport.mode == 'live' ? '' : '模拟服务仅支持文字联调。');
    } catch (e) {
      _status(_message(e));
    }
  }

  String _message(Object error) => switch (error) {
    MicPermissionDenied() => '麦克风权限未允许。',
    GatewayException(code: 'SESSION_BUSY') => '请先关闭 Windows 测试页或其他通话，再重试。',
    GatewayException(code: 'SESSION_SUPERSEDED') => '',
    GatewayException(:final code) => '语音服务未完成（$code）。',
    _ => '连接或音频操作失败，请重试。',
  };

  Future<bool> text(
    String value,
    String character, {
    VoidCallback? saved,
  }) async {
    if (inputBusy || value.trim().isEmpty || _textSaves.isNotEmpty) {
      return false;
    }
    final epoch = _epoch;
    final id = ModelGateway.requestId();
    final ack = Completer<bool>();
    _textSaves[id] = ack;
    _notify();
    try {
      await connect(character);
      if (epoch != _epoch) return false;
      interrupt();
      _sent[id] = _now;
      transport.send('chat.send', {
        'request_id': id,
        'text': value.trim(),
        'speak': true,
      });
      final ok = await ack.future.timeout(const Duration(seconds: 12));
      if (ok && epoch == _epoch) saved?.call();
      return ok;
    } catch (e) {
      _status(_message(e));
      return false;
    } finally {
      _textSaves.remove(id);
      _sent.remove(id);
      _notify();
    }
  }

  Future<void> startCall(String character) =>
      _startCapture(character, call: true);
  Future<void> startHold(String character) =>
      _startCapture(character, call: false);

  Future<void> _startCapture(String character, {required bool call}) async {
    if (inputBusy || _textSaves.isNotEmpty) return;
    final epoch = _epoch;
    preparing = true;
    if (!call) holding = true;
    _status('准备麦克风…');
    try {
      await connect(character);
      if (epoch != _epoch || (!call && !holding)) return;
      if (transport.mode != 'live') {
        throw const GatewayException('ASR_LIVE_REQUIRED');
      }
      interrupt();
      await audio.stopAll();
      if (epoch != _epoch || (!call && !holding)) return;
      subtitle = '';
      if (call) {
        _segmenter.reset();
      } else {
        _captureSegment = _Segment('hold');
        _queued.add(_captureSegment!);
      }
      await _startMicrophone(call);
      if (epoch != _epoch || (!call && !holding)) return;
      if (call) {
        calling = true;
        muted = false;
      }
      _status(call ? '正在聆听' : '录音中，松开发送');
    } catch (e) {
      if (epoch == _epoch) {
        await close();
        _status(_message(e));
      }
    } finally {
      if (epoch == _epoch) {
        preparing = false;
        _notify();
      }
    }
  }

  Future<void> _startMicrophone(bool call) => _capture.start(
    call: call,
    onFrame: (frame, score) {
      if (call) {
        if (calling && !muted) _segmenter.add(frame, score);
      } else if (holding && _captureSegment != null) {
        _append(_captureSegment!, frame);
        if ((_captureSegment?.bytes ?? 0) >=
            960000 - ConversationCapture.frameBytes) {
          unawaited(finishHold(true));
        }
      }
    },
    onError: (_) {
      unawaited(_lose('麦克风已停止，请重试。'));
    },
  );

  void _speechStart(List<Uint8List> frames) {
    interrupt();
    if (_queued.length >= 5) {
      _status('等待识别的语音过多，请稍后再说。');
      return;
    }
    _captureSegment = _Segment('call')..lastSpeech = _now;
    _queued.add(_captureSegment!);
    for (final frame in frames) {
      _append(_captureSegment!, frame, drain: false);
    }
    _drain();
    _status('在听，请继续…');
  }

  void _callFrame(Uint8List frame, double score) {
    if (_captureSegment == null) return;
    if (_captureSegment!.bytes + frame.length > 960000) {
      _finishCallSegment();
      _speechStart([]);
    }
    final segment = _captureSegment;
    if (segment == null) return;
    if (score >= .35) segment.lastSpeech = _now;
    _append(segment, frame);
  }

  void _finishCallSegment() {
    final segment = _captureSegment;
    _captureSegment = null;
    if (segment != null) _endSegment(segment);
  }

  void _append(_Segment segment, Uint8List frame, {bool drain = true}) {
    final previousSeconds = recordingSeconds;
    segment.frames.add(frame);
    segment.bytes += frame.length;
    if (drain) _drain();
    if (segment.kind == 'hold' && recordingSeconds != previousSeconds) {
      _notify();
    }
  }

  void _endSegment(_Segment segment) {
    segment.endpoint = _now;
    if (segment.bytes < 6400) {
      _discard(segment);
      _status('录音太短，请再说一次。');
      _drain();
      return;
    }
    segment.ended = true;
    _drain();
  }

  void _discard(_Segment segment) {
    _queued.remove(segment);
    if (identical(segment, _captureSegment)) _captureSegment = null;
    if (identical(segment, _pending)) _pending = null;
    if (segment.started) {
      _ignored.add(segment.id);
      _try('input.abort', {'input_id': segment.id});
    }
  }

  Future<void> finishHold(bool send) async {
    if (!holding) return;
    holding = false;
    final segment = _captureSegment;
    _captureSegment = null;
    final epoch = _epoch;
    await _capture.stop();
    if (epoch != _epoch) return;
    if (segment == null || !send) {
      if (segment != null) _discard(segment);
      _status(send ? '录音尚未开始，请再按住说话。' : '录音已取消。');
    } else {
      segment.lastSpeech = _now;
      _endSegment(segment);
    }
  }

  void _drain() {
    if (_queued.isEmpty || _pending != null) return;
    final segment = _queued.first;
    try {
      if (!segment.started) {
        transport.send('input.start', {
          'input_id': segment.id,
          'kind': segment.kind,
        });
        segment.started = true;
      }
      for (final pcm in segment.frames) {
        transport.samples(segment.id, segment.sequence++, pcm);
      }
      segment.frames.clear();
      if (segment.ended) {
        _queued.removeFirst();
        _pending = segment;
        segment.committed = _now;
        transport.send('input.commit', {'input_id': segment.id});
        _status('正在确认你说的话…');
      }
    } catch (_) {
      unawaited(_lose('语音连接中断。'));
    }
  }

  Future<void> toggleMute() async {
    if (!calling || preparing) return;
    muted = !muted;
    final epoch = _epoch;
    preparing = true;
    try {
      if (muted) {
        // Preserve an already submitted phrase. Cancel captured but unsent audio.
        final current = _captureSegment;
        _captureSegment = null;
        if (current != null) _discard(current);
        _segmenter.reset();
        await _capture.stop();
      } else {
        await _startMicrophone(true);
      }
      if (epoch == _epoch) _status(muted ? '麦克风已静音' : '正在聆听');
    } catch (e) {
      if (epoch == _epoch) await _lose(_message(e));
    } finally {
      if (epoch == _epoch) {
        preparing = false;
        _notify();
      }
    }
  }

  void _try(String command, Map<String, Object?> fields) {
    if (!transport.connected) return;
    try {
      transport.send(command, fields);
    } catch (_) {
      /* Closing transport. */
    }
  }

  void interrupt() {
    final id = _reply;
    final output = _output;
    _invalidateOutput();
    if (id == null) return;
    _reply = null;
    _ignored.add(id);
    if (output != null && output.played > 0) {
      _try('playback.progress', {'reply_id': id, 'frames': output.played});
    }
    _try('turn.interrupt', {'reply_id': id});
    final turn = _turns[id];
    if (turn?.reply.status == 'pending') turn!.reply.status = 'interrupted';
    _notify();
  }

  void _invalidateOutput() {
    ++_outputEpoch;
    _output = null;
    _progress?.cancel();
    _progress = null;
    if (audio.pcm.active != null) unawaited(audio.pcm.stop());
  }

  Future<void> _lose(String reason) async {
    try {
      await close();
    } finally {
      _status(reason);
    }
  }

  Future<void> close() async {
    ++_epoch;
    final capture = _capture.stop();
    interrupt();
    _segmenter.reset();
    _pending = null;
    _captureSegment = null;
    _queued.clear();
    holding = calling = preparing = muted = false;
    _sent.clear();
    for (final ack in _textSaves.values) {
      if (!ack.isCompleted) ack.complete(false);
    }
    _textSaves.clear();
    subtitle = '';
    _notify();
    await Future.wait([capture, transport.close()]);
  }

  void _event(Map<String, Object?> event) {
    if (_disposed) return;
    try {
      _receive(event);
    } catch (_) {
      unawaited(_lose('语音数据异常，已停止通话。'));
    }
  }

  void _receive(Map<String, Object?> event) {
    final id = event['reply_id'] as String?;
    final input = event['input_id'] as String?;
    if (_ignored.contains(id) || _ignored.contains(input)) return;
    switch (event['event']) {
      case 'connection.lost':
        unawaited(_lose('语音连接已断开。'));
      case 'transcript.partial':
      case 'transcript.final':
        if (input == _pending?.id || input == _queued.firstOrNull?.id) {
          subtitle = event['text'] as String;
          if (event['event'] == 'transcript.final') _pending?.recognized = _now;
          _notify();
        }
      case 'turn.saved':
        final row = Map<String, Object?>.from(event['turn'] as Map);
        final turn = _turn(row);
        if (_ignored.contains(turn.id)) return;
        final segment = _pending;
        if (segment != null && segment.id == turn.id) {
          turn.origin = segment.lastSpeech;
          turn.endpoint = segment.endpoint;
          turn.committed = segment.committed;
          turn.recognized = segment.recognized;
          _pending = null;
        } else {
          turn.origin = _sent[turn.id];
        }
        _reply = turn.id;
        final ack = _textSaves[turn.id];
        if (ack != null && !ack.isCompleted) ack.complete(true);
        _status('正在想…');
        if (_queued.isNotEmpty) interrupt();
        _drain();
      case 'reply.delta':
        if (id != _reply) return;
        final turn = _turns[id]!;
        turn.first ??= _now;
        turn.reply.text += event['delta'] as String;
        _notify();
      case 'reply.saved':
        if (id != _reply) return;
        final turn = _turns[id]!;
        turn.reply.text = event['text'] as String;
        turn.reply.status = 'complete';
        onTimelineMessage?.call(turn.reply);
        _notify();
      case 'audio.started':
        if (id == null || id != _reply) return;
        if (event['format'] != 'pcm_s16le' ||
            event['sample_rate'] != 24000 ||
            event['channels'] != 1) {
          throw const FormatException();
        }
        final output = _Output(id);
        _output = output;
        unawaited(_startOutput(output));
      case 'audio.chunk':
        final output = _output;
        if (output == null || output.id != id) return;
        if (event['seq'] != output.sequence ||
            event['offset'] != output.offset) {
          throw const FormatException();
        }
        final pcm = event['pcm'] as Uint8List;
        output.sequence++;
        output.offset += pcm.length;
        output.pendingBytes += pcm.length;
        if (output.pendingBytes > 60 * 48000) throw const FormatException();
        output.chunks.add(pcm);
        unawaited(_pump(output));
      case 'audio.completed':
        final output = _output;
        if (output == null || output.id != id) return;
        if (event['chunks'] != output.sequence ||
            (event['total_frames'] as int) * 2 != output.offset) {
          throw const FormatException();
        }
        output.ended = true;
        unawaited(_pump(output));
      case 'turn.completed':
        if (id != _reply) return;
        _reply = null;
        _status(calling ? '正在聆听' : '');
      case 'turn.failed':
        if (id != _reply) return;
        _invalidateOutput();
        _reply = null;
        if (_turns[id]?.reply.status == 'pending') {
          _turns[id]!.reply.status = 'failed';
          onTimelineMessage?.call(_turns[id]!.reply);
        }
        _status('本轮未完成（${event['code']}）。');
      case 'input.failed':
      case 'request.failed':
        _failRequest(event, input);
    }
  }

  void _failRequest(Map<String, Object?> event, String? input) {
    final failed = <_Segment>[
      ?_pending,
      ..._queued,
    ].where((segment) => segment.id == input).firstOrNull;
    if (failed != null) _discard(failed);
    final request = event['request_id'];
    final ack = _textSaves[request];
    if (ack != null && !ack.isCompleted) ack.complete(false);
    _status('请求未完成（${event['code']}）。');
    _drain();
  }

  _Turn _turn(Map<String, Object?> row) {
    final id = row['id'] as String;
    final created = (row['created'] as num?)?.toDouble();
    final timestamp = created == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (created * 1000).round(),
            isUtc: true,
          );
    final user = Message(
      eventId: 'v3-user-$id',
      turnId: id,
      occurredAt: timestamp,
      id: ++_messageId,
      characterId: role,
      author: 'user',
      text: row['prompt'] as String,
      status: 'complete',
    );
    final answer = Message(
      eventId: 'v3-assistant-$id',
      turnId: id,
      occurredAt: timestamp,
      id: ++_messageId,
      characterId: role,
      author: 'assistant',
      text: row['reply'] as String? ?? '',
      replyTo: user.id,
      status: row['state'] == 'running' ? 'pending' : row['state'] as String,
    );
    final turn = _Turn(
      id,
      user,
      answer,
      row['kind'] as String,
      row['has_recording'] == true,
    );
    _turns[id] = turn;
    _byMessage[user.id] = _byMessage[answer.id] = turn;
    onTimelineMessage?.call(user);
    if (answer.status != 'pending') onTimelineMessage?.call(answer);
    return turn;
  }

  Future<void> _startOutput(_Output output) async {
    output.pumping = true;
    try {
      await audio.pcm.start(
        output.id,
        bufferMs: 180,
        communication: calling && !muted,
      );
      if (_output != output) return;
      _progress = Timer.periodic(const Duration(milliseconds: 200), (_) {
        unawaited(_reportProgress(output));
      });
    } catch (_) {
      if (_output == output) {
        interrupt();
        _status('无法播放角色声音。');
      }
    } finally {
      output.pumping = false;
    }
    if (_output == output) await _pump(output);
  }

  Future<void> _reportProgress(_Output output) async {
    if (_output != output) return;
    try {
      final frames = await audio.pcm.progress(output.id);
      if (_output == output &&
          frames > output.played &&
          frames <= output.offset ~/ 2) {
        output.played = frames;
        _try('playback.progress', {'reply_id': output.id, 'frames': frames});
      }
    } catch (_) {
      /* Device stopped or player changed. */
    }
  }

  Future<void> _pump(_Output output) async {
    if (output.pumping || _output != output) return;
    output.pumping = true;
    try {
      while (_output == output && output.chunks.isNotEmpty) {
        final chunk = output.chunks.removeFirst();
        await audio.pcm.append(output.id, chunk);
        output.pendingBytes -= chunk.length;
      }
      if (_output != output || !output.ended) return;
      final metrics = await audio.pcm.end(output.id);
      if (_output != output) return;
      if (metrics['frames'] != output.offset ~/ 2) {
        throw const FormatException();
      }
      _try('playback.progress', {
        'reply_id': output.id,
        'frames': metrics['frames'],
        'complete': true,
      });
      _invalidateOutput();
      _notify();
    } catch (_) {
      if (_output == output) {
        interrupt();
        _status('语音播放失败。');
      }
    } finally {
      output.pumping = false;
    }
  }

  void _audioEvent(Map<String, Object?> event) {
    if (event['event'] == 'firstOutput' && event['id'] == _reply) {
      _turns[_reply]?.output = _now;
      _status(calling ? '正在说话，可以插话' : '正在朗读');
    }
  }

  String? latency(Message message) {
    final turn = _byMessage[message.id];
    if (message.author != 'assistant' || turn == null || turn.origin == null) {
      return null;
    }
    String seconds(int? end, int? start) => end == null || start == null
        ? ''
        : ' ${((end - start) / 1000).toStringAsFixed(2)} 秒';
    if (turn.first == null) return null;
    final parts = [
      turn.output == null
          ? '到首字${seconds(turn.first, turn.origin)}'
          : '到开播${seconds(turn.output, turn.origin)}',
      if (turn.kind == 'call') '断句${seconds(turn.endpoint, turn.origin)}',
      if (turn.recognized != null)
        '转写${seconds(turn.recognized, turn.committed)}',
      '首字${seconds(turn.first, turn.recognized ?? turn.origin)}',
    ];
    return parts.join(' · ');
  }

  Future<void> replay(Message message) async {
    if (inputBusy || !hasRecording(message)) return;
    final id = _byMessage[message.id]!.id;
    interrupt();
    final epoch = ++_outputEpoch;
    try {
      await audio.stopAll();
      final bytes = await transport.recording(id);
      if (epoch != _outputEpoch || inputBusy || _disposed) return;
      await audio.playGenerated(bytes, expectedEpoch: audio.operationEpoch);
    } catch (e) {
      _status(_message(e));
    }
  }

  Future<void> chooseVoice(String? id, int revision) async {
    if (inputBusy || busy) throw const GatewayException('VOICE_BUSY');
    final character = role;
    await close();
    await transport.bind(character, id, revision);
    await connect(character);
    _status('');
  }

  Future<void> shutdown() async {
    audio.onStreamEvent = null;
    _disposed = true;
    try {
      await close();
    } finally {
      await _events.cancel();
      await _capture.dispose();
      await transport.dispose();
      dispose();
    }
  }
}
