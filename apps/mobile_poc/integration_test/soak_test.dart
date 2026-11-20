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
  WidgetController.hitTestWarningShouldBeFatal = true;
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
    Future<void> ready(Key key) async {
      final target = find.byKey(key);
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      bool visible() {
        if (target.hitTestable().evaluate().isEmpty) return false;
        final animation = ModalRoute.of(tester.element(target))?.animation;
        return animation == null ||
            animation.status == AnimationStatus.completed;
      }

      while (!visible() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        visible(),
        isTrue,
        reason: '$key must be visible and its route settled',
      );
    }

    Future<void> tap(Key key) async {
      await ready(key);
      await tester.tap(find.byKey(key));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }

    final start = DateTime.now();
    var cycles = 0;
    while (DateTime.now().difference(start) < const Duration(minutes: 15)) {
      await tap(const Key('text-mode'));
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
      await tap(const Key('voice-mode'));
      await tap(const Key('open-history'));
      await ready(const Key('message-list'));
      await tester.drag(
        find.byKey(const Key('message-list')),
        const Offset(0, 160),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tap(const Key('close-history'));
      await tap(const Key('camera-toggle'));
      await tap(const Key('start-call'));
      await tester.pump(const Duration(seconds: 1));
      await tap(const Key('mute-call'));
      await tap(const Key('end-call'));
      await tap(const Key('open-menu'));
      await tap(const Key('menu-roles'));
      final nextRole = chat.selected == 'xing' ? 'yue' : 'xing';
      await tap(Key('select-$nextRole'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(audio.playing, isFalse);
      expect(
        chat.messages.every((m) => m.characterId == chat.selected),
        isTrue,
      );
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
      'scope': 'real-time immersive UI; simulated chat/calls, real SQLite; no microphone capture',
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
