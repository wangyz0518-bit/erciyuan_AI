import 'dart:io';

import 'package:erciyuan_mobile/bootstrap.dart';
import 'package:erciyuan_mobile/features/avatar/presentation/avatar_fallback_scene.dart';
import 'package:erciyuan_mobile/features/avatar/presentation/character_avatar_scene.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const zip = String.fromEnvironment('AVATAR_TEST_ZIP');
  const upgrade = String.fromEnvironment('AVATAR_TEST_UPGRADE');
  const invalid = String.fromEnvironment('AVATAR_TEST_INVALID');
  const channel = MethodChannel('erciyuan/live2d');
  testWidgets('character avatar on official chat, switch and reopen', (
    tester,
  ) async {
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
      }
      expect(find.byType(AvatarFallbackScene), findsOneWidget);
      expect(find.byTooltip('人物形象'), findsNothing);
      await switchTo('小月');
      expect(find.byType(AvatarFallbackScene), findsOneWidget);
    } else {
      await waitFor(find.byTooltip('人物形象'));
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
