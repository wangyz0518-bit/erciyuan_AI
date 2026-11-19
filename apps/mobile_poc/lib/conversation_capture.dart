import 'dart:async';

import 'package:flutter/services.dart';
import 'package:record/record.dart';

/// Capture mono PCM through the platform recorder.
class ConversationCapture {
  static const frameBytes = 1024; // 512 PCM16 samples, 32 ms.
  static const _detector = MethodChannel('dev.erciyuan/vad');
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  int _epoch = 0;

  Future<void> _serialize(Future<void> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> start({
    required bool call,
    required void Function(Uint8List frame, double probability) onFrame,
    required void Function(Object) onError,
  }) {
    final epoch = ++_epoch;
    return _serialize(() async {
      if (_disposed || epoch != _epoch) return;
      if (!await _recorder.hasPermission()) throw const MicPermissionDenied();
      if (epoch != _epoch) return;
      if (call) await _detector.invokeMethod<void>('reset');
      if (epoch != _epoch) return;
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: call,
          noiseSuppress: call,
          androidConfig: AndroidRecordConfig(
            audioSource: call
                ? AndroidAudioSource.voiceCommunication
                : AndroidAudioSource.mic,
            audioManagerMode: call
                ? AudioManagerMode.modeInCommunication
                : AudioManagerMode.modeNormal,
            manageBluetooth: false,
            speakerphone: call,
          ),
        ),
      );
      if (epoch != _epoch) {
        await _recorder.stop();
        return;
      }
      var frame = Uint8List(frameBytes);
      var filled = 0;
      var backlogged = 0;
      Future<void> processing = Future.value();
      _subscription = stream.listen(
        (chunk) {
          if (epoch != _epoch) return;
          if (backlogged + chunk.length > 32000) {
            onError(StateError('Recording could not keep up'));
            return;
          }
          backlogged += chunk.length;
          processing = processing
              .then((_) async {
                if (epoch != _epoch) return;
                var offset = 0;
                while (offset < chunk.length && epoch == _epoch) {
                  final count = (chunk.length - offset).clamp(
                    0,
                    frame.length - filled,
                  );
                  frame.setRange(filled, filled + count, chunk, offset);
                  filled += count;
                  offset += count;
                  if (filled == frame.length) {
                    final pcm = frame;
                    frame = Uint8List(frameBytes);
                    filled = 0;
                    final score = call
                        ? await _detector.invokeMethod<double>(
                            'probability',
                            pcm,
                          )
                        : 0.0;
                    if (epoch == _epoch) onFrame(pcm, score ?? 0);
                  }
                }
                backlogged -= chunk.length;
              })
              .catchError((Object error) {
                if (epoch == _epoch) onError(error);
              });
        },
        onError: (Object error) {
          if (epoch == _epoch) onError(error);
        },
        onDone: () {
          if (epoch == _epoch) onError(StateError('Microphone closed'));
        },
      );
    });
  }

  Future<void> stop() {
    ++_epoch; // Invalidate callbacks even during the permission dialog.
    return _serialize(() async {
      final active = _subscription;
      _subscription = null;
      if (active != null) {
        await active.cancel();
        await _recorder.stop();
      }
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _recorder.dispose();
  }
}

class MicPermissionDenied implements Exception {
  const MicPermissionDenied();
}

/// Endpointing uses capture frames (32 ms), so slow packets cannot end speech early.
class SpeechSegmenter {
  SpeechSegmenter({
    required this.onStart,
    required this.onFrame,
    required this.onEnd,
  });
  final void Function(List<Uint8List>) onStart;
  final void Function(Uint8List, double) onFrame;
  final void Function() onEnd;
  final _ring = <Uint8List>[];
  bool _speaking = false;
  int _candidate = 0, _silence = 0;
  bool get speaking => _speaking;

  void add(Uint8List frame, double probability) {
    if (_speaking) {
      onFrame(frame, probability);
      if (probability >= .65) {
        _silence = 0;
      } else if (probability < .35 && ++_silence >= 80) {
        reset();
        onEnd();
      }
      return;
    }
    _ring.add(frame);
    if (_ring.length > 10) _ring.removeAt(0);
    if (probability >= .65) {
      if (++_candidate >= 5) {
        _speaking = true;
        _silence = 0;
        onStart(List.of(_ring));
        _ring.clear();
      }
    } else if (probability < .35) {
      _candidate = 0;
    }
  }

  void reset() {
    _speaking = false;
    _candidate = 0;
    _silence = 0;
    _ring.clear();
  }
}
