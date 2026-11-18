import 'character.dart';

abstract interface class CharacterCatalog {
  List<Character> listForOwner(String ownerId);
}
