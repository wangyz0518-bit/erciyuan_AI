import 'dart:async';
import 'dart:typed_data';

import 'package:erciyuan_mobile/features/voice/application/continuous_call_controller.dart';
import 'package:erciyuan_mobile/features/voice/data/voice_input_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import 'voice_input_controller_test.dart' show FakeConversationCapture;

class _Utterance implements VoiceInputStream {
  final finalText = Completer<String>();
  bool committed = false, cancelled = false;
  @override
  int bytes = 0;
  @override
  Future<String> get result => finalText.future;
  @override
  void add(Uint8List pcm) => bytes += pcm.length;
  @override
  void commit() {
    committed = true;
  }

  @override
  void cancel() {
    cancelled = true;
    if (!finalText.isCompleted) finalText.complete('迟到');
  }

  @override
  Uri get uri => Uri();
  @override
  String get token => '';
  @override
  void Function(String) get onPartial => (_) {};
}

void main() {
  test(
    'two-second pause, out-of-order ASR, barge-in, mute and teardown',
    () async {
      final capture = FakeConversationCapture(),
          utterances = <_Utterance>[],
          sent = <String>[];
      var interrupts = 0;
      final call = ContinuousCallController(
        capture: capture,
        open: (_) {
          final input = _Utterance();
          utterances.add(input);
          return input;
        },
        submit: (s) async => sent.add(s),
        interrupt: () => interrupts++,
      );
      addTearDown(call.dispose);
      await call.start();
      void frames(int count, double score) {
        for (var i = 0; i < count; i++) {
          capture.feed!(Uint8List(1024), score);
        }
      }

      frames(8, .95);
      frames(62, 0);
      expect(utterances.single.committed, isFalse);
      frames(8, .95);
      frames(80, 0);
      expect(utterances.single.committed, isTrue);
      frames(8, .95);
      frames(80, 0);
      expect(interrupts, 2);
      utterances.last.finalText.complete('第二句');
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);
      utterances.first.finalText.complete('第一句');
      await Future<void>.delayed(Duration.zero);
      expect(sent, ['第一句', '第二句']);
      frames(8, .95);
      await call.toggleMute();
      expect(utterances.last.cancelled, isTrue);
      expect(capture.feed, isNull);
      await call.toggleMute();
      frames(8, .95);
      await call.stop();
      expect(capture.feed, isNull);
      expect(utterances.last.cancelled, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(sent, ['第一句', '第二句']);
    },
  );
}
