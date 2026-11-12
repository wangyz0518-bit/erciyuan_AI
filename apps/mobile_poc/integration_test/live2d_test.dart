import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:live2d_avatar/live2d_avatar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:companion_poc/main_live2d.dart';
import 'package:companion_poc/live2d_preview_page.dart';

Future<Live2dPreviewPageState> boot(WidgetTester tester) async {
  await tester.pumpWidget(const Live2dPreviewApp());
  final limit = DateTime.now().add(const Duration(seconds: 90));
  final state = tester.state<Live2dPreviewPageState>(
    find.byType(Live2dPreviewPage),
  );
  while (!state.controller.loaded && DateTime.now().isBefore(limit)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(state.controller.loaded, isTrue, reason: state.status);
  return state;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native texture, capabilities, lifecycle, faults and chat overlays',
    (tester) async {
      final state = await boot(tester);
      final c = state.controller;
      expect(c.expressions.length, 8);
      expect(c.supportsLipSync, isTrue);
      expect(c.motions, isNotEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect((await c.stats())['frames'], greaterThan(0));
      for (final expression in List<String>.from(c.expressions)) {
        await c.command('expression', value: expression);
        await tester.pump(const Duration(milliseconds: 100));
      }
      for (final motion in List<String>.from(c.motions)) {
        await c.command('motion', value: motion);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await expectLater(
        c.command('expression', value: 'missing'),
        throwsA(isA<PlatformException>()),
      );
      for (final file in ['absent', 'broken', 'missing']) {
        await expectLater(
          c.load('assets/live2d/fixtures/$file.model3.json'),
          throwsA(isA<PlatformException>()),
        );
      }
      await state.loadModel('Haru');
      await c.command('mouth', number: .8);
      expect((await c.stats())['mouth'], closeTo(.8, .001));
      await c.command('mouth');
      await state.playAudio();
      final audioMouth = <num>[];
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        audioMouth.add((await c.stats())['mouth'] as num);
      }
      expect(state.playing, isTrue);
      expect(audioMouth.any((value) => value > 0), isTrue);
      await state.stopAudio();
      expect((await c.stats())['mouth'], 0);
      await state.playAudio();
      await tester.pump(const Duration(seconds: 2));
      expect(state.playing, isFalse);
      expect((await c.stats())['mouth'], 0);
      await state.playAudio();
      await state.loadModel('Mark');
      expect(c.supportsLipSync, isFalse);
      expect(state.playing, isFalse);
      expect((await c.stats())['mouth'], 0);
      final samples = <Map<String, dynamic>>[];
      for (int i = 0; i < 30; i++) {
        await c.unload();
        expect((await c.stats())['models'], 0);
        await state.loadModel(i.isEven ? 'Haru' : 'Mark');
        await tester.pump(const Duration(milliseconds: 80));
        final s = await c.stats();
        expect(s['models'], 1);
        expect(s['nativeInstances'], 1);
        expect(s['error'], isNull);
        if (i % 5 == 0) samples.add(s);
      }
      await state.loadModel('Haru');
      for (int i = 0; i < 20; i++) {
        await c.setActive(false);
        final frames = (await c.stats())['frames'];
        await tester.pump(const Duration(milliseconds: 100));
        expect((await c.stats())['frames'], frames);
        await c.setActive(true);
        await tester.pump(const Duration(milliseconds: 100));
        expect((await c.stats())['frames'], greaterThan(frames as num));
      }
      await tester.tap(find.byKey(const Key('history')));
      await tester.pump();
      expect(find.byKey(const Key('close-history')), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-history')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('live2d-input')),
        '中文 🐱\n多行测试',
      );
      await tester.tap(find.byKey(const Key('send')));
      await tester.pump();
      expect(state.messages.last, '中文 🐱\n多行测试');
      expect(tester.takeException(), isNull);
      final result = {
        'reloads': 30,
        'pauseResume': 20,
        'contextRecreations': 20,
        'expressions': 8,
        'faults': 4,
        'audioMouthSamples': audioMouth,
        'samples': samples,
        'final': await c.stats(),
      };
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      for (int i = 0; i < 20; i++) {
        final next = Live2dController();
        await next.create();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Live2dView(controller: next),
          ),
        );
        await next.load('assets/live2d/Haru/Haru.model3.json');
        await tester.pump(const Duration(milliseconds: 150));
        expect((await next.stats())['error'], isNull);
        await next.setActive(false);
        await tester.pumpWidget(const SizedBox());
        await next.close();
      }
      expect(tester.takeException(), isNull);
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/live2d-acceptance.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      binding.reportData = result;
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
