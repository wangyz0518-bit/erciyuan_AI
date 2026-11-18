import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Native Android SQLite failure/recovery checks for the official schema.
/// Failed transactions must not create orphan events or skip sequence numbers.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const star = PersonScope(ownerId: 'integration-owner', characterId: 'star');
  const moon = PersonScope(ownerId: 'integration-owner', characterId: 'moon');
  const other = PersonScope(ownerId: 'other-owner', characterId: 'star');

  late String dbPath;
  late PersonDatabase database;

  setUp(() async {
    dbPath = path.join(
      await getDatabasesPath(),
      'official-failure-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    database = await PersonDatabase.open(databasePath: dbPath);
  });

  tearDown(() async {
    await database.close();
    await deleteDatabase(dbPath);
  });

  testWidgets(
    'missing character rejects event; after repair first sequence is one',
    (tester) async {
      await expectLater(
        database.appendEvent(
          scope: star,
          eventId: 'first-event',
          speaker: 'user',
          content: '第一次失败的写入',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await database.rawEventsFor(scope: star), isEmpty);
      await database.createCharacter(
        character: const Character(scope: star, name: '小星', description: 'A'),
        timelineId: 'star-timeline',
      );
      final saved = await database.appendEvent(
        scope: star,
        eventId: 'first-event',
        speaker: 'user',
        content: '重新写入成功',
      );
      expect(saved.sequence, 1);
      expect(
        (await database.rawEventsFor(scope: star)).single.content,
        '重新写入成功',
      );
    },
  );

  testWidgets(
    'duplicate character creation rolls back without partial timeline',
    (tester) async {
      await database.createCharacter(
        character: const Character(scope: star, name: '小星', description: 'A'),
        timelineId: 'unique-timeline',
      );
      await expectLater(
        database.createCharacter(
          character: const Character(scope: moon, name: '小月', description: 'B'),
          timelineId: 'unique-timeline',
        ),
        throwsA(isA<Exception>()),
      );
      expect(await database.timelineIdFor(moon), isNull);
      expect(await database.charactersForOwner(star.ownerId), hasLength(1));
      await database.createCharacter(
        character: const Character(scope: moon, name: '小月', description: 'B'),
        timelineId: 'moon-timeline',
      );
      expect(await database.charactersForOwner(star.ownerId), hasLength(2));
    },
  );

  testWidgets('duplicate raw fact never advances sequence or leaks scope', (
    tester,
  ) async {
    for (final character in const [
      Character(scope: star, name: '小星', description: 'A'),
      Character(scope: other, name: '外部星', description: 'X'),
    ]) {
      await database.createCharacter(
        character: character,
        timelineId: 'timeline-${character.scope.ownerId}',
      );
    }
    final first = await database.appendEvent(
      scope: star,
      eventId: 'fixed-id',
      speaker: 'user',
      content: '唯一事实',
    );
    expect(first.sequence, 1);
    await expectLater(
      database.appendEvent(
        scope: star,
        eventId: 'fixed-id',
        speaker: 'user',
        content: '重试不应重复',
      ),
      throwsA(isA<Exception>()),
    );
    final second = await database.appendEvent(
      scope: star,
      eventId: 'next-id',
      speaker: 'user',
      content: '下一个事实',
    );
    expect(second.sequence, 2);
    expect(await database.rawEventsFor(scope: star), hasLength(2));
    expect(await database.rawEventsFor(scope: other), isEmpty);
    expect(await database.charactersForOwner(other.ownerId), hasLength(1));
  });
}
