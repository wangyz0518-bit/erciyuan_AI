import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:erciyuan_mobile/immersive/audio_controller.dart';
import 'package:erciyuan_mobile/immersive/conversation_controller.dart';
import 'package:erciyuan_mobile/immersive/model_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:record/record.dart';

// Substitute only the microphone source. Framing, VAD, turn detection,
// transport, transcription and AudioTrack all run through the app.
class _FixtureMicrophone extends RecordPlatform {
  final samples = StreamController<Uint8List>.broadcast();

  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<void> dispose(String recorderId) async {}
  @override
  Future<bool> isRecording(String recorderId) async => samples.hasListener;
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;
  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();
  @override
  Future<String?> stop(String recorderId) async => null;

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    expect(config.sampleRate, 16000);
    expect(config.encoder, AudioEncoder.pcm16bits);
    expect(config.numChannels, 1);
    return samples.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const port = int.fromEnvironment('CONVERSATION_LIVE_PCM_PORT');
  testWidgets(
    'Android keeps a paused voice turn and interrupts its live reply',
    (tester) async {
      final http = HttpClient();
      late final Uint8List pcm;
      try {
        final uri = Uri.http('127.0.0.1:$port', '/two-phrases.pcm');
        final response = await (await http.getUrl(uri)).close();
        expect(response.statusCode, HttpStatus.ok);
        pcm = await consolidateHttpClientResponseBytes(response);
        expect(pcm.length, inInclusiveRange(32000 * 5, 32000 * 20));
      } finally {
        http.close(force: true);
      }

      final gateway = ModelGateway.configured()!;
      expect(gateway.useV3, isTrue);
      final original = RecordPlatform.instance;
      final microphone = _FixtureMicrophone();
      RecordPlatform.instance = microphone;
      final audio = AudioController();
      final voice = ConversationController(gateway, audio);
      // Preserve acknowledgements only. Audio chunks and transcripts stay out of logs.
      final readyInputs = <String>[];
      String? interrupted, aborted, usedVoice;
      final events = voice.transport.events.listen((event) {
        switch (event['event']) {
          case 'audio.started':
            usedVoice = event['voice_profile_id'] as String?;
          case 'input.ready':
            readyInputs.add(event['input_id'] as String);
          case 'interrupt.accepted':
            if (event['stale'] == false) {
              interrupted = event['reply_id'] as String;
            }
          case 'input.aborted':
            aborted = event['input_id'] as String;
        }
      });

      Future<void> until(bool Function() done, Duration timeout) async {
        final clock = Stopwatch()..start();
        while (!done() && clock.elapsed < timeout) {
          await tester.pump(const Duration(milliseconds: 30));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        expect(done(), isTrue, reason: voice.status);
      }

      Future<void> feed(Uint8List clip) async {
        final clock = Stopwatch()..start();
        // 20 ms source packets exercise the production 32 ms frame assembler.
        for (var offset = 0; offset < clip.length; offset += 640) {
          final end = math.min(offset + 640, clip.length);
          microphone.samples.add(Uint8List.sublistView(clip, offset, end));
          final wait =
              Duration(microseconds: end * 1000000 ~/ 32000) - clock.elapsed;
          if (wait > Duration.zero) await Future<void>.delayed(wait);
        }
      }

      try {
        await voice.startCall('xing');
        expect(voice.calling, isTrue, reason: voice.status);
        expect(voice.transport.mode, 'live');
        final binding = await voice.transport.binding('xing');
        expect(binding['profile_id'], isNotNull);
        final before = voice.messages.length;
        await feed(pcm);
        await until(
          () => audio.streamMetrics['event'] == 'firstOutput',
          const Duration(seconds: 85),
        );
        expect(usedVoice, binding['profile_id']);
        final added = voice.messages.skip(before).toList();
        expect(added, hasLength(2), reason: voice.status);
        expect(added.first.text, matches(RegExp('星星.*聊', dotAll: true)));
        expect(added.last.status, 'complete', reason: voice.status);
        expect(added.last.text, isNotEmpty);
        final timing = voice.latency(added.last);
        expect(timing, contains('到开播'));
        expect(timing, contains('转写'));
        debugPrint('Android synthetic voice turn: $timing');
        final replyId = readyInputs.single;
        expect(audio.pcm.active, replyId);
        expect(await audio.pcm.progress(replyId), greaterThan(0));
        // Start speaking again during actual AudioTrack playback.
        await feed(Uint8List.sublistView(pcm, 0, 32000 * 2));
        await until(
          () => interrupted == replyId && readyInputs.length == 2,
          const Duration(seconds: 6),
        );
        expect(audio.pcm.active, isNull);
        expect(voice.playing, isFalse);
        expect(readyInputs.last, isNot(replyId));
        // The first utterance is durable. Mute before committing the new input.
        await voice.toggleMute();
        await until(
          () => aborted == readyInputs.last,
          const Duration(seconds: 4),
        );
        expect(voice.messages.length, before + 2);
        await voice.close();
        await voice.startHold('xing');
        expect(voice.recording, isTrue, reason: voice.status);
        final beforeHold = voice.messages.length;
        usedVoice = null;
        await feed(pcm);
        await voice.finishHold(true);
        await until(
          () =>
              voice.messages.length == beforeHold + 2 &&
              !voice.busy &&
              usedVoice != null,
          const Duration(seconds: 90),
        );
        final held = voice.messages.skip(beforeHold).toList();
        expect(voice.hasRecording(held.first), isTrue);
        expect(held.first.text, matches(RegExp('星星.*聊', dotAll: true)));
        expect(held.last.status, 'complete');
        expect(usedVoice, binding['profile_id']);
      } finally {
        try {
          await events.cancel();
          await voice.shutdown();
          await audio.close();
          await microphone.samples.close();
          await gateway.close();
        } finally {
          RecordPlatform.instance = original;
        }
      }
    },
    skip: port == 0,
  );
}
