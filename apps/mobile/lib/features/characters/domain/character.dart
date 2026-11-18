class PersonScope {
  const PersonScope({required this.ownerId, required this.characterId});

  final String ownerId;
  final String characterId;

  @override
  bool operator ==(Object other) =>
      other is PersonScope &&
      other.ownerId == ownerId &&
      other.characterId == characterId;

  @override
  int get hashCode => Object.hash(ownerId, characterId);
}

class Character {
  const Character({
    required this.scope,
    required this.name,
    required this.description,
  });

  final PersonScope scope;
  final String name;
  final String description;
}
