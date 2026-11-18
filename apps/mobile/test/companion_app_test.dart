import 'package:erciyuan_mobile/app/companion_app.dart';
import 'package:erciyuan_mobile/features/characters/application/character_selection_controller.dart';
import 'package:erciyuan_mobile/features/characters/data/mock_character_catalog.dart';
import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home always enters one continuous timeline per character', (
    tester,
  ) async {
    final controller = CharacterSelectionController(
      ownerId: 'local',
      catalog: MockCharacterCatalog(const [
        Character(
          scope: PersonScope(ownerId: 'local', characterId: 'a'),
          name: '小星',
          description: 'Mock A',
        ),
        Character(
          scope: PersonScope(ownerId: 'local', characterId: 'b'),
          name: '小月',
          description: 'Mock B',
        ),
      ]),
    );

    await tester.pumpWidget(CompanionApp(controller: controller));
    expect(find.text('人物主页（Mock）'), findsOneWidget);
    expect(find.text('新建会话'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('continue-timeline')));
    await tester.pumpAndSettle();
    expect(find.text('持续对话（Mock）'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('character-draft')),
      'A 的草稿',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('character-b')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('continue-timeline')));
    await tester.pumpAndSettle();

    expect(find.text('A 的草稿'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('character-draft')),
      'B 的草稿',
    );
    expect(
      controller.draftFor(
        const PersonScope(ownerId: 'local', characterId: 'a'),
      ),
      'A 的草稿',
    );
    expect(
      controller.draftFor(
        const PersonScope(ownerId: 'local', characterId: 'b'),
      ),
      'B 的草稿',
    );
  });
}
