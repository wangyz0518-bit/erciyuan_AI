import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:companion_poc/dragon_idle_page.dart';
import 'package:companion_poc/main_live2d.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'character idle preview animates and pauses through normal entry',
    (tester) async {
      app.main();
      await tester.pump();
      final state = tester.state<DragonIdlePageState>(
        find.byType(DragonIdlePage),
      );
      final limit = DateTime.now().add(const Duration(seconds: 30));
      while (!state.loaded &&
          state.error == null &&
          DateTime.now().isBefore(limit)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.loaded, isTrue, reason: state.error);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('idle-avatar')),
      );
      Future<Uint8List> capture() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return data!.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } finally {
          image.dispose();
        }
      }

      Future<void> frames(int count) async {
        for (int i = 0; i < count; i++) {
          await tester.pump(const Duration(milliseconds: 33));
        }
      }

      await frames(8);
      final before = await capture();
      await frames(75);
      final after = await capture();
      expect(
        after,
        isNot(before),
        reason: 'animation must change actual rendered pixels',
      );
      await tester.tap(find.byKey(const Key('idle-play')));
      await tester.pump();
      final frozenTime = state.time.value;
      final frozen = await capture();
      await frames(15);
      expect(state.time.value, frozenTime);
      expect(await capture(), frozen);
      await tester.tap(find.byKey(const Key('idle-framing')));
      await tester.pump();
      expect(
        await capture(),
        isNot(frozen),
        reason: 'framing must repaint while paused',
      );
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.tap(find.byKey(const Key('idle-play')));
      await frames(10);
      expect(state.time.value, frozenTime);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await frames(8);
      expect(state.time.value, greaterThan(frozenTime));
      final intensity = find.byKey(const Key('idle-intensity'));
      final rect = tester.getRect(intensity);
      await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
      await tester.pump();
      expect(state.intensity, lessThan(.1));
      await tester.tap(find.byKey(const Key('idle-reset')));
      await tester.pump();
      expect(state.intensity, .75);
      expect(state.closeView, isFalse);
      expect(state.playing, isTrue);
      await frames(60);
      expect(tester.takeException(), isNull);
      int changedBytes = 0;
      for (int i = 0; i < before.length; i++) {
        if (before[i] != after[i]) changedBytes++;
      }
      final result = {
        'loaded': true,
        'changedPixelBytes': changedBytes,
        'pausePixelsStable': true,
        'pausedFramingRepaints': true,
        'lifecycle': 'passed',
        'reset': 'passed',
      };
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/dragon-idle-acceptance.json')
          .writeAsString(jsonEncode(result));
      binding.reportData = result;
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
