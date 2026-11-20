import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/conversation_capture.dart';
import 'package:companion_poc/conversation_controller.dart';
import 'package:companion_poc/model_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class TestCapture extends ConversationCapture {
  void Function(Uint8List, double)? frame;

  @override
  Future<void> start({
    required bool call,
    required void Function(Uint8List, double) onFrame,
    required void Function(Object) onError,
  }) async {
    frame = onFrame;
  }

  void feed(int count, int marker, double probability) {
    for (var i = 0; i < count; i++) {
      frame?.call(Uint8List(1024)..[0] = marker, probability);
    }
  }

  @override
  Future<void> stop() async => frame = null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android loads the bundled VAD and runs native inference', (
    _,
  ) async {
    const vad = MethodChannel('dev.erciyuan/vad');
    await vad.invokeMethod<void>('reset');
    for (var i = 0; i < 12; i++) {
      final probability = await vad.invokeMethod<double>(
        'probability',
        Uint8List(1024),
      );
      expect(probability, inInclusiveRange(0, .35));
    }
  });

  testWidgets('Android microphone streams framed PCM and releases on stop', (
    _,
  ) async {
    final capture = ConversationCapture();
    final frame = Completer<Uint8List>();
    var count = 0;
    try {
      await capture.start(
        call: true,
        onFrame: (pcm, _) {
          count++;
          if (!frame.isCompleted) frame.complete(pcm);
        },
        onError: (error) {
          if (!frame.isCompleted) frame.completeError(error);
        },
      );
      expect(
        await frame.future.timeout(const Duration(seconds: 5)),
        hasLength(1024),
      );
      await capture.stop();
      final stoppedAt = count;
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(count, stoppedAt);
    } finally {
      await capture.dispose();
    }
  });

  testWidgets(
    'v3 retains paused speech and cancels playback before the next input',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final commands = <Map<String, Object?>>[];
      final audioReceived = <String, List<int>>{};
      var sequencesValid = true;
      final history = <Map<String, Object?>>[];
      final pending = <String, String>{};
      var wire = Completer<WebSocket>();
      server.listen((request) async {
        final connection = await WebSocketTransformer.upgrade(request);
        wire.complete(connection);
        connection.listen((dynamic data) {
          if (data is List<int>) {
            final bytes = Uint8List.fromList(data);
            final length = ByteData.sublistView(bytes).getUint32(0);
            final header =
                jsonDecode(utf8.decode(bytes.sublist(4, length + 4))) as Map;
            final samples = audioReceived.putIfAbsent(
              header['input_id'] as String,
              () => [],
            );
            sequencesValid = sequencesValid && header['seq'] == samples.length;
            samples.add(bytes[4 + length]);
            return;
          }
          final value = Map<String, Object?>.from(
            jsonDecode(data as String) as Map,
          );
          commands.add(value);
          if (value['command'] == 'session.start') {
            connection.add(
              jsonEncode({
                'event': 'session.ready',
                'protocol': 3,
                'session_id': 'test-session',
                'character_id': 'xing',
                'mode': 'live',
                'history': history,
              }),
            );
          }
          if (value['command'] == 'session.end') unawaited(connection.close());
          if (value['command'] == 'input.start') {
            pending[value['input_id'] as String] = value['kind'] as String;
          }
        });
      });
      final audio = AudioController();
      final capture = TestCapture();
      final client = ConversationController(
        ModelGateway(
          'http://127.0.0.1:${server.port}',
          'test-development-token',
          useV3: true,
        ),
        audio,
        capture: capture,
      );
      Future<void> until(bool Function() condition) async {
        final until = DateTime.now().add(const Duration(seconds: 8));
        while (!condition() && DateTime.now().isBefore(until)) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(condition(), isTrue);
      }

      var socket = await (() async {
        unawaited(client.startCall('xing'));
        return wire.future;
      })();
      void send(String event, Map<String, Object?> fields) => socket.add(
        jsonEncode({'event': event, 'session_id': 'test-session', ...fields}),
      );
      List<String> commits() => commands
          .where((c) => c['command'] == 'input.commit')
          .map((c) => c['input_id'] as String)
          .toList();
      void save(String id, String prompt) {
        final row = {
          'id': id,
          'prompt': prompt,
          'reply': '',
          'state': 'running',
          'kind': pending[id],
          'has_recording': pending[id] == 'hold',
        };
        history.add(row);
        send('transcript.final', {'input_id': id, 'text': prompt});
        send('turn.saved', {'turn': row});
      }

      void play(String id) {
        send('reply.delta', {'reply_id': id, 'delta': '好，我接着说。'});
        send('reply.saved', {'reply_id': id, 'text': '好，我接着说。'});
        send('audio.started', {
          'reply_id': id,
          'sample_rate': 24000,
          'channels': 1,
          'format': 'pcm_s16le',
        });
        final header = utf8.encode(
          jsonEncode({
            'event': 'audio.chunk',
            'session_id': 'test-session',
            'reply_id': id,
            'seq': 0,
            'offset': 0,
          }),
        );
        final packet = Uint8List(4 + header.length + 48000);
        ByteData.sublistView(packet).setUint32(0, header.length);
        packet.setRange(4, 4 + header.length, header);
        for (var i = 4 + header.length + 1; i < packet.length; i += 2) {
          packet[i] = (i % 60 < 30) ? 4 : 252;
        }
        socket.add(packet);
      }

      try {
        await until(() => client.calling);
        capture.feed(12, 1, .99);
        capture.feed(64, 0, .01); // A 2.048-second gap within the same turn.
        capture.feed(12, 2, .99);
        capture.feed(80, 0, .01);
        await until(() => commits().length == 1);
        final first = commits().single;
        expect(audioReceived[first]!.where((v) => v != 0), [
          ...List.filled(12, 1),
          ...List.filled(12, 2),
        ]);

        capture.feed(12, 3, .99);
        capture.feed(80, 0, .01);
        await tester.pump();
        expect(commits(), [first]);
        save(first, '第一句。第二句。');
        await until(() => commits().length == 2);
        final second = commits().last;
        expect(audioReceived[second]!.where((v) => v != 0), List.filled(12, 3));
        expect(commands.where((x) => x['command'] == 'input.abort'), isEmpty);

        save(second, '下一句');
        play(second);
        await until(() => audio.streamMetrics['event'] == 'firstOutput');
        expect(client.latency(client.messages.last), contains('到开播'));
        capture.feed(5, 4, .99);
        await until(
          () => commands.any(
            (c) => c['command'] == 'turn.interrupt' && c['reply_id'] == second,
          ),
        );
        expect(audio.pcm.active, isNull);
        expect(commits(), [first, second]);

        await client.toggleMute();
        expect(capture.frame, isNull);
        await client.toggleMute();
        expect(capture.frame, isNotNull);
        await client.close();
        expect(capture.frame, isNull);

        wire = Completer<WebSocket>();
        final hold = client.startHold('xing');
        socket = await wire.future;
        await hold;
        capture.feed(15, 5, 0);
        await client.finishHold(true);
        await until(() => commits().length == 3);
        final held = commits().last;
        save(held, '按住说话');
        await until(() => client.messages.length == 6);
        expect(client.hasRecording(client.messages[4]), isTrue);

        await client.startHold('xing');
        capture.feed(12, 6, 0);
        await client.finishHold(false);
        await until(
          () =>
              commands.where((c) => c['command'] == 'input.abort').length >= 2,
        );
        expect(commits().length, 3);
        expect(sequencesValid, isTrue);
      } finally {
        await client.shutdown();
        await audio.close();
        await server.close(force: true);
      }
    },
  );
}
