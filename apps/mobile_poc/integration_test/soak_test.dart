import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:companion_poc/main.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/audio_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('15 minute real-time emulator UI exercise', (tester) async {
    final store = await LocalStore.open(
      name: 'soak-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final chat = ChatController(
      store,
      chunkDelay: const Duration(milliseconds: 10),
    );
    await chat.init();
    final audio = AudioController();
    await tester.pumpWidget(CompanionApp(chat: chat, audio: audio));
    await tester.pump(const Duration(seconds: 1));
    Future<void> tap(Key key) async {
      await tester.tap(find.byKey(key));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }

    final start = DateTime.now();
    var cycles = 0;
    while (DateTime.now().difference(start) < const Duration(minutes: 15)) {
      await tester.enterText(
        find.byKey(const Key('message-input')),
        '持续验证第 $cycles 轮：中文🙂与本地回复',
      );
      await tester.pump();
      await tap(const Key('send'));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (chat.busy && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(chat.busy, isFalse);
      expect(chat.messages.last.status, 'complete');
      await tester.drag(
        find.byKey(const Key('message-list')),
        const Offset(0, 180),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tap(const Key('nav-avatar'));
      await tap(ValueKey('emotion-${cycles.isEven ? '开心' : '疑惑'}'));
      await tap(ValueKey('activity-${cycles.isEven ? '说话' : '待机'}'));
      await tap(const Key('nav-audio'));
      await tap(const Key('play-tone'));
      await tester.pump(const Duration(seconds: 1));
      expect(audio.playing, isTrue);
      await tap(const Key('role-selector'));
      final nextRole = chat.selected == 'xing' ? '小月' : '小星';
      await tester.tap(find.text(nextRole).last);
      await tester.pump(const Duration(seconds: 1));
      expect(audio.playing, isFalse);
      expect(
        chat.messages.every((m) => m.characterId == chat.selected),
        isTrue,
      );
      await tap(const Key('nav-chat'));
      // Periodically detach the whole page and recreate it with the same saved core.
      if (cycles % 5 == 4) {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpWidget(CompanionApp(chat: chat, audio: audio));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(tester.takeException(), isNull);
      cycles++;
      if (cycles % 5 == 0) {
        debugPrint(
          'SOAK_PROGRESS cycles=$cycles seconds=${DateTime.now().difference(start).inSeconds}',
        );
      }
    }
    final result = {
      'started_at': start.toIso8601String(),
      'finished_at': DateTime.now().toIso8601String(),
      'elapsed_seconds': DateTime.now().difference(start).inSeconds,
      'cycles': cycles,
      'message_count': await store.count(),
      'result': 'passed',
      'scope': 'real-time automated UI; simulated chat, real SQLite and Android audio player; no microphone capture',
    };
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/soak-results.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    debugPrint('SOAK_RESULTS ${jsonEncode(result)}');
    await tester.pumpWidget(const SizedBox());
    await audio.close();
    chat.dispose();
    await store.db.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
