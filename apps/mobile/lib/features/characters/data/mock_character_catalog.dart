import '../domain/character.dart';
import '../domain/character_catalog.dart';

/// Test-only fixture. Not a database and never generates an AI reply.
final class MockCharacterCatalog implements CharacterCatalog {
  MockCharacterCatalog(List<Character> characters)
    : _characters = List.unmodifiable(characters);

  final List<Character> _characters;

  @override
  List<Character> listForOwner(String ownerId) => List.unmodifiable(
    _characters.where((character) => character.scope.ownerId == ownerId),
  );
}
