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

/// Render actual Flutter Widget screens on CI, not a manually drawn mockup.
/// Run: flutter test --update-goldens test_screenshots/official_ui_preview_test.dart
void main() {
  sqfliteFfiInit();

  testWidgets('capture home, durable chat, and export page at 375x812', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final directory = await Directory.systemTemp.createTemp('ui-gallery-');
    final db = await PersonDatabase.open(
      databasePath: path.join(directory.path, 'gallery.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });

    const star = PersonScope(ownerId: 'preview', characterId: 'star');
    const moon = PersonScope(ownerId: 'preview', characterId: 'moon');
    for (final character in const [
      Character(scope: star, name: '小星', description: '温柔而好奇的伙伴'),
      Character(scope: moon, name: '小月', description: '善于倾听的伙伴'),
    ]) {
      await db.createCharacter(
        character: character,
        timelineId: 'preview-${character.scope.characterId}',
      );
    }
    await db.appendEvent(
      scope: star,
      eventId: 'preview-user',
      speaker: 'user',
      content: '今天的星空很好看。',
    );
    await db.appendEvent(
      scope: star,
      eventId: 'preview-assistant',
      speaker: 'assistant',
      content: '【离线 Mock】小星：我也想听听你看到的星空。',
    );
    final selection = CharacterSelectionController(
      ownerId: 'preview',
      catalog: MockCharacterCatalog(const [
        Character(scope: star, name: '小星', description: '温柔而好奇的伙伴'),
        Character(scope: moon, name: '小月', description: '善于倾听的伙伴'),
      ]),
    );
    await tester.pumpWidget(
      CompanionApp(
        controller: selection,
        database: db,
        closeDatabaseOnDispose: false,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/people-home-375.png'),
    );

    await tester.tap(find.byKey(const ValueKey('continue-timeline')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/continuous-chat-375.png'),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('data-management')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/data-management-375.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
