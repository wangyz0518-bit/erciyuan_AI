import 'dart:io';

import 'package:erciyuan_mobile/app/companion_app.dart';
import 'package:erciyuan_mobile/features/characters/application/character_selection_controller.dart';
import 'package:erciyuan_mobile/features/characters/data/mock_character_catalog.dart';
import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  const star = PersonScope(ownerId: 'local', characterId: 'a');
  const moon = PersonScope(ownerId: 'local', characterId: 'b');

  late Directory temp;
  late PersonDatabase database;
  late CharacterSelectionController selection;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('erciyuan-chat-widget-');
    database = await PersonDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: path.join(temp.path, 'people.db'),
    );
    await database.createCharacter(
      character: const Character(
        scope: star,
        name: '小星',
        description: '本地人物 A',
      ),
      timelineId: 'timeline-star',
    );
    await database.createCharacter(
      character: const Character(
        scope: moon,
        name: '小月',
        description: '本地人物 B',
      ),
      timelineId: 'timeline-moon',
    );
    selection = CharacterSelectionController(
      ownerId: 'local',
      catalog: MockCharacterCatalog(const [
        Character(scope: star, name: '小星', description: '本地人物 A'),
        Character(scope: moon, name: '小月', description: '本地人物 B'),
      ]),
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      CompanionApp(
        controller: selection,
        database: database,
        closeDatabaseOnDispose: false,
      ),
    );
  }

  testWidgets('people-first navigation has no multiple-session controls', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('人物主页'), findsOneWidget);
    expect(find.text('新建会话'), findsNothing);
    expect(find.byKey(const ValueKey('continue-timeline')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('continue-timeline')));
    await tester.pumpAndSettle();
    expect(find.text('唯一持续时间线'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-mode')), findsOneWidget);
  });

  testWidgets('mock send persists and character switch isolates messages', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('continue-timeline')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('character-draft')),
      '仅属于小星',
    );
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      (await database.rawEventsFor(scope: star)).map((event) => event.speaker),
      ['user', 'assistant'],
    );
    expect(find.textContaining('离线 Mock'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('chat-switch-character')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小月').last);
    await tester.pumpAndSettle();
    expect(find.text('仅属于小星'), findsNothing);
    expect(await database.rawEventsFor(scope: moon), isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('character-draft')),
      '月的草稿',
    );
    expect(selection.draftFor(moon), '月的草稿');
    expect(selection.draftFor(star), isEmpty);
  });

  testWidgets('my/data entry exports all owner data through real SQLite', (
    tester,
  ) async {
    await database.appendEvent(
      scope: star,
      eventId: 'user-before-export',
      speaker: 'user',
      content: '私有测试记录',
    );
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('data-management')));
    await tester.pumpAndSettle();
    expect(find.text('导出全部人物数据'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-all-person-data')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-summary')), findsOneWidget);
    expect(find.textContaining('原始记录：1'), findsOneWidget);
  });
}
