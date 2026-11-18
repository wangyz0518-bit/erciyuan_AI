import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../domain/audio_ports.dart';
import '../application/audio_session_controller.dart';

/// Adapted from the existing mobile PoC recorder, without a chat side effect.
final class RecordAudioCapture implements AudioCapturePort {
  AudioRecorder? _recorder;

  AudioRecorder get _instance => _recorder ??= AudioRecorder();

  @override
  Future<bool> hasPermission() => _instance.hasPermission();

  @override
  Future<void> startWav(String filename, {int sampleRate = 16000}) =>
      _instance.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
        path: filename,
      );

  @override
  Future<String?> stop() => _recorder?.stop() ?? Future<String?>.value(null);

  @override
  Future<void> cancel() async {
    final recorder = _recorder;
    if (recorder != null && await recorder.isRecording()) {
      await recorder.cancel();
    }
  }

  @override
  Future<void> dispose() => _recorder?.dispose() ?? Future<void>.value();
}

final class DeviceAudioFilePlayback implements AudioFilePlaybackPort {
  AudioPlayer? _player;

  @override
  Future<void> playFile(String filename) =>
      (_player ??= AudioPlayer()).play(DeviceFileSource(filename));

  @override
  Future<void> stop() => _player?.stop() ?? Future<void>.value();

  @override
  Future<void> dispose() => _player?.dispose() ?? Future<void>.value();
}

/// Audio clips use a distinct dedicated filename, never a message attachment.
/// The app deletes both completed and abandoned files on exit or replacement.
final class LocalAudioTemporaryFiles implements AudioTemporaryFiles {
  @override
  Future<String> allocate() async {
    final temp = await getTemporaryDirectory();
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return path.join(temp.path, 'erciyuan-clip-$micros.wav');
  }

  @override
  Future<void> delete(String filename) async {
    final file = File(filename);
    if (await file.exists()) await file.delete();
  }
}

/// Android native implementation derived from PR #22. iOS intentionally uses
/// file playback until a separate, tested native PCM implementation exists.
final class AndroidPcmPlayback implements AudioPcmPlaybackPort {
  AndroidPcmPlayback({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.erciyuan/pcm');

  final MethodChannel _channel;
  String? _active;
  bool _closed = false;

  void _requireActive(String id) {
    if (_closed || _active != id) {
      throw StateError('Inactive PCM stream');
    }
  }

  @override
  Future<void> start(String streamId, {int bufferMs = 400}) async {
    if (_closed) throw StateError('PCM player was disposed');
    if (!Platform.isAndroid) {
      throw UnsupportedError('PCM streaming is not implemented on iOS');
    }
    if (streamId.isEmpty || bufferMs < 100 || bufferMs > 1000) {
      throw ArgumentError('Invalid PCM stream configuration');
    }
    _active = null;
    await _channel.invokeMethod<void>('stop');
    await _channel.invokeMethod<void>('start', {
      'id': streamId,
      'bufferMs': bufferMs,
    });
    if (_closed) {
      await _channel.invokeMethod<void>('stop');
      return;
    }
    _active = streamId;
  }

  @override
  Future<void> append(String streamId, Uint8List pcm16le) async {
    _requireActive(streamId);
    if (pcm16le.isEmpty || pcm16le.length.isOdd || pcm16le.length > 192000) {
      throw ArgumentError('PCM must be a nonempty even-sized bounded payload');
    }
    await _channel.invokeMethod<void>('append', {
      'id': streamId,
      'bytes': pcm16le,
    });
  }

  @override
  Future<void> end(String streamId) async {
    _requireActive(streamId);
    await _channel.invokeMethod<Object?>('end', {'id': streamId});
    if (_active == streamId) _active = null;
  }

  @override
  Future<void> stop() async {
    _active = null;
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stop');
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    await stop();
  }
}

AudioSessionController createDeviceAudioSession() => AudioSessionController(
  capture: RecordAudioCapture(),
  playback: DeviceAudioFilePlayback(),
  files: LocalAudioTemporaryFiles(),
);
