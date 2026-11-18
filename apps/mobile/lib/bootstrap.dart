import 'app/companion_app.dart';
import 'features/characters/application/character_selection_controller.dart';
import 'features/characters/data/mock_character_catalog.dart';
import 'features/characters/domain/character.dart';

CompanionApp bootstrapCompanionApp() {
  final catalog = MockCharacterCatalog([
    Character(
      scope: const PersonScope(
        ownerId: 'mock-local-owner',
        characterId: 'star',
      ),
      name: '小星',
      description: '温柔而好奇的伙伴（Mock 人物）',
    ),
    Character(
      scope: const PersonScope(
        ownerId: 'mock-local-owner',
        characterId: 'moon',
      ),
      name: '小月',
      description: '善于倾听的伙伴（Mock 人物）',
    ),
  ]);

  return CompanionApp(
    controller: CharacterSelectionController(
      ownerId: 'mock-local-owner',
      catalog: catalog,
    ),
  );
}
