import 'dart:async';

import 'package:erciyuan_mobile/features/audio/application/audio_session_controller.dart';
import 'package:erciyuan_mobile/features/audio/domain/audio_ports.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Capture implements AudioCapturePort {
  bool allowed = true;
  bool recording = false;
  int starts = 0;
  int cancels = 0;
  Completer<bool>? permissionGate;

  @override
  Future<bool> hasPermission() =>
      permissionGate?.future ?? Future<bool>.value(allowed);

  @override
  Future<void> startWav(String path, {int sampleRate = 16000}) async {
    expect(sampleRate, 16000);
    recording = true;
    starts++;
  }

  @override
  Future<String?> stop() async {
    if (!recording) return null;
    recording = false;
    return '/fake/clip.wav';
  }

  @override
  Future<void> cancel() async {
    cancels++;
    recording = false;
  }

  @override
  Future<void> dispose() async {}
}

final class _Playback implements AudioFilePlaybackPort {
  int stops = 0;
  int starts = 0;
  @override
  Future<void> playFile(String path) async {
    starts++;
    expect(path, '/fake/clip.wav');
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

final class _Files implements AudioTemporaryFiles {
  final deleted = <String>[];
  @override
  Future<String> allocate() async => '/fake/clip.wav';
  @override
  Future<void> delete(String path) async => deleted.add(path);
}

void main() {
  late _Capture capture;
  late _Playback playback;
  late _Files files;
  late AudioSessionController audio;

  setUp(() {
    capture = _Capture();
    playback = _Playback();
    files = _Files();
    audio = AudioSessionController(
      capture: capture,
      playback: playback,
      files: files,
    );
  });

  tearDown(() async {
    await audio.close();
    audio.dispose();
  });

  test('permission denial never starts recorder or creates a clip', () async {
    capture.allowed = false;
    await audio.begin();
    expect(audio.state, AudioSessionState.denied);
    expect(capture.starts, 0);
    expect(audio.recordedPath, isNull);
  });

  test('hold, release, replay and discard are local-only', () async {
    await audio.begin();
    expect(audio.state, AudioSessionState.recording);
    await audio.finish();
    expect(audio.state, AudioSessionState.recorded);
    expect(audio.recordedPath, '/fake/clip.wav');
    await audio.play();
    expect(playback.starts, 1);
    await audio.stopPlayback();
    expect(audio.state, AudioSessionState.recorded);
    await audio.discard();
    expect(audio.recordedPath, isNull);
    expect(files.deleted, contains('/fake/clip.wav'));
    expect(audio.state, AudioSessionState.idle);
  });

  test('duplicate release triggers only one native stop', () async {
    await audio.begin();
    await Future.wait([audio.finish(), audio.finish()]);
    expect(audio.state, AudioSessionState.recorded);
    expect(audio.recordedPath, '/fake/clip.wav');
    expect(files.deleted, isNot(contains('/fake/clip.wav')));
  });

  test('maximum capture duration stops and preserves local preview', () async {
    final limited = AudioSessionController(
      capture: capture,
      playback: playback,
      files: files,
      maxDuration: const Duration(milliseconds: 35),
    );
    addTearDown(() async {
      await limited.close();
      limited.dispose();
    });
    await limited.begin();
    expect(limited.state, AudioSessionState.recording);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(limited.state, AudioSessionState.recorded);
    expect(limited.status, contains('上限'));
    expect(limited.recordedPath, '/fake/clip.wav');
    // Finger release after auto-stop must not discard the saved clip.
    await limited.finish();
    expect(limited.recordedPath, '/fake/clip.wav');
    expect(files.deleted, isNot(contains('/fake/clip.wav')));
  });

  test(
    'discard invalidates pending deadline without resurrecting audio',
    () async {
      final limited = AudioSessionController(
        capture: capture,
        playback: playback,
        files: files,
        maxDuration: const Duration(milliseconds: 35),
      );
      addTearDown(() async {
        await limited.close();
        limited.dispose();
      });
      await limited.begin();
      await limited.discard();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(limited.state, AudioSessionState.idle);
      expect(limited.recordedPath, isNull);
      expect(capture.recording, isFalse);
    },
  );

  test('rapid release invalidates late permission without recording', () async {
    capture.permissionGate = Completer<bool>();
    final start = audio.begin();
    final release = audio.finish();
    capture.permissionGate!.complete(true);
    await Future.wait([start, release]);
    expect(capture.starts, 0);
    expect(audio.state, AudioSessionState.idle);
  });

  test('switching a character/background discards and cannot replay', () async {
    await audio.begin();
    await audio.finish();
    await audio.discard();
    await audio.play();
    expect(playback.starts, 0);
    expect(files.deleted, contains('/fake/clip.wav'));
  });

  test('close releases resources and blocks delayed permission', () async {
    capture.permissionGate = Completer<bool>();
    final start = audio.begin();
    final closed = audio.close();
    capture.permissionGate!.complete(true);
    await Future.wait([start, closed]);
    expect(audio.state, AudioSessionState.closed);
    expect(capture.starts, 0);
    expect(audio.canRecord, isFalse);
  });
}
