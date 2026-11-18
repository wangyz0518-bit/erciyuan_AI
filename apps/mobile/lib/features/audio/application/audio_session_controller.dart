import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/audio_ports.dart';

/// Temporary files are private to the audio layer and never enter SQLite.
abstract interface class AudioTemporaryFiles {
  Future<String> allocate();
  Future<void> delete(String filename);
}

/// A page-scoped audio controller. The operation queue prevents an async
/// permission result or native start from resurrecting audio after cancellation.
final class AudioSessionController extends ChangeNotifier {
  AudioSessionController({
    required this.capture,
    required this.playback,
    required this.files,
  });

  final AudioCapturePort capture;
  final AudioFilePlaybackPort playback;
  final AudioTemporaryFiles files;

  AudioSessionState state = AudioSessionState.idle;
  String status = '按住麦克风录音；仅本机试听，不识别、不发送。';
  String? recordedPath;
  String? _pendingPath;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  int _epoch = 0;

  bool get canRecord => !_closed &&
      state != AudioSessionState.requestingPermission &&
      state != AudioSessionState.recording;
  bool get hasClip => recordedPath != null && !_closed;
  bool _current(int generation) => !_closed && generation == _epoch;

  void _show(AudioSessionState next, String description) {
    if (_closed) return;
    state = next;
    status = description;
    notifyListeners();
  }

  Future<void> _queue(Future<void> Function() work) {
    final task = _tail.then((_) => work());
    // Every failed operation is reported to its caller; it must not poison
    // subsequent cleanup operations.
    _tail = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return task;
  }

  Future<void> _deleteClips() async {
    final paths = <String>{
      if (_pendingPath != null) _pendingPath!,
      if (recordedPath != null) recordedPath!,
    };
    _pendingPath = null;
    recordedPath = null;
    for (final filename in paths) {
      await files.delete(filename);
    }
  }

  Future<void> begin() {
    if (!canRecord) return Future<void>.value();
    final generation = ++_epoch;
    _show(AudioSessionState.requestingPermission, '正在检查麦克风权限');
    return _queue(() async {
      try {
        await playback.stop();
        await capture.cancel();
        await _deleteClips();
        if (!_current(generation)) return;
        if (!await capture.hasPermission()) {
          if (_current(generation)) {
            _show(AudioSessionState.denied, '麦克风权限未允许；仍可输入文字。');
          }
          return;
        }
        if (!_current(generation)) return;
        final filename = await files.allocate();
        _pendingPath = filename;
        if (!_current(generation)) {
          await _deleteClips();
          return;
        }
        await capture.startWav(filename, sampleRate: 16000);
        if (!_current(generation)) {
          await capture.cancel();
          await _deleteClips();
          return;
        }
        _show(AudioSessionState.recording, '正在录音；松开试听，滑出取消');
      } catch (_) {
        try {
          await capture.cancel();
        } catch (_) {}
        await _deleteClips();
        if (_current(generation)) {
          _show(AudioSessionState.failed, '录音失败，请检查权限和音频设备。');
        }
      }
    });
  }

  /// Releasing before permission/start resolves is treated as a cancelled tap.
  Future<void> finish() {
    if (_closed) return Future<void>.value();
    if (state != AudioSessionState.recording) return discard();
    final generation = _epoch;
    return _queue(() async {
      try {
        final filename = await capture.stop();
        final pending = _pendingPath;
        _pendingPath = null;
        if (!_current(generation) || filename == null || filename.isEmpty) {
          if (filename != null) await files.delete(filename);
          if (pending != null && pending != filename) {
            await files.delete(pending);
          }
          if (_current(generation)) {
            _show(AudioSessionState.failed, '录音未产生文件，请重试。');
          }
          return;
        }
        if (pending != null && pending != filename) {
          await files.delete(pending);
        }
        recordedPath = filename;
        _show(AudioSessionState.recorded, '录音暂存在本机，可试听或删除（未发送）。');
      } catch (_) {
        await _deleteClips();
        if (_current(generation)) {
          _show(AudioSessionState.failed, '录音保存失败，请重试。');
        }
      }
    });
  }

  Future<void> play() {
    final filename = recordedPath;
    if (_closed || filename == null || state == AudioSessionState.recording) {
      return Future<void>.value();
    }
    final generation = ++_epoch;
    _show(AudioSessionState.playing, '正在播放本地录音（未发送）');
    return _queue(() async {
      try {
        await playback.stop();
        if (!_current(generation)) return;
        await playback.playFile(filename);
        if (!_current(generation)) await playback.stop();
      } catch (_) {
        if (_current(generation)) {
          _show(AudioSessionState.failed, '本地播放失败，可重试或删除。');
        }
      }
    });
  }

  Future<void> stopPlayback() {
    if (_closed) return Future<void>.value();
    ++_epoch;
    _show(
      recordedPath == null ? AudioSessionState.idle : AudioSessionState.recorded,
      '播放已停止；录音仍仅保存在本机。',
    );
    return _queue(() => playback.stop());
  }

  /// Called on swipe-out, page switch, app backgrounding and page teardown.
  /// Invalidation happens synchronously before awaiting any native plugin.
  Future<void> discard() {
    if (_closed) return Future<void>.value();
    ++_epoch;
    _show(AudioSessionState.idle, '录音已取消并删除；不会生成聊天消息。');
    return _queue(() async {
      try {
        await capture.cancel();
      } finally {
        try {
          await playback.stop();
        } finally {
          await _deleteClips();
        }
      }
    });
  }

  Future<void> close() {
    if (_closed) return _tail;
    ++_epoch;
    _closed = true;
    state = AudioSessionState.closed;
    return _queue(() async {
      try {
        await capture.cancel();
        await playback.stop();
      } finally {
        try {
          await _deleteClips();
        } finally {
          await capture.dispose();
          await playback.dispose();
        }
      }
    });
  }
}
