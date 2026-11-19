import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/conversation_capture.dart';
import '../data/voice_input_stream.dart';

class VoiceInputController extends ChangeNotifier {
  VoiceInputController({
    required this.open,
    required this.submit,
    ConversationCapture? capture,
  }) : capture = capture ?? ConversationCapture();
  final VoiceInputStream Function(void Function(String)) open;
  final Future<void> Function(String) submit;
  final ConversationCapture capture;
  VoiceInputStream? _current;
  bool holding = false, _disposed = false;
  String status = '';
  bool get busy => _current != null;

  void show(String value) {
    if (_disposed) return;
    status = value;
    notifyListeners();
  }

  Future<void> startHold() async {
    if (_disposed || _current != null) return;
    final input = open((text) => show(text));
    _current = input;
    holding = true;
    show('按住说话，松开发送，滑出取消');
    unawaited(_finish(input));
    try {
      await capture.start(
        call: false,
        onFrame: (pcm, _) {
          if (!holding || _current != input) return;
          input.add(pcm);
          if (input.bytes + ConversationCapture.frameBytes > 960000) {
            unawaited(endHold(true));
          }
        },
        onError: (_) => unawaited(cancel()),
      );
    } catch (_) {
      if (_current == input) {
        await cancel();
        show('麦克风不可用，请检查权限');
      }
    }
  }

  Future<void> _finish(VoiceInputStream input) async {
    try {
      final text = await input.result;
      if (_disposed || _current != input) return;
      show('已确认转写');
      await submit(text);
    } catch (_) {
      if (_current == input) show('语音未发送，请重试');
    } finally {
      if (_current == input) {
        _current = null;
        holding = false;
        await capture.stop();
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> endHold(bool send) async {
    if (!holding) return;
    holding = false;
    final input = _current;
    if (!send) {
      await cancel();
      return;
    }
    await capture.stop();
    if (input == null || _current != input) return;
    show('正在确认转写');
    input.commit();
  }

  Future<void> cancel() {
    final current = _current;
    _current = null;
    holding = false;
    current?.cancel();
    show('');
    return capture.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    unawaited(capture.dispose());
    super.dispose();
  }
}
