import 'dart:convert';

import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/main.dart';
import 'package:companion_poc/model_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('ten real turns, two roles, streaming playback and restore', (
    tester,
  ) async {
    final gateway = ModelGateway.configured()!;
    final name = 'stream-live-${DateTime.now().microsecondsSinceEpoch}.db';
    final store = await LocalStore.open(name: name);
    final chat = ChatController(store, gateway: gateway);
    final audio = AudioController();
    await chat.init();
    try {
      await tester.pumpWidget(CompanionApp(chat: chat, audio: audio));
      await tester.pump(const Duration(seconds: 1));
      for (final role in ['xing', 'yue']) {
        await audio.stopAll();
        await chat.switchCharacter(role);
        await tester.pump();
        final keyword = role == 'xing' ? '青松' : '红枫';
        final lines = [
          '请记住本次测试暗号是$keyword，只回复暗号。',
          '刚才的测试暗号是什么？只回复暗号。',
          '请用十个字以内向我问好。',
          '请用一句十五字以内的中文说说晴天。',
          '请用一句十五字以内的中文道别。',
        ];
        for (int i = 0; i < lines.length; i++) {
          audio.streamMetrics.clear();
          await chat.send(lines[i]);
          final deadline = DateTime.now().add(const Duration(seconds: 110));
          while (!audio.streamMetrics.containsKey('sendToOutputMs') &&
              find.byKey(const Key('retry-speech')).evaluate().isEmpty &&
              chat.messages.last.status == 'complete' &&
              DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          debugPrint(
            'STREAM_LIVE ${jsonEncode({'role': role, 'case': i + 1, 'chat': chat.messages.last.status, 'voiceFailed': find.byKey(const Key('retry-speech')).evaluate().isNotEmpty, 'contextCorrect': i > 1 ? null : chat.messages.last.text.contains(keyword), ...audio.streamMetrics})}',
          );
          expect(chat.messages.last.status, 'complete');
          expect(
            audio.streamMetrics.containsKey('sendToOutputMs'),
            isTrue,
            reason: 'Missing completed native playback',
          );
          if (i < 2) expect(chat.messages.last.text, contains(keyword));
        }
      }
      expect((await store.messages('xing')).length, 10);
      expect((await store.messages('yue')).length, 10);
      await tester.pumpWidget(const SizedBox());
      await store.db.close();
      final reopened = await LocalStore.open(name: name);
      final restored = ChatController(reopened);
      await restored.init();
      expect(restored.selected, 'yue');
      expect(restored.messages.length, 10);
      expect(restored.messages.every((m) => m.status == 'complete'), isTrue);
      restored.dispose();
      await reopened.db.close();
    } finally {
      await tester.pumpWidget(const SizedBox());
      await audio.close();
      chat.dispose();
      if (store.db.isOpen) await store.db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
