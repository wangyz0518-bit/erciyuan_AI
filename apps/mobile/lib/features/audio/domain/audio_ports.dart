import 'dart:typed_data';

/// Microphone capture is a temporary, explicit user action. A clip is never
/// inserted into raw_events and is never uploaded by this audio layer.
abstract interface class AudioCapturePort {
  Future<bool> hasPermission();
  Future<void> startWav(String path, {int sampleRate = 16000});
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// Plays an already completed local WAV/PCM-encoded file.
abstract interface class AudioFilePlaybackPort {
  Future<void> playFile(String path);
  Future<void> stop();
  Future<void> dispose();
}

/// Explicit 24 kHz, 16-bit, mono PCM chunk playback. Implementations must
/// discard stale stream IDs, provide stop guarantees, and reject bad payloads.
abstract interface class AudioPcmPlaybackPort {
  Future<void> start(String streamId, {int bufferMs = 400});
  Future<void> append(String streamId, Uint8List pcm16le);
  Future<void> end(String streamId);
  Future<void> stop();
  Future<void> dispose();
}

enum AudioSessionState {
  idle,
  requestingPermission,
  recording,
  recorded,
  playing,
  streaming,
  denied,
  failed,
  closed,
}
