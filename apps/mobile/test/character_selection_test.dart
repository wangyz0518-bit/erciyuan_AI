import 'package:erciyuan_mobile/features/characters/application/character_selection_controller.dart';
import 'package:erciyuan_mobile/features/characters/data/mock_character_catalog.dart';
import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const star = PersonScope(ownerId: 'owner-a', characterId: 'star');
  const moon = PersonScope(ownerId: 'owner-a', characterId: 'moon');
  const foreign = PersonScope(ownerId: 'owner-b', characterId: 'star');

  CharacterSelectionController buildController() =>
      CharacterSelectionController(
        ownerId: 'owner-a',
        catalog: MockCharacterCatalog([
          const Character(scope: star, name: '星', description: 'A'),
          const Character(scope: moon, name: '月', description: 'B'),
          const Character(scope: foreign, name: '另一用户', description: 'C'),
        ]),
      );

  test('scope is stable and owner-aware', () {
    expect(star, const PersonScope(ownerId: 'owner-a', characterId: 'star'));
    expect(star, isNot(foreign));
  });

  test('switching characters never shares an in-memory draft', () {
    final controller = buildController();
    addTearDown(controller.dispose);

    expect(controller.characters, hasLength(2));
    controller.updateDraft(star, '星的草稿');
    controller.selectCharacter(moon);
    expect(controller.draftFor(moon), isEmpty);
    controller.updateDraft(moon, '月的草稿');
    controller.selectCharacter(star);
    expect(controller.draftFor(star), '星的草稿');
    expect(controller.draftFor(moon), '月的草稿');
  });

  test('rejects cross-owner scope and stale character writes', () {
    final controller = buildController();
    addTearDown(controller.dispose);

    expect(() => controller.selectCharacter(foreign), throwsArgumentError);
    expect(() => controller.draftFor(foreign), throwsArgumentError);
    controller.selectCharacter(moon);
    expect(() => controller.updateDraft(star, 'late'), throwsStateError);
    expect(controller.draftFor(star), isEmpty);
  });

  test('rejects a catalog without characters', () {
    expect(
      () => CharacterSelectionController(
        ownerId: 'owner-b',
        catalog: MockCharacterCatalog(const []),
      ),
      throwsArgumentError,
    );
  });
}
