import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/conversation_capture.dart';
import '../data/voice_input_stream.dart';

/// Detect speech locally; transcribe overlapping utterances but submit finals
/// in capture order so a slower first utterance cannot disappear.
class ContinuousCallController extends ChangeNotifier {
  ContinuousCallController({
    required this.open,
    required this.submit,
    required this.interrupt,
    ConversationCapture? capture,
  }) : capture = capture ?? ConversationCapture();
  final VoiceInputStream Function(void Function(String)) open;
  final Future<void> Function(String) submit;
  final void Function() interrupt;
  final ConversationCapture capture;
  late final _detector = SpeechSegmenter(
    onStart: _beginSegment,
    onFrame: _frame,
    onEnd: _commit,
  );
  final _pending = <VoiceInputStream>{};
  Future<void> _delivery = Future.value();
  VoiceInputStream? _segment;
  Timer? _clock;
  final Stopwatch _elapsed = Stopwatch();
  int _epoch = 0;
  bool calling = false, muted = false, _disposed = false;
  String status = '', subtitle = '';
  int get seconds => _elapsed.elapsed.inSeconds;
  bool get hasUnsentSpeech => _pending.isNotEmpty || _segment != null;

  void _update(String value) {
    status = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (calling || _disposed) return;
    ++_epoch;
    calling = true;
    muted = false;
    subtitle = '';
    _elapsed
      ..reset()
      ..start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _update(status));
    _update('准备麦克风');
    await _listen();
  }

  Future<void> _listen() async {
    final epoch = _epoch;
    try {
      await capture.start(
        call: true,
        onFrame: (pcm, score) {
          if (epoch == _epoch && calling && !muted) _detector.add(pcm, score);
        },
        onError: (_) {
          if (epoch == _epoch) unawaited(stop('麦克风已断开'));
        },
      );
      if (epoch == _epoch && !muted) _update('正在聆听');
    } catch (_) {
      if (epoch == _epoch) await stop('无法启动通话，请检查麦克风权限和语音检测组件');
    }
  }

  void _beginSegment(List<Uint8List> frames) {
    interrupt();
    if (_pending.length >= 4) {
      _update('仍在处理前面的语音，请稍后再说');
      return;
    }
    final epoch = _epoch;
    late final VoiceInputStream item;
    item = open((text) {
      if (epoch == _epoch && (_segment == item || _segment == null)) {
        subtitle = text;
        _update(status);
      }
    });
    _segment = item;
    _pending.add(item);
    for (final pcm in frames) {
      item.add(pcm);
    }
    _update('在听，请继续');
    _delivery = _delivery.then((_) async {
      try {
        final text = await item.result;
        if (epoch != _epoch || !_pending.remove(item)) return;
        subtitle = text;
        _update('正在回应');
        await submit(text);
      } catch (_) {
        if (epoch == _epoch && _pending.remove(item)) _update('本段识别失败，可以继续说话');
      } finally {
        if (epoch == _epoch && _segment == item) _segment = null;
      }
    });
  }

  void _frame(Uint8List pcm, double score) {
    final item = _segment;
    if (item == null) return;
    if (item.bytes + pcm.length > 960000) {
      _commit();
      _beginSegment([pcm]);
    } else {
      item.add(pcm);
    }
  }

  void _commit() {
    final item = _segment;
    _segment = null;
    item?.commit();
    if (item != null) _update('正在确认转写');
  }

  Future<void> toggleMute() async {
    if (!calling) return;
    muted = !muted;
    _detector.reset();
    if (muted) {
      final unfinished = _segment;
      _segment = null;
      _pending.remove(unfinished);
      unfinished?.cancel();
      _update('麦克风已静音');
      await capture.stop();
    } else {
      await _listen();
    }
  }

  Future<void> stop([String message = '']) {
    if (!calling) return Future.value();
    ++_epoch;
    calling = false;
    muted = false;
    _clock?.cancel();
    _elapsed.stop();
    _detector.reset();
    for (final input in _pending) {
      input.cancel();
    }
    _pending.clear();
    _segment = null;
    _delivery = Future.value();
    subtitle = '';
    interrupt();
    _update(message);
    return capture.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    unawaited(capture.dispose());
    super.dispose();
  }
}
