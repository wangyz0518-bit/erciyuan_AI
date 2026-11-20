import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/voice_ports.dart';

/// No chat/database dependency: only the user can explicitly insert a
/// transcript into the editable chat composer and then press Send.
final class VoiceAssistController extends ChangeNotifier {
  VoiceAssistController({required this.recognizer, required this.speaker});

  final OnDeviceAsrPort recognizer;
  final SystemTtsPort speaker;

  String transcript = '';
  String status = '设备端识别需单独授权；识别结果必须编辑确认后发送。';
  bool listening = false;
  bool speaking = false;
  bool _closed = false;
  int _epoch = 0;
  Future<void> _tail = Future<void>.value();

  bool get isClosed => _closed;

  void _emit() {
    if (!_closed) notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _tail.then((_) => task());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> beginRecognition() {
    if (_closed || listening) return Future<void>.value();
    final token = ++_epoch;
    listening = true;
    // Starting ASR invalidates the previous speech callback and stops playback.
    // Reflect that interruption immediately instead of retaining a stale TTS UI.
    speaking = false;
    transcript = '';
    status = '正在请求设备端识别（无离线服务时不启用云端回退）';
    _emit();
    return _enqueue(() async {
      try {
        await speaker.stop();
        if (_closed || token != _epoch) return;
        final available = await recognizer.listen((words, isFinal) {
          if (_closed || token != _epoch) return;
          transcript = words;
          if (isFinal) {
            listening = false;
            status = '识别完成，点击“填入草稿”后检查，再自行发送';
          } else {
            status = '正在识别，尚未发送';
          }
          _emit();
        });
        if (!_closed && token == _epoch && !available) {
          listening = false;
          status = '本设备无法使用离线识别；请使用文字输入。';
          _emit();
        }
      } catch (_) {
        if (!_closed && token == _epoch) {
          listening = false;
          status = '设备端识别失败或未授权；不会自动发送。';
          _emit();
        }
      }
    });
  }

  Future<void> stopRecognition() {
    if (_closed) return Future<void>.value();
    ++_epoch;
    listening = false;
    status = transcript.isEmpty ? '已停止识别' : '识别已停止，草稿待确认';
    _emit();
    return _enqueue(() => recognizer.stop());
  }

  /// The UI consumes this text ONLY when the user presses 'Apply draft'.
  String get editableCandidate => transcript;

  void clearTranscript() {
    if (_closed) return;
    transcript = '';
    _emit();
  }

  Future<void> speak(String text) {
    if (_closed || text.trim().isEmpty) return Future<void>.value();
    final token = ++_epoch;
    speaking = true;
    listening = false;
    status = '系统朗读中（系统语音可能由设备服务提供，不是角色专属音色）';
    _emit();
    return _enqueue(() async {
      try {
        await recognizer.stop();
        await speaker.stop();
        if (_closed || token != _epoch) return;
        await speaker.speak(text, () {
          if (!_closed && token == _epoch) {
            speaking = false;
            status = '系统朗读结束';
            _emit();
          }
        });
      } catch (_) {
        if (!_closed && token == _epoch) {
          speaking = false;
          status = '系统朗读不可用，文字记录不受影响';
          _emit();
        }
      }
    });
  }

  Future<void> stopAll() {
    if (_closed) return Future<void>.value();
    ++_epoch;
    listening = false;
    speaking = false;
    status = '已停止设备端识别与朗读';
    _emit();
    return _enqueue(() async {
      await recognizer.stop();
      await speaker.stop();
    });
  }

  Future<void> close() {
    if (_closed) return _tail;
    ++_epoch;
    _closed = true;
    listening = false;
    speaking = false;
    return _enqueue(() async {
      try {
        await recognizer.stop();
        await speaker.stop();
      } finally {
        await recognizer.dispose();
        await speaker.dispose();
      }
    });
  }
}
