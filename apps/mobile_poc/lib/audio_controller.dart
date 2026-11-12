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
  bool working = false;
  String status = '录音仅保存在本机；此页不会识别或发送文字。';
  String? recordingPath;
  int recordingBytes = 0;
  double rms = 0;
  int seconds = 0;
  int _epoch = 0;
  Timer? _timer;
  late final StreamSubscription<PlayerState> _subscription;

  AudioController() {
    _subscription = player.onPlayerStateChanged.listen((s) {
      playing = s == PlayerState.playing;
      notifyListeners();
    });
  }

  Future<void> startRecording() async {
    if (working || recording) return;
    working = true;
    final epoch = ++_epoch;
    notifyListeners();
    try {
      await player.stop();
      final allowed = await recorder.hasPermission();
      if (epoch != _epoch) return;
      if (!allowed) {
        status = '麦克风权限未允许，仍可返回聊天页打字。可在系统设置中重新授权。';
        return;
      }
      final dir = await getTemporaryDirectory();
      if (epoch != _epoch) return;
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: '${dir.path}/poc-recording.wav',
      );
      if (epoch != _epoch) {
        await recorder.cancel();
        return;
      }
      recordingPath = null;
      recordingBytes = 0;
      recording = true;
      seconds = 0;
      status = '正在录音，最长 30 秒';
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        seconds++;
        notifyListeners();
        if (seconds >= 30) unawaited(finishRecording());
      });
    } catch (e) {
      if (epoch == _epoch) status = '无法开始录音，请检查麦克风与权限。';
    } finally {
      working = false;
      notifyListeners();
    }
  }

  Future<void> finishRecording() async {
    if (working || !recording) return;
    working = true;
    final epoch = _epoch;
    _timer?.cancel();
    try {
      final p = await recorder.stop();
      recording = false;
      if (epoch != _epoch || p == null) return;
      final bytes = await File(p).readAsBytes();
      if (epoch != _epoch) return;
      recordingPath = p;
      recordingBytes = bytes.length;
      rms = pcmRms(bytes);
      status = rms < 0.001
          ? '录音已保存，但信号接近静音。请检查电脑麦克风和模拟器输入。'
          : '录音已保存，可以回放（未做语音识别）。';
    } catch (_) {
      status = '录音保存失败，请重新录制。';
    } finally {
      working = false;
      recording = false;
      notifyListeners();
    }
  }

  Future<void> stopAll({bool discardRecording = true}) async {
    ++_epoch;
    _timer?.cancel();
    if (recording) {
      if (discardRecording) {
        await recorder.cancel();
      } else {
        await recorder.stop();
      }
      recordingPath = null;
      recordingBytes = 0;
    }
    recording = false;
    await player.stop();
    playing = false;
    status = '已停止。录音取消后不会生成聊天消息。';
    notifyListeners();
  }

  Future<void> play({bool testTone = false}) async {
    if (working || recording) return;
    working = true;
    final epoch = ++_epoch;
    notifyListeners();
    try {
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
      status = testTone ? '正在播放本地测试音（非合成语音）' : '正在回放录音';
    } catch (_) {
      status = '播放失败，请重试。';
    } finally {
      working = false;
      notifyListeners();
    }
  }

  Future<void> close() async {
    await stopAll();
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
