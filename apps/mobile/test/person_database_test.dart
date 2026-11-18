import 'dart:convert';
import 'dart:io';

import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  sqfliteFfiInit();

  const star = PersonScope(ownerId: 'owner-a', characterId: 'star');
  const moon = PersonScope(ownerId: 'owner-a', characterId: 'moon');
  const outsider = PersonScope(ownerId: 'owner-b', characterId: 'star');

  late Directory temp;
  late String databasePath;
  late PersonDatabase store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('erciyuan-sqlite-test-');
    databasePath = path.join(temp.path, 'persons.db');
    store = await PersonDatabase.open(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await store.close();
    await temp.delete(recursive: true);
  });

  Future<void> seed() async {
    await store.createCharacter(
      character: const Character(scope: star, name: '小星', description: 'A'),
      timelineId: 'timeline-star',
    );
    await store.createCharacter(
      character: const Character(scope: moon, name: '小月', description: 'B'),
      timelineId: 'timeline-moon',
    );
    await store.createCharacter(
      character: const Character(
        scope: outsider,
        name: '另一用户的星',
        description: 'X',
      ),
      timelineId: 'timeline-outsider',
    );
  }

  test(
    'one immutable timeline per owner/character, restart recovery',
    () async {
      await seed();
      final first = await store.appendEvent(
        scope: star,
        eventId: 'event-1',
        speaker: 'user',
        content: '你好',
      );
      expect(first.sequence, 1);
      await store.close();
      store = await PersonDatabase.open(
        databasePath: databasePath,
        factory: databaseFactoryFfi,
      );
      expect(await store.timelineIdFor(star), 'timeline-star');
      expect((await store.rawEventsFor(scope: star)).single.content, '你好');
      final second = await store.appendEvent(
        scope: star,
        eventId: 'event-2',
        speaker: 'assistant',
        content: '你好呀',
      );
      expect(second.sequence, 2);
      expect(await store.timelineIdFor(star), 'timeline-star');
    },
  );

  test('scoped reads, paging, and full-owner export never leak data', () async {
    await seed();
    await store.appendEvent(
      scope: star,
      eventId: 'star-one',
      speaker: 'user',
      content: '星专属秘密',
    );
    await store.appendEvent(
      scope: star,
      eventId: 'star-two',
      speaker: 'assistant',
      content: '回复',
    );
    await store.appendEvent(
      scope: moon,
      eventId: 'moon-one',
      speaker: 'user',
      content: '月专属',
    );
    await store.appendEvent(
      scope: outsider,
      eventId: 'foreign',
      speaker: 'user',
      content: '别人的秘密',
    );

    expect(await store.charactersForOwner('owner-a'), hasLength(2));
    final page = await store.rawEventsFor(scope: star, limit: 1);
    expect(page.single.eventId, 'star-one');
    final next = await store.rawEventsFor(
      scope: star,
      afterSequence: page.single.sequence,
    );
    expect(next.single.eventId, 'star-two');
    expect(await store.rawEventsFor(scope: outsider), hasLength(1));
    final exported = jsonDecode(
      await store.exportOwnerJson('owner-a'),
    ) as Map<String, dynamic>;
    expect(exported['schema_version'], 1);
    expect((exported['characters'] as List).length, 2);
    expect((exported['raw_events'] as List).length, 3);
    expect(exported['archive_segments'], isEmpty);
    expect(jsonEncode(exported), isNot(contains('别人的秘密')));
    expect(jsonEncode(exported), contains('星专属秘密'));
  });

  test('failed and cancelled raw events stay out of model context', () async {
    await seed();
    await store.appendEvent(
      scope: star,
      eventId: 'pending',
      speaker: 'user',
      content: 'not complete',
      status: 'cancelled',
    );
    await store.appendEvent(
      scope: star,
      eventId: 'complete',
      speaker: 'user',
      content: 'committed',
    );
    final context = await store.rawEventsFor(scope: star, contextOnly: true);
    expect(context.map((event) => event.eventId), ['complete']);
  });

  test(
    'duplicate event rolls back sequence, duplicate request is idempotent',
    () async {
      await seed();
      await store.appendEvent(
        scope: star,
        eventId: 'one',
        speaker: 'user',
        content: 'first',
      );
      await expectLater(
        store.appendEvent(
          scope: star,
          eventId: 'one',
          speaker: 'user',
          content: 'repeat',
        ),
        throwsA(isA<Exception>()),
      );
      final second = await store.appendEvent(
        scope: star,
        eventId: 'two',
        speaker: 'assistant',
        content: 'second',
      );
      expect(second.sequence, 2);
      expect(
        await store.registerGeneration(scope: star, requestId: 'req'),
        isTrue,
      );
      expect(
        await store.registerGeneration(scope: star, requestId: 'req'),
        isFalse,
      );
      expect(
        await store.registerGeneration(scope: moon, requestId: 'req'),
        isTrue,
      );
      await store.setGenerationStatus(
        scope: star,
        requestId: 'req',
        status: 'cancelled',
      );
    },
  );

  test('failed two-table character creation commits nothing', () async {
    await store.createCharacter(
      character: const Character(scope: star, name: '星', description: 'A'),
      timelineId: 'existing-timeline',
    );
    await expectLater(
      store.createCharacter(
        character: const Character(scope: moon, name: '月', description: 'B'),
        timelineId: 'existing-timeline',
      ),
      throwsA(isA<Exception>()),
    );
    expect(await store.charactersForOwner('owner-a'), hasLength(1));
    expect(await store.timelineIdFor(moon), isNull);
  });

  test('migration from a version-one database preserves characters', () async {
    await store.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE characters (owner_id TEXT NOT NULL, '
            'character_id TEXT NOT NULL, name TEXT NOT NULL, '
            'description TEXT NOT NULL, base_identity_json TEXT NOT NULL, '
            'created_at_utc TEXT NOT NULL, PRIMARY KEY(owner_id, character_id))',
          );
          await db.execute(
            'CREATE TABLE character_timelines (owner_id TEXT NOT NULL, '
            'character_id TEXT NOT NULL, timeline_id TEXT NOT NULL UNIQUE, '
            'next_sequence INTEGER NOT NULL DEFAULT 1, '
            'PRIMARY KEY(owner_id, character_id))',
          );
          await db.execute(
            'CREATE TABLE raw_events (owner_id TEXT NOT NULL, '
            'character_id TEXT NOT NULL, event_id TEXT NOT NULL, '
            'sequence INTEGER NOT NULL, occurred_at_utc TEXT NOT NULL, '
            'speaker TEXT NOT NULL, kind TEXT NOT NULL, content TEXT NOT NULL, '
            'status TEXT NOT NULL, request_id TEXT, revision_of TEXT, '
            'PRIMARY KEY(owner_id, character_id, event_id))',
          );
          await db.insert('characters', {
            'owner_id': 'owner-a',
            'character_id': 'star',
            'name': '旧版星',
            'description': 'legacy',
            'base_identity_json': '{}',
            'created_at_utc': '2026-01-01T00:00:00.000Z',
          });
          await db.insert('character_timelines', {
            'owner_id': 'owner-a',
            'character_id': 'star',
            'timeline_id': 'stable-legacy',
            'next_sequence': 1,
          });
        },
      ),
    );
    await legacy.close();
    store = await PersonDatabase.open(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    expect((await store.charactersForOwner('owner-a')).single.name, '旧版星');
    expect(await store.timelineIdFor(star), 'stable-legacy');
    expect(
      await store.registerGeneration(scope: star, requestId: 'migrated'),
      isTrue,
    );
  });

  test('v3 generation tasks migrate to unknown and completion is atomic/idempotent', () async {
    await store.close();
    await File(databasePath).delete();

    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE characters (
              owner_id TEXT NOT NULL,
              character_id TEXT NOT NULL,
              PRIMARY KEY (owner_id, character_id)
            )
          ''');
          await database.execute('''
            CREATE TABLE character_timelines (
              owner_id TEXT NOT NULL,
              character_id TEXT NOT NULL,
              timeline_id TEXT NOT NULL UNIQUE,
              next_sequence INTEGER NOT NULL DEFAULT 1,
              PRIMARY KEY (owner_id, character_id),
              FOREIGN KEY (owner_id, character_id)
                REFERENCES characters(owner_id, character_id) ON DELETE CASCADE
            )
          ''');
          await database.execute('''
            CREATE TABLE raw_events (
              owner_id TEXT NOT NULL,
              character_id TEXT NOT NULL,
              event_id TEXT NOT NULL,
              sequence INTEGER NOT NULL,
              occurred_at_utc TEXT NOT NULL,
              speaker TEXT NOT NULL,
              kind TEXT NOT NULL,
              content TEXT NOT NULL,
              status TEXT NOT NULL,
              request_id TEXT,
              revision_of TEXT,
              PRIMARY KEY (owner_id, character_id, event_id),
              UNIQUE (owner_id, character_id, sequence),
              FOREIGN KEY (owner_id, character_id)
                REFERENCES character_timelines(owner_id, character_id) ON DELETE CASCADE
            )
          ''');
          await database.execute('''
            CREATE TABLE generation_tasks (
              owner_id TEXT NOT NULL,
              character_id TEXT NOT NULL,
              request_id TEXT NOT NULL,
              status TEXT NOT NULL CHECK(status IN ('pending','complete','failed','cancelled')),
              retry_of TEXT,
              started_at_utc TEXT NOT NULL,
              PRIMARY KEY (owner_id, character_id, request_id),
              FOREIGN KEY (owner_id, character_id)
                REFERENCES character_timelines(owner_id, character_id) ON DELETE CASCADE
            )
          ''');
          await database.insert('characters', {
            'owner_id': star.ownerId,
            'character_id': star.characterId,
          });
          await database.insert('character_timelines', {
            'owner_id': star.ownerId,
            'character_id': star.characterId,
            'timeline_id': 'timeline-star',
            'next_sequence': 1,
          });
          await database.insert('generation_tasks', {
            'owner_id': star.ownerId,
            'character_id': star.characterId,
            'request_id': 'request-migration-0001',
            'status': 'pending',
            'retry_of': null,
            'started_at_utc': DateTime.now().toUtc().toIso8601String(),
          });
        },
      ),
    );
    await legacy.close();

    store = await PersonDatabase.open(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    await store.setGenerationStatus(
      scope: star,
      requestId: 'request-migration-0001',
      status: 'unknown',
    );
    final saved = await store.completeGeneration(
      scope: star,
      requestId: 'request-migration-0001',
      eventId: 'assistant-request-migration-0001',
      content: 'confirmed after status reconciliation',
    );
    final repeated = await store.completeGeneration(
      scope: star,
      requestId: 'request-migration-0001',
      eventId: 'assistant-request-migration-0001',
      content: 'confirmed after status reconciliation',
    );

    expect(saved.sequence, 1);
    expect(repeated.eventId, saved.eventId);
    expect(
      (await store.rawEventsFor(scope: star)).where(
        (event) => event.speaker == 'assistant',
      ),
      hasLength(1),
    );
  });

}
