import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'live2d_test.dart' show boot;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('15 minutes of rendered character and Flutter UI interaction', (
    tester,
  ) async {
    final state = await boot(tester);
    final watch = Stopwatch()..start();
    final samples = <Map<String, dynamic>>[];
    int round = 0;
    while (watch.elapsed < const Duration(minutes: 15)) {
      debugPrint('SOAK $round load');
      await state.loadModel(round.isEven ? 'Haru' : 'Mark');
      debugPrint('SOAK $round history');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('history')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('close-history')));
      await tester.pump(const Duration(milliseconds: 100));
      debugPrint('SOAK $round input');
      await tester.tap(find.byKey(const Key('live2d-input')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(
        find.byKey(const Key('live2d-input')),
        '持续测试 $round',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.input.text, '持续测试 $round');
      await tester.tap(find.byKey(const Key('send')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.messages.last, '持续测试 $round');
      expect(state.messages.length, round + 3);
      debugPrint('SOAK $round audio');
      if (round % 4 == 0) {
        await state.playAudio();
      }
      for (int j = 0; j < 15; j++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await state.stopAudio();
      final s = await state.controller.stats();
      debugPrint('SOAK $round sampled at ${watch.elapsed.inSeconds}s');
      expect(s['error'], isNull);
      expect(s['models'], 1);
      samples.add({'elapsedMs': watch.elapsedMilliseconds, ...s});
      expect(tester.takeException(), isNull);
      round++;
    }
    final result = {
      'elapsedMs': watch.elapsedMilliseconds,
      'rounds': round,
      'messages': state.messages.length,
      'samples': samples,
    };
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/live2d-soak.json')
        .writeAsString(jsonEncode(result));
    binding.reportData = result;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 25)));
}
