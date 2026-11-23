import 'dart:io';
import 'dart:math' as math;

import 'package:erciyuan_mobile/bootstrap.dart';
import 'package:erciyuan_mobile/features/avatar/presentation/avatar_fallback_scene.dart';
import 'package:erciyuan_mobile/features/avatar/presentation/character_avatar_scene.dart';
import 'package:erciyuan_mobile/features/avatar/presentation/dragon_avatar_scene.dart';
import 'package:erciyuan_mobile/features/avatar/presentation/sprout_avatar_scene.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:video_player/video_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const zip = String.fromEnvironment('AVATAR_TEST_ZIP');
  const upgrade = String.fromEnvironment('AVATAR_TEST_UPGRADE');
  const invalid = String.fromEnvironment('AVATAR_TEST_INVALID');
  const channel = MethodChannel('erciyuan/live2d');
  testWidgets('character avatar on official chat, switch and reopen', (
    tester,
  ) async {
    final testDragon = Platform.isAndroid && zip.isEmpty;
    final platform = tester.platformDispatcher;
    if (testDragon) {
      // The CI emulator disables system animations. Exercise the static pose
      // first, then enable animations for the playback assertions.
      platform.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(platform.clearAccessibilityFeaturesTestValue);
    }
    final owner = 'avatar-test-${DateTime.now().microsecondsSinceEpoch}';
    final dbPath = path.join(await getDatabasesPath(), '$owner.db');
    Future<void> openStar() async {
      final db = await PersonDatabase.open(databasePath: dbPath);
      await tester.pumpWidget(
        await bootstrapCompanionApp(ownerId: owner, database: db),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('character-star')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('continue-timeline')));
      await tester.pumpAndSettle();
    }

    Future<void> waitFor(Finder finder) async {
      final timer = Stopwatch()..start();
      while (finder.evaluate().isEmpty &&
          timer.elapsed < const Duration(seconds: 20)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsOneWidget);
    }

    Future<void> switchTo(String name) async {
      await tester.tap(find.byKey(const ValueKey('chat-switch-character')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    CharacterAvatarSceneState scene() =>
        tester.state(find.byType(CharacterAvatarScene));
    Future<Map<dynamic, dynamic>> stats() async =>
        (await channel.invokeMapMethod('stats'))!;
    await openStar();
    if (zip.isEmpty) {
      if (Platform.isAndroid) {
        expect(await channel.invokeMethod<bool>('available'), isFalse);
        await waitFor(find.byType(DragonAvatarScene));
        expect(find.byType(VideoPlayer), findsNothing);
        platform.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures();
        await tester.pump();
        await waitFor(find.byType(VideoPlayer));
        expect(
          tester
              .widget<VideoPlayer>(find.byType(VideoPlayer))
              .controller
              .value
              .isPlaying,
          isTrue,
        );
        await tester.tap(find.byTooltip('人物形象'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('龙角动作预览'));
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        final previewVideo = find.descendant(
          of: dialog,
          matching: find.byType(VideoPlayer),
        );
        for (final clip in DragonAvatarClip.values) {
          await tester.tap(
            find.descendant(
              of: dialog,
              matching: find.widgetWithText(ChoiceChip, clip.label),
            ),
          );
          await tester.pump();
          await waitFor(previewVideo);
          final player = tester.widget<VideoPlayer>(previewVideo).controller;
          expect(player.dataSource, '${clip.asset}.mp4');
          expect(player.value.isPlaying, isTrue);
        }
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('人物形象'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('切回原形象'));
        await waitFor(find.byType(AvatarFallbackScene));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await openStar();
        expect(find.byType(AvatarFallbackScene), findsOneWidget);
        await tester.tap(find.byTooltip('人物形象'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('使用龙角形象'));
        await waitFor(find.byType(DragonAvatarScene));
        await waitFor(find.byType(VideoPlayer));
      } else {
        expect(find.byType(AvatarFallbackScene), findsOneWidget);
        expect(find.byTooltip('人物形象'), findsNothing);
      }
      await switchTo('小月');
      expect(find.byType(AvatarFallbackScene), findsOneWidget);
      expect(find.byType(DragonAvatarScene), findsNothing);
      await switchTo('小芽');
      await waitFor(find.byType(VideoAvatarScene));
      final sproutVideo = find.byWidgetPredicate(
        (widget) =>
            widget is VideoPlayer &&
            widget.controller.dataSource == 'assets/sprout_avatar/idle.mp4' &&
            widget.controller.value.isPlaying,
      );
      if (Platform.isAndroid || Platform.isIOS) {
        await waitFor(sproutVideo);
        await tester.tap(find.byTooltip('人物形象'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('小芽动作预览'));
        await tester.pumpAndSettle();
        final fade = find.descendant(
          of: find.byType(SproutAvatarScene),
          matching: find.byType(ShaderMask),
        );
        final sceneBounds = tester.getRect(find.byType(SproutAvatarScene));
        final fullWidth = math.min(
          sceneBounds.width * .88,
          sceneBounds.height * .77 * 5 / 6,
        );
        for (final motion in AvatarSceneMotion.values) {
          await tester.tap(find.widgetWithText(ChoiceChip, motion.label));
          await tester.pump();
          final video = find.byWidgetPredicate(
            (w) =>
                w is VideoPlayer &&
                w.controller.dataSource ==
                    'assets/sprout_avatar/${motion.name}.mp4' &&
                w.controller.value.isPlaying,
          );
          await waitFor(video);
          final controller = tester.widget<VideoPlayer>(video).controller;
          final source = tester.getRect(video);
          expect(tester.getRect(fade), source);
          expect(source.width, closeTo(fullWidth * 8 / 3, .01));
          final waistY = source.top + source.height * 268 / 576;
          expect(sceneBounds.bottom, greaterThan(waistY));
          final cover = find.image(
            AssetImage('assets/sprout_avatar/${motion.name}.webp'),
          );
          expect(tester.getRect(cover), source);
          if (motion == AvatarSceneMotion.idle) {
            await tester.tap(find.byKey(const Key('avatar-zoom-button')));
            await tester.pumpAndSettle();
            final slider = tester.widget<Slider>(
              find.byKey(const Key('avatar-zoom-slider')),
            );
            for (final value in [.8, 1.0, 1.6, 2.15, 3.0]) {
              slider.onChanged!(value);
              await tester.pump();
              final bounds = tester.getRect(video);
              expect(tester.getRect(fade), bounds);
              expect(bounds.width, closeTo(fullWidth * value, .01));
              expect(tester.getRect(cover), bounds);
              expect(
                tester.widget<VideoPlayer>(video).controller,
                same(controller),
              );
            }
            slider.onChanged!(8 / 3);
            await tester.tap(find.byTooltip('完成'));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('半身'));
          await tester.pump();
          expect(
            tester.widget<VideoPlayer>(video).controller,
            same(controller),
          );
          final fullBody = tester.getRect(video);
          expect(tester.getRect(fade), fullBody);
          expect(tester.getRect(cover), fullBody);
          expect(sceneBounds.contains(fullBody.center), isTrue);
          expect(fullBody.bottom, lessThanOrEqualTo(sceneBounds.bottom));
          await tester.tap(find.text('全身'));
          await tester.pump();
          expect(
            tester.widget<VideoPlayer>(video).controller,
            same(controller),
          );
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        await waitFor(sproutVideo);
      }
      platform.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(platform.clearAccessibilityFeaturesTestValue);
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayer), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/sprout_avatar/idle.webp',
        ),
        findsOneWidget,
      );
      await switchTo('小月');
      expect(find.byType(AvatarFallbackScene), findsOneWidget);
      expect(find.byType(VideoAvatarScene), findsNothing);
    } else {
      await waitFor(find.byTooltip('人物形象'));
      final ready = Stopwatch()..start();
      while (!scene().canImport &&
          ready.elapsed < const Duration(seconds: 20)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(scene().canImport, isTrue);
      await scene().importFile(File(zip));
      await waitFor(find.byType(Texture));
      if (upgrade.isNotEmpty) {
        final before = (await stats())['packageKey'];
        await scene().importFile(File(upgrade));
        expect((await stats())['packageKey'], isNot(before));
      }
      final initial = await stats();
      final key = initial['packageKey'];
      expect(key, isNotEmpty);
      if (invalid.isNotEmpty) {
        await expectLater(
          scene().importFile(File(invalid)),
          throwsA(isA<PlatformException>()),
        );
        expect((await stats())['packageKey'], key);
      }
      await channel.invokeMethod<void>('packageAction', {'id': 'wave'});
      await tester.pump(const Duration(milliseconds: 600));
      final playing = await stats();
      expect(playing['playingMotion'], isNotEmpty);
      expect(playing['frames'], greaterThan(initial['frames'] as int));
      expect(playing['error'], isNull);
      await switchTo('小月');
      await waitFor(find.byTooltip('人物形象'));
      expect(find.byType(AvatarFallbackScene), findsOneWidget);
      expect((await stats())['packageKey'], isEmpty);
      await switchTo('小星');
      await waitFor(find.byType(Texture));
      expect((await stats())['packageKey'], key);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await openStar();
      await waitFor(find.byType(Texture));
      expect((await stats())['packageKey'], key);
      await tester.tap(find.byTooltip('人物形象'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复内置形象'));
      await waitFor(find.byType(AvatarFallbackScene));
      expect((await stats())['packageKey'], isEmpty);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await deleteDatabase(dbPath);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
