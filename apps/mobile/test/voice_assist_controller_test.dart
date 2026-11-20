import 'package:erciyuan_mobile/features/voice/application/voice_assist_controller.dart';
import 'package:erciyuan_mobile/features/voice/domain/voice_ports.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Asr implements OnDeviceAsrPort {
  bool available = true;
  int stops = 0;
  void Function(String, bool)? callback;

  @override
  Future<bool> listen(
    void Function(String words, bool finalResult) onWords,
  ) async {
    callback = onWords;
    return available;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

final class _Tts implements SystemTtsPort {
  final messages = <String>[];
  int stops = 0;
  void Function()? done;

  @override
  Future<void> speak(String text, void Function() onFinished) async {
    messages.add(text);
    done = onFinished;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late _Asr asr;
  late _Tts tts;
  late VoiceAssistController controller;
  setUp(() {
    asr = _Asr();
    tts = _Tts();
    controller = VoiceAssistController(recognizer: asr, speaker: tts);
  });
  tearDown(() async {
    await controller.close();
    controller.dispose();
  });

  test(
    'recognized text stays candidate; no automatic send port exists',
    () async {
      await controller.beginRecognition();
      asr.callback!('请帮我', false);
      asr.callback!('请帮我写一首诗', true);
      expect(controller.listening, isFalse);
      expect(controller.editableCandidate, '请帮我写一首诗');
      expect(controller.status, contains('自行发送'));
      controller.clearTranscript();
      expect(controller.editableCandidate, isEmpty);
    },
  );

  test('late recognition after stop cannot restore stale words', () async {
    await controller.beginRecognition();
    final oldCallback = asr.callback!;
    await controller.stopRecognition();
    oldCallback('旧人物内容', true);
    expect(controller.editableCandidate, isEmpty);
  });

  test('unavailable on-device ASR never uses remote fallback', () async {
    asr.available = false;
    await controller.beginRecognition();
    expect(controller.listening, isFalse);
    expect(controller.status, contains('离线识别'));
    expect(controller.editableCandidate, isEmpty);
  });

  test(
    'speaker is explicit, cancellable and separated from transcript',
    () async {
      await controller.speak('你好');
      expect(tts.messages, ['你好']);
      expect(controller.speaking, isTrue);
      await controller.stopAll();
      expect(controller.speaking, isFalse);
      tts.done?.call();
      expect(controller.speaking, isFalse);
      expect(tts.stops, greaterThan(0));
    },
  );

  test(
    'recognition immediately clears previous TTS state and callback',
    () async {
      await controller.speak('旧角色回复');
      expect(controller.speaking, isTrue);
      final oldTtsCompletion = tts.done!;

      await controller.beginRecognition();
      expect(controller.speaking, isFalse);
      expect(controller.listening, isTrue);
      expect(tts.stops, greaterThan(0));

      oldTtsCompletion();
      expect(controller.speaking, isFalse);
      expect(controller.listening, isTrue);
      asr.callback!('新的识别草稿', true);
      expect(controller.editableCandidate, '新的识别草稿');
      expect(controller.listening, isFalse);
    },
  );

  test('closing discards delayed recognizer callbacks', () async {
    await controller.beginRecognition();
    final callback = asr.callback!;
    await controller.close();
    callback('关闭之后', true);
    expect(controller.editableCandidate, isEmpty);
    expect(controller.isClosed, isTrue);
  });
}
