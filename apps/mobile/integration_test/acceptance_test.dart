import 'package:erciyuan_mobile/app/companion_app.dart';
import 'package:erciyuan_mobile/features/characters/application/character_selection_controller.dart';
import 'package:erciyuan_mobile/features/characters/data/mock_character_catalog.dart';
import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Actual device/emulator integration: Flutter UI + platform SQLite plugin.
/// It never makes paid model requests and never claims to test a physical phone.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android: persistent chat, character isolation and database reopen',
    (tester) async {
      const star = PersonScope(
        ownerId: 'integration-owner',
        characterId: 'star',
      );
      const moon = PersonScope(
        ownerId: 'integration-owner',
        characterId: 'moon',
      );
      final dbPath = path.join(
        await getDatabasesPath(),
        'official-integration-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      var database = await PersonDatabase.open(databasePath: dbPath);
      addTearDown(() async {
        await database.close();
        await deleteDatabase(dbPath);
      });
      const people = [
        Character(scope: star, name: '小星', description: '人物 A'),
        Character(scope: moon, name: '小月', description: '人物 B'),
      ];
      for (final character in people) {
        await database.createCharacter(
          character: character,
          timelineId: 'integration-${character.scope.characterId}',
        );
      }
      final selection = CharacterSelectionController(
        ownerId: star.ownerId,
        catalog: MockCharacterCatalog(people),
      );
      await tester.pumpWidget(
        CompanionApp(
          controller: selection,
          database: database,
          closeDatabaseOnDispose: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('人物主页'), findsOneWidget);
      expect(find.text('新建会话'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('continue-timeline')));
      await tester.pumpAndSettle();
      expect(find.text('唯一持续时间线'), findsOneWidget);
      expect(find.textContaining('离线 Mock 模式'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('character-draft')),
        '只属于小星的 Android 原始记录',
      );
      await tester.tap(find.byKey(const ValueKey('send-message')));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if ((await database.rawEventsFor(scope: star)).length == 2) break;
      }
      final starHistory = await database.rawEventsFor(scope: star);
      expect(starHistory, hasLength(2));
      expect(starHistory.first.content, '只属于小星的 Android 原始记录');
      expect(starHistory.first.speaker, 'user');
      expect(starHistory.last.content, contains('离线 Mock'));
      expect(starHistory.last.speaker, 'assistant');
      expect(await database.rawEventsFor(scope: moon), isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('character-moon')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('continue-timeline')));
      await tester.pumpAndSettle();
      expect(find.text('唯一持续时间线'), findsOneWidget);
      expect(find.textContaining('只属于小星的 Android 原始记录'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('character-draft')),
        '小月自己的一条消息',
      );
      await tester.tap(find.byKey(const ValueKey('send-message')));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if ((await database.rawEventsFor(scope: moon)).length == 2) break;
      }
      final moonHistory = await database.rawEventsFor(scope: moon);
      expect(moonHistory, hasLength(2));
      expect(moonHistory.first.content, '小月自己的一条消息');
      expect(
        (await database.rawEventsFor(scope: star)).first.content,
        '只属于小星的 Android 原始记录',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
      database = await PersonDatabase.open(databasePath: dbPath);
      final afterRestart = await database.rawEventsFor(scope: star);
      expect(afterRestart.map((event) => event.sequence), [1, 2]);
      expect(afterRestart.first.content, '只属于小星的 Android 原始记录');
      expect(await database.rawEventsFor(scope: moon), hasLength(2));
      expect(await database.mostRecentCharacterForOwner(star.ownerId), moon);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
