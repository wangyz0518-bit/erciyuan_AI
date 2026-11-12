import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class AudioController extends ChangeNotifier {
  final recorder = AudioRecorder();
  final player = AudioPlayer();
  bool recording = false;
  bool playing = false;
  String status = '按住录音，松开试听；仅临时保存在本机。';
  String? recordingPath;
  String? _temporaryPath;
  int recordingBytes = 0;
  double rms = 0;
  int seconds = 0;
  int _epoch = 0;
  int _pending = 0;
  bool _closed = false;
  bool _permissionDenied = false;
  Timer? _timer;
  Future<void> _tail = Future<void>.value();
  late final StreamSubscription<PlayerState> _subscription;
  bool get working => _pending > 0;

  AudioController() {
    _subscription = player.onPlayerStateChanged.listen((s) {
      playing = s == PlayerState.playing;
      _notify();
    });
    // Remove a temporary clip left by an abrupt process termination.
    unawaited(
      _enqueue(() async {
        final dir = await getTemporaryDirectory();
        _temporaryPath = '${dir.path}/poc-recording.wav';
        await _discard();
      }),
    );
  }
  void _notify() {
    if (!_closed) notifyListeners();
  }

  // Serialize native recorder/player operations. Cancellation invalidates the
  // epoch immediately, including while the Android permission dialog is open.
  Future<void> _enqueue(Future<void> Function() action) {
    if (_closed) return Future<void>.value();
    _pending++;
    _notify();
    final result = _tail.then((_) async {
      try {
        await action();
      } catch (_) {
        status = '音频操作失败，请重试。';
      } finally {
        _pending--;
        _notify();
      }
    });
    _tail = result;
    return result;
  }

  Future<void> _discard() async {
    final file = _temporaryPath ?? recordingPath;
    recordingPath = null;
    recordingBytes = 0;
    rms = 0;
    if (file != null && await File(file).exists()) await File(file).delete();
    _temporaryPath = null;
  }

  Future<void> startRecording() {
    if (working || recording || _closed) return Future<void>.value();
    final epoch = ++_epoch;
    return _enqueue(() async {
      await player.stop();
      await _discard();
      seconds = 0;
      final allowed = await recorder.hasPermission();
      _permissionDenied = !allowed;
      if (epoch != _epoch) return;
      if (!allowed) {
        status = '麦克风权限未允许，仍可切换键盘打字。';
        return;
      }
      final dir = await getTemporaryDirectory();
      if (epoch != _epoch) return;
      _temporaryPath = '${dir.path}/poc-recording.wav';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _temporaryPath!,
      );
      if (epoch != _epoch) {
        await recorder.cancel();
        await _discard();
        return;
      }
      recording = true;
      status = '正在录音，松开试听，滑出取消（最长 30 秒）';
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        seconds++;
        _notify();
        if (seconds >= 30) unawaited(finishRecording());
      });
    });
  }

  Future<void> finishRecording() {
    // A release before startup completes cancels, rather than recording after
    // the user grants permission and has already lifted their finger.
    if (!recording) return working ? stopAll() : Future<void>.value();
    _timer?.cancel();
    final epoch = _epoch;
    return _enqueue(() async {
      if (!recording || epoch != _epoch) return;
      try {
        final p = await recorder.stop();
        recording = false;
        if (epoch != _epoch || p == null) {
          await _discard();
          return;
        }
        final bytes = await File(p).readAsBytes();
        if (epoch != _epoch) {
          await _discard();
          return;
        }
        recordingPath = p;
        recordingBytes = bytes.length;
        rms = pcmRms(bytes);
        status = rms < 0.001 ? '录音接近静音，请检查麦克风输入。' : '录音可试听，尚未发送。';
      } finally {
        recording = false;
      }
    });
  }

  Future<void> stopAll({bool discardRecording = true}) {
    ++_epoch;
    _timer?.cancel();
    return _enqueue(() async {
      if (recording) await recorder.cancel();
      recording = false;
      await player.stop();
      playing = false;
      if (discardRecording) await _discard();
      status = _permissionDenied ? '麦克风权限未允许，仍可切换键盘打字。' : '已停止。录音不会生成聊天消息。';
    });
  }

  Future<void> play({bool testTone = false}) {
    if (working || recording || _closed) return Future<void>.value();
    final epoch = ++_epoch;
    return _enqueue(() async {
      String? file = recordingPath;
      if (testTone) {
        final dir = await getTemporaryDirectory();
        file = '${dir.path}/poc-test-tone.wav';
        await File(file).writeAsBytes(makeTone());
      }
      if (epoch != _epoch) return;
      if (file == null) {
        status = '请先完成一次录音。';
        return;
      }
      await player.play(DeviceFileSource(file));
      if (epoch != _epoch) {
        await player.stop();
        return;
      }
      status = testTone ? '正在播放本地测试音' : '正在试听，尚未发送';
    });
  }

  Future<void> close() async {
    await stopAll();
    _closed = true;
    await _subscription.cancel();
    await recorder.dispose();
    await player.dispose();
    dispose();
  }
}

double pcmRms(Uint8List bytes) {
  if (bytes.length < 44) return 0;
  final data = ByteData.sublistView(bytes);
  int offset = 12;
  while (offset + 8 <= bytes.length) {
    final length = data.getUint32(offset + 4, Endian.little);
    if (String.fromCharCodes(bytes.sublist(offset, offset + 4)) == 'data') {
      final end = math.min(bytes.length, offset + 8 + length);
      double energy = 0;
      int count = 0;
      for (int i = offset + 8; i + 1 < end; i += 2) {
        final sample = data.getInt16(i, Endian.little) / 32768;
        energy += sample * sample;
        count++;
      }
      return count == 0 ? 0 : math.sqrt(energy / count);
    }
    offset += 8 + length + (length % 2);
  }
  return 0;
}

Uint8List makeTone() {
  const sampleRate = 16000;
  const samples = sampleRate * 4;
  final bytes = Uint8List(44 + samples * 2);
  final data = ByteData.sublistView(bytes);
  void label(int offset, String text) =>
      bytes.setRange(offset, offset + text.length, text.codeUnits);
  label(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  label(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (int i = 0; i < samples; i++) {
    final envelope = math.min(1.0, math.min(i / 400, (samples - i) / 400));
    data.setInt16(
      44 + i * 2,
      (math.sin(i * 2 * math.pi * 440 / sampleRate) * 4000 * envelope).round(),
      Endian.little,
    );
  }
  return bytes;
}
