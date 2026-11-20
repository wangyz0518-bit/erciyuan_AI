import 'dart:convert';
import 'dart:io';

import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/model_gateway.dart';
import 'package:companion_poc/reply_speech_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cold and reused connections: fixed lines through Android PCM', (
    tester,
  ) async {
    final gateway = ModelGateway.configured()!;
    final http = HttpClient();
    Future<Map<String, dynamic>> fixture(
      String path, {
      bool post = false,
    }) async {
      final request = await http.openUrl(
        post ? 'POST' : 'GET',
        Uri.parse('${gateway.baseUrl}/benchmark/$path'),
      );
      request.headers.set('Authorization', 'Bearer ${gateway.token}');
      final response = await request.close();
      expect(response.statusCode, 200);
      return jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>;
    }

    final cases = (await fixture('cases'))['cases'] as List;
    final store = await LocalStore.open(
      name: 'stream-benchmark-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final chat = ChatController(store, gateway: gateway);
    final audio = AudioController();
    final speech = ReplySpeechController(gateway, audio);
    await chat.init();
    Future<void>? playback;
    chat.onReplyComplete = (message, id) {
      playback = speech.speak(id, message.characterId);
    };
    try {
      for (final mode in ['cold', 'reuse']) {
        await fixture('reset', post: true);
        for (final item in cases) {
          if (mode == 'cold') await fixture('reset', post: true);
          playback = null;
          await chat.send(item['id'] as String);
          expect(chat.messages.last.status, 'complete');
          expect(chat.messages.last.text, item['text']);
          expect(playback, isNotNull);
          await playback;
          final result = <String, Object?>{
            'case': item['id'],
            'mode': mode,
            'failed': speech.failed,
            'saved': chat.messages.last.status == 'complete',
            ...audio.streamMetrics,
          };
          // Only metrics and synthetic case IDs, no credentials or real conversation.
          debugPrint('STREAM_BENCHMARK ${jsonEncode(result)}');
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      final expected = cases.length * 4;
      expect(await store.count(), expected);
      await gateway.close();
      final restored = ChatController(store);
      await restored.init();
      expect(restored.messages.length, expected);
      restored.dispose();
    } finally {
      speech.dispose();
      await audio.close();
      chat.dispose();
      await store.db.close();
      http.close();
    }
  }, timeout: const Timeout(Duration(minutes: 18)));
}
