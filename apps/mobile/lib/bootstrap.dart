import 'app/companion_app.dart';
import 'features/characters/application/character_selection_controller.dart';
import 'features/characters/domain/character.dart';
import 'features/characters/domain/character_catalog.dart';
import 'features/chat/data/model_gateway_adapter.dart';
import 'features/memory/domain/memory_models.dart';
import 'features/timeline/data/person_database.dart';

/// Local-only owner. This is NOT an authenticated account identity.
const localOwnerId = 'local-device-owner-v1';

/// Opens the actual SQLite store. Demo characters are inserted once and then
/// loaded from the database rather than recreated for each app launch.
Future<CompanionApp> bootstrapCompanionApp({
  String ownerId = localOwnerId,
  PersonDatabase? database,
  Uri? gatewayUri,
  String? gatewayToken,
}) async {
  final store =
      database ??
      await PersonDatabase.open(
        automaticSummarizer: const DeterministicSummarizer(),
      );
  var characters = await store.charactersForOwner(ownerId);
  if (characters.isEmpty) {
    final starterCharacters = [
      Character(
        scope: PersonScope(ownerId: ownerId, characterId: 'star'),
        name: '小星',
        description: '温柔而好奇的伙伴',
      ),
      Character(
        scope: PersonScope(ownerId: ownerId, characterId: 'moon'),
        name: '小月',
        description: '善于倾听的伙伴',
      ),
    ];
    for (final character in starterCharacters) {
      await store.createCharacter(
        character: character,
        timelineId: 'timeline-$ownerId-${character.scope.characterId}',
        baseIdentityJson: '{"source":"local-starter-character","version":1}',
      );
    }
    characters = await store.charactersForOwner(ownerId);
  }

  if ((gatewayUri == null) != (gatewayToken == null)) {
    throw ArgumentError('Gateway URI and development token must be paired');
  }
  final gateway = gatewayUri == null
      ? null
      : ModelGatewayAdapter(
          baseUri: gatewayUri,
          accessToken: gatewayToken!,
          database: store,
        );

  return CompanionApp(
    database: store,
    gateway: gateway,
    controller: CharacterSelectionController(
      ownerId: ownerId,
      catalog: _DatabaseCharacterCatalog(characters),
    ),
  );
}

final class _DatabaseCharacterCatalog implements CharacterCatalog {
  const _DatabaseCharacterCatalog(this.characters);

  final List<Character> characters;

  @override
  List<Character> listForOwner(String ownerId) => List.unmodifiable(
    characters.where((character) => character.scope.ownerId == ownerId),
  );
}
