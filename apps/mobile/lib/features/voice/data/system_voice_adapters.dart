import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../application/voice_assist_controller.dart';
import '../domain/voice_ports.dart';

final class DeviceOnDeviceAsr implements OnDeviceAsrPort {
  final stt.SpeechToText _recognizer = stt.SpeechToText();
  bool _initialized = false;
  int _epoch = 0;

  @override
  Future<bool> listen(
    void Function(String words, bool finalResult) onWords,
  ) async {
    final generation = ++_epoch;
    if (!_initialized) {
      final ready = await _recognizer.initialize();
      if (!ready) return false;
      _initialized = true;
    }
    if (generation != _epoch) return false;
    await _recognizer.listen(
      onResult: (result) {
        if (generation == _epoch) {
          onWords(result.recognizedWords, result.finalResult);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: 'zh_CN',
        onDevice: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
    return generation == _epoch;
  }

  @override
  Future<void> stop() async {
    ++_epoch;
    await _recognizer.cancel();
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}

final class DeviceSystemTts implements SystemTtsPort {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> speak(String text, void Function() onFinished) async {
    _tts.setCompletionHandler(onFinished);
    _tts.setCancelHandler(onFinished);
    _tts.setErrorHandler((_) => onFinished());
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<void> dispose() => stop();
}

VoiceAssistController createDeviceVoiceAssist() => VoiceAssistController(
  recognizer: DeviceOnDeviceAsr(),
  speaker: DeviceSystemTts(),
);
