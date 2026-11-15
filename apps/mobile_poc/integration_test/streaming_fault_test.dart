import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/model_gateway.dart';
import 'package:companion_poc/reply_speech_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Device-local fault injection. No model/network charges, real SQLite and AudioTrack.
class Fixture {
  late HttpServer server;
  final sockets = <WebSocket>[];
  final commands = <String>[];
  int replies = 0;
  bool failVoice = true, badSequence = false;
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final command = jsonDecode(raw as String) as Map;
        final type = command['command'] as String;
        commands.add(type);
        final rid = command['request_id'];
        final role = request.uri.path.contains('local-yue') ? 'yue' : 'xing';
        final sid = command['speech_id'] ?? 'fixture-voice-$replies';
        void send(String event, Map<String, Object?> fields) => socket.add(
          jsonEncode({
            'event': event,
            'request_id': rid,
            'character_id': role,
            ...fields,
          }),
        );
        if (type == 'chat.send') {
          replies++;
          send('message.delta', {'delta': '固定测试回复'});
          send('message.completed', {'content': '固定测试回复', 'speech_id': sid});
        }
        if (type == 'turn.status') {
          if ((rid as String).startsWith('missing')) {
            send('request.failed', {'code': 'REQUEST_NOT_FOUND'});
          } else {
            send('turn.status', {'status': 'completed', 'content': '固定测试回复'});
          }
        }
        if (type == 'chat.send' || type == 'speech.retry') {
          if (failVoice) {
            send('audio.failed', {
              'speech_id': sid,
              'code': 'VOICE_UNAVAILABLE',
            });
          } else {
            send('audio.started', {
              'speech_id': sid,
              'format': 'pcm_s16le',
              'sample_rate': 24000,
              'channels': 1,
            });
            // The existing synthetic PCM tone is repurposed as a transport fixture.
            final pcm = makeTone().sublist(44);
            final header = utf8.encode(
              jsonEncode({
                'event': 'audio.chunk',
                'request_id': rid,
                'character_id': role,
                'speech_id': sid,
                'seq': badSequence ? 1 : 0,
                'offset': 0,
              }),
            );
            final frame = Uint8List(4 + header.length + pcm.length);
            ByteData.sublistView(frame).setUint32(0, header.length);
            frame.setRange(4, 4 + header.length, header);
            frame.setRange(4 + header.length, frame.length, pcm);
            socket.add(frame);
            send('audio.completed', {
              'speech_id': sid,
              'bytes': pcm.length,
              'chunks': 1,
            });
          }
        }
      });
    });
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'v2 voice failure, retry, SQLite failure, role isolation and malformed PCM',
    (tester) async {
      final fixture = Fixture();
      await fixture.start();
      final gateway = ModelGateway(
        'http://127.0.0.1:${fixture.server.port}',
        'fixture',
        useV2: true,
      );
      final store = await LocalStore.open(
        name: 'stream-fault-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final chat = ChatController(store, gateway: gateway);
      final audio = AudioController();
      final speech = ReplySpeechController(gateway, audio);
      Future<void>? playback;
      chat.onReplyComplete = (message, id) {
        playback = speech.speak(id, message.characterId);
      };
      await chat.init();
      try {
        await chat.send('语音失败保留文字');
        await playback;
        expect(speech.failed, isTrue);
        expect(chat.messages.last.status, 'complete');
        expect(await store.count(), 2);
        fixture.failVoice = false;
        await speech.retry();
        expect(speech.failed, isFalse);
        expect(audio.streamMetrics['frames'], 64000);
        expect(
          fixture.replies,
          1,
          reason: 'Voice retry never regenerates chat',
        );
        expect(await store.count(), 2);
        final replyId = gateway.streaming.turns.keys.single;
        await gateway.close();
        final remote = await gateway.streaming.status(replyId, 'xing');
        expect(remote['status'], 'completed');
        expect(
          fixture.replies,
          1,
          reason: 'Reconnect status never resubmits chat',
        );
        await expectLater(
          gateway.streaming.status('missing-request-0001', 'xing'),
          throwsA(isA<GatewayException>()),
        );
        // Interrupt a blocking native write, then inject a late old-generation chunk.
        final epoch = audio.operationEpoch;
        await audio.startPcm('cancel-fixture', epoch);
        final writing = audio
            .appendPcm('cancel-fixture', makeTone().sublist(44), epoch)
            .then((_) {}, onError: (Object _) {});
        for (int i = 0; i < 30 && !audio.playing; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(audio.playing, isTrue);
        final stopClock = Stopwatch()..start();
        await audio.stopAll();
        await writing;
        expect(stopClock.elapsedMilliseconds, lessThan(1000));
        await audio.appendPcm('cancel-fixture', makeTone().sublist(44), epoch);
        expect(audio.playing, isFalse);
        expect(audio.pcm.active, isNull);
        // Force final save to fail after a complete reply, before playback can start.
        await store.db.execute(
          "CREATE TRIGGER fail_complete BEFORE INSERT ON messages WHEN NEW.author='assistant' AND NEW.status='complete' BEGIN SELECT RAISE(ABORT,'fixture'); END",
        );
        playback = null;
        await chat.send('保存失败禁止朗读');
        await tester.pump(const Duration(milliseconds: 300));
        expect(playback, isNull);
        expect(chat.messages.last.status, 'failed');
        expect(fixture.commands, contains('turn.cancel'));
        expect(audio.playing, isFalse);
        await store.db.execute('DROP TRIGGER fail_complete');
        await audio.stopAll();
        await chat.switchCharacter('yue');
        expect(chat.messages, isEmpty);
        fixture.badSequence = true;
        await chat.send('错误音频序号');
        await playback;
        expect(speech.failed, isTrue);
        expect(chat.messages.last.status, 'complete');
        expect(audio.playing, isFalse);
        expect((await store.messages('xing')).length, 4);
        expect((await store.messages('yue')).length, 2);
        await gateway.close();
        final restored = ChatController(store);
        await restored.init();
        expect(restored.selected, 'yue');
        expect(restored.messages.last.status, 'complete');
        restored.dispose();
      } finally {
        speech.dispose();
        await audio.close();
        chat.dispose();
        await store.db.close();
        await fixture.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
