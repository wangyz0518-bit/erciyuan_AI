import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:erciyuan_mobile/features/voice/application/voice_input_controller.dart';
import 'package:erciyuan_mobile/features/voice/data/conversation_capture.dart';
import 'package:erciyuan_mobile/features/voice/data/voice_input_stream.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConversationCapture implements ConversationCapture {
  void Function(Uint8List, double)? feed;
  @override
  Future<void> start({
    required bool call,
    required void Function(Uint8List, double) onFrame,
    required void Function(Object) onError,
  }) async {
    feed = onFrame;
  }

  @override
  Future<void> stop() async {
    feed = null;
  }

  @override
  Future<void> dispose() => stop();
}

void main() {
  for (final send in [true, false]) {
    test(
      'hold and ${send ? "submit" : "cancel"} while websocket connects',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final remoteClosed = Completer<void>();
        final commands = <String>[];
        final texts = <String>[];
        server.listen((req) async {
          expect(req.headers.value('authorization'), 'Bearer fixture');
          final ws = await WebSocketTransformer.upgrade(req);
          ws.add('{"type":"ready","mode":"demo"}');
          await for (final frame in ws) {
            if (frame is String) {
              commands.add(frame);
              ws.add('{"type":"partial","text":"半句"}');
              ws.add('{"type":"final","text":"一句完整的话"}');
            }
          }
          remoteClosed.complete();
        });
        final capture = FakeConversationCapture();
        final controller = VoiceInputController(
          capture: capture,
          open: (partial) => VoiceInputStream(
            Uri.parse('ws://127.0.0.1:${server.port}/star'),
            'fixture',
            partial,
          ),
          submit: (text) async => texts.add(text),
        );
        addTearDown(() async {
          controller.dispose();
          await server.close(force: true);
        });
        await controller.startHold();
        for (var i = 0; i < 8; i++) {
          capture.feed!(Uint8List(1024), 0);
        }
        await controller.endHold(send);
        await remoteClosed.future.timeout(const Duration(seconds: 5));
        expect(commands, send ? ['commit'] : isEmpty);
        expect(texts, send ? ['一句完整的话'] : isEmpty);
      },
    );
  }
}
