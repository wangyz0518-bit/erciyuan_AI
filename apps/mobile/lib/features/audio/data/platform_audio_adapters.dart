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

/// PCM playback on Android (AudioTrack) and iOS (AVAudioEngine).
/// The native platform callbacks are scoped by stream ID; Flutter also
/// invalidates pending starts before they can publish a stale active stream.
/// This port does not request microphone access or generate chat messages.
final class NativePcmPlayback implements AudioPcmPlaybackPort {
  NativePcmPlayback({MethodChannel? channel, bool? isSupported})
    : _channel = channel ?? const MethodChannel('dev.erciyuan/pcm'),
      _supported = isSupported ?? (Platform.isAndroid || Platform.isIOS);

  final MethodChannel _channel;
  final bool _supported;
  String? _active;
  bool _closed = false;
  bool _starting = false;
  int _epoch = 0;

  void _requireActive(String id) {
    if (_closed || _active != id) {
      throw StateError('Inactive PCM stream');
    }
  }

  @override
  Future<void> start(String streamId, {int bufferMs = 400}) async {
    if (_closed) throw StateError('PCM player was disposed');
    if (!_supported) {
      throw UnsupportedError('Native PCM playback requires Android or iOS');
    }
    if (streamId.isEmpty || bufferMs < 100 || bufferMs > 1000) {
      throw ArgumentError('Invalid PCM stream configuration');
    }
    if (_starting) throw StateError('PCM start already in progress');
    _starting = true;
    final generation = ++_epoch;
    _active = null;
    try {
      await _channel.invokeMethod<void>('stop');
      if (_closed || generation != _epoch) return;
      await _channel.invokeMethod<void>('start', {
        'id': streamId,
        'bufferMs': bufferMs,
      });
      if (_closed || generation != _epoch) {
        // A stop may have happened while a native start was in flight.
        await _channel.invokeMethod<void>('stop');
        return;
      }
      _active = streamId;
    } finally {
      _starting = false;
    }
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
    ++_epoch;
    _active = null;
    if (_supported) await _channel.invokeMethod<void>('stop');
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await stop();
  }
}

/// Legacy name retained for existing clients; iOS is now also supported.
typedef AndroidPcmPlayback = NativePcmPlayback;

AudioSessionController createDeviceAudioSession() => AudioSessionController(
  capture: RecordAudioCapture(),
  playback: DeviceAudioFilePlayback(),
  files: LocalAudioTemporaryFiles(),
);
