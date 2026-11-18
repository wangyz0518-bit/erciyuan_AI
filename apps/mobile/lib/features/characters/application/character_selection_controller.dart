import 'package:flutter/foundation.dart';

import '../domain/character.dart';
import '../domain/character_catalog.dart';

/// In-memory app state. SQLite and durable history belong to Issue #36.
final class CharacterSelectionController extends ChangeNotifier {
  CharacterSelectionController({
    required this.ownerId,
    required CharacterCatalog catalog,
  }) : characters = catalog.listForOwner(ownerId) {
    if (ownerId.trim().isEmpty || characters.isEmpty) {
      throw ArgumentError('Owner must have at least one character.');
    }
    if (characters.any((character) => character.scope.ownerId != ownerId)) {
      throw StateError('Character catalog leaked another owner scope.');
    }
    _activeScope = characters.first.scope;
  }

  final String ownerId;
  final List<Character> characters;
  late PersonScope _activeScope;
  final Map<PersonScope, String> _draftByScope = {};

  PersonScope get activeScope => _activeScope;

  Character get activeCharacter =>
      characters.firstWhere((character) => character.scope == _activeScope);

  String draftFor(PersonScope scope) {
    _requireOwnedCharacter(scope);
    return _draftByScope[scope] ?? '';
  }

  void selectCharacter(PersonScope scope) {
    _requireOwnedCharacter(scope);
    if (scope == _activeScope) return;
    _activeScope = scope;
    notifyListeners();
  }

  /// A late callback from a previous character cannot overwrite the new one.
  void updateDraft(PersonScope scope, String text) {
    _requireOwnedCharacter(scope);
    if (scope != _activeScope) {
      throw StateError('Cannot update the draft of an inactive character.');
    }
    if (_draftByScope[scope] == text) return;
    _draftByScope[scope] = text;
    notifyListeners();
  }

  void _requireOwnedCharacter(PersonScope scope) {
    if (scope.ownerId != ownerId ||
        !characters.any((character) => character.scope == scope)) {
      throw ArgumentError.value(scope, 'scope', 'Unknown character scope');
    }
  }
}
