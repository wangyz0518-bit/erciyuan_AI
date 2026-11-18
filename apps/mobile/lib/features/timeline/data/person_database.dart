import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

import '../../characters/domain/character.dart';
import '../../memory/data/person_memory_repository.dart';
import '../../memory/domain/memory_models.dart';
import '../domain/raw_event.dart';

/// SQLite fact repository. All operations are scoped by owner + character.
/// Account verification is NOT implemented by a local owner ID (#38).
final class PersonDatabase {
  PersonDatabase._(this._db, this._automaticSummarizer);

  static const int schemaVersion = 3;
  final Database _db;
  final MemorySummarizer? _automaticSummarizer;
  Object? _lastArchiveError;

  /// A failed summary never rolls back already committed raw events.
  /// The app can display or log this error and call memory.archiveReady again.
  Object? get lastArchiveError => _lastArchiveError;

  /// Memory shares the same SQLite connection and atomic fact transactions.
  PersonMemoryRepository get memory => PersonMemoryRepository(_db);

  static Future<PersonDatabase> open({
    DatabaseFactory? factory,
    String? databasePath,
    MemorySummarizer? automaticSummarizer,
  }) async {
    final selectedFactory = factory ?? sqflite.databaseFactory;
    final location =
        databasePath ??
        path.join(await sqflite.getDatabasesPath(), 'erciyuan-persons.db');
    final db = await selectedFactory.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await _createVersionOne(database);
          await _createGenerationTasks(database);
          await PersonMemoryRepository.createSchema(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createGenerationTasks(database);
          if (oldVersion < 3) {
            await PersonMemoryRepository.createSchema(database);
          }
        },
      ),
    );
    return PersonDatabase._(db, automaticSummarizer);
  }

  static Future<void> _createVersionOne(Database db) async {
    await db.execute('''
      CREATE TABLE characters (
        owner_id TEXT NOT NULL,
        character_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        base_identity_json TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        PRIMARY KEY (owner_id, character_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE character_timelines (
        owner_id TEXT NOT NULL,
        character_id TEXT NOT NULL,
        timeline_id TEXT NOT NULL UNIQUE,
        next_sequence INTEGER NOT NULL DEFAULT 1 CHECK(next_sequence >= 1),
        PRIMARY KEY (owner_id, character_id),
        FOREIGN KEY (owner_id, character_id)
          REFERENCES characters(owner_id, character_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE raw_events (
        owner_id TEXT NOT NULL,
        character_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        sequence INTEGER NOT NULL CHECK(sequence >= 1),
        occurred_at_utc TEXT NOT NULL,
        speaker TEXT NOT NULL,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('complete','pending','failed','cancelled','redacted')),
        request_id TEXT,
        revision_of TEXT,
        PRIMARY KEY (owner_id, character_id, event_id),
        UNIQUE (owner_id, character_id, sequence),
        FOREIGN KEY (owner_id, character_id)
          REFERENCES character_timelines(owner_id, character_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_raw_event_sequence
        ON raw_events(owner_id, character_id, sequence)
    ''');
  }

  static Future<void> _createGenerationTasks(Database db) async {
    await db.execute('''
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
  }

  static void _validateScope(PersonScope scope) {
    if (scope.ownerId.trim().isEmpty || scope.characterId.trim().isEmpty) {
      throw ArgumentError.value(scope, 'scope', 'Owner and character required');
    }
  }

  static void _requireValue(String value, String field) {
    if (value.trim().isEmpty) throw ArgumentError.value(value, field);
  }

  static List<Object?> _args(PersonScope scope) => [
    scope.ownerId,
    scope.characterId,
  ];

  Future<void> createCharacter({
    required Character character,
    required String timelineId,
    String baseIdentityJson = '{}',
  }) async {
    _validateScope(character.scope);
    _requireValue(timelineId, 'timelineId');
    _requireValue(character.name, 'name');
    jsonDecode(baseIdentityJson);
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('characters', {
        'owner_id': character.scope.ownerId,
        'character_id': character.scope.characterId,
        'name': character.name,
        'description': character.description,
        'base_identity_json': baseIdentityJson,
        'created_at_utc': now,
      });
      await txn.insert('character_timelines', {
        'owner_id': character.scope.ownerId,
        'character_id': character.scope.characterId,
        'timeline_id': timelineId,
        'next_sequence': 1,
      });
    });
  }

  Future<List<Character>> charactersForOwner(String ownerId) async {
    _requireValue(ownerId, 'ownerId');
    final rows = await _db.query(
      'characters',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'created_at_utc ASC, character_id ASC',
    );
    return List.unmodifiable(
      rows.map(
        (row) => Character(
          scope: PersonScope(
            ownerId: row['owner_id']! as String,
            characterId: row['character_id']! as String,
          ),
          name: row['name']! as String,
          description: row['description']! as String,
        ),
      ),
    );
  }

  Future<String?> timelineIdFor(PersonScope scope) async {
    _validateScope(scope);
    final rows = await _db.query(
      'character_timelines',
      columns: ['timeline_id'],
      where: 'owner_id = ? AND character_id = ?',
      whereArgs: _args(scope),
    );
    return rows.isEmpty ? null : rows.single['timeline_id'] as String;
  }

  /// Appends one raw event and advances sequence in the SAME transaction.
  Future<RawEvent> appendEvent({
    required PersonScope scope,
    required String eventId,
    required String speaker,
    required String content,
    String kind = 'message',
    String status = 'complete',
    String? requestId,
    String? revisionOf,
    DateTime? occurredAt,
  }) async {
    _validateScope(scope);
    _requireValue(eventId, 'eventId');
    _requireValue(speaker, 'speaker');
    if (!const [
      'complete',
      'pending',
      'failed',
      'cancelled',
      'redacted',
    ].contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final timestamp = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    final saved = await _db.transaction((txn) async {
      final timelines = await txn.query(
        'character_timelines',
        columns: ['next_sequence'],
        where: 'owner_id = ? AND character_id = ?',
        whereArgs: _args(scope),
      );
      if (timelines.isEmpty) throw StateError('Character timeline is missing');
      final sequence = timelines.single['next_sequence']! as int;
      await txn.insert('raw_events', {
        'owner_id': scope.ownerId,
        'character_id': scope.characterId,
        'event_id': eventId,
        'sequence': sequence,
        'occurred_at_utc': timestamp,
        'speaker': speaker,
        'kind': kind,
        'content': content,
        'status': status,
        'request_id': requestId,
        'revision_of': revisionOf,
      });
      final changed = await txn.update(
        'character_timelines',
        {'next_sequence': sequence + 1},
        where: 'owner_id = ? AND character_id = ? AND next_sequence = ?',
        whereArgs: [..._args(scope), sequence],
      );
      if (changed != 1) throw StateError('Sequence advance conflict');
      if (revisionOf != null && status == 'complete') {
        final source = await txn.query(
          'raw_events',
          columns: ['event_id'],
          where: "owner_id = ? AND character_id = ? AND event_id = ? AND status = 'complete'",
          whereArgs: [..._args(scope), revisionOf],
        );
        if (source.isEmpty) throw StateError('Revision source not found');
        await PersonMemoryRepository.invalidateSourceInTransaction(
          txn, scope, revisionOf,
        );
      }
      return RawEvent(
        scope: scope,
        eventId: eventId,
        sequence: sequence,
        occurredAtUtc: timestamp,
        speaker: speaker,
        kind: kind,
        content: content,
        status: status,
        requestId: requestId,
        revisionOf: revisionOf,
      );
    });
    if (status == 'complete' && _automaticSummarizer != null) {
      try {
        await memory.archiveReady(
          scope: scope,
          summarizer: _automaticSummarizer,
        );
        _lastArchiveError = null;
      } catch (error) {
        // RawEvent has committed; retry later from the unchanged archive cursor.
        _lastArchiveError = error;
      }
    }
    return saved;
  }

  Future<List<RawEvent>> rawEventsFor({
    required PersonScope scope,
    int afterSequence = 0,
    int limit = 100,
    bool contextOnly = false,
  }) async {
    _validateScope(scope);
    if (afterSequence < 0 || limit < 1 || limit > 1000) {
      throw ArgumentError('Invalid pagination');
    }
    final contextFilter = contextOnly ? " AND status = 'complete'" : '';
    final rows = await _db.query(
      'raw_events',
      where: 'owner_id = ? AND character_id = ? AND sequence > ?$contextFilter',
      whereArgs: [..._args(scope), afterSequence],
      orderBy: 'sequence ASC',
      limit: limit,
    );
    return List.unmodifiable(rows.map(_rawEvent));
  }

  static RawEvent _rawEvent(Map<String, Object?> row) => RawEvent(
    scope: PersonScope(
      ownerId: row['owner_id']! as String,
      characterId: row['character_id']! as String,
    ),
    eventId: row['event_id']! as String,
    sequence: row['sequence']! as int,
    occurredAtUtc: row['occurred_at_utc']! as String,
    speaker: row['speaker']! as String,
    kind: row['kind']! as String,
    content: row['content']! as String,
    status: row['status']! as String,
    requestId: row['request_id'] as String?,
    revisionOf: row['revision_of'] as String?,
  );

  /// Repeating a request ID cannot create an extra generation task.
  Future<bool> registerGeneration({
    required PersonScope scope,
    required String requestId,
    String? retryOf,
  }) async {
    _validateScope(scope);
    _requireValue(requestId, 'requestId');
    final result = await _db.insert('generation_tasks', {
      'owner_id': scope.ownerId,
      'character_id': scope.characterId,
      'request_id': requestId,
      'status': 'pending',
      'retry_of': retryOf,
      'started_at_utc': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return result != 0;
  }

  Future<void> setGenerationStatus({
    required PersonScope scope,
    required String requestId,
    required String status,
  }) async {
    _validateScope(scope);
    if (!const [
      'pending',
      'complete',
      'failed',
      'cancelled',
    ].contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final changed = await _db.update(
      'generation_tasks',
      {'status': status},
      where: 'owner_id = ? AND character_id = ? AND request_id = ?',
      whereArgs: [..._args(scope), requestId],
    );
    if (changed != 1) throw StateError('Generation task not found');
  }

  /// Explicit privacy redaction: keep an event's stable ID and sequence but
  /// remove its personal content and invalidate all derived summaries.
  Future<void> redactEvent({
    required PersonScope scope,
    required String eventId,
  }) async {
    _validateScope(scope);
    _requireValue(eventId, 'eventId');
    await _db.transaction((txn) async {
      final changed = await txn.update(
        'raw_events',
        {'content': '', 'status': 'redacted'},
        where: "owner_id = ? AND character_id = ? AND event_id = ? AND status = 'complete'",
        whereArgs: [..._args(scope), eventId],
      );
      if (changed != 1) throw StateError('Redactable event not found');
      await PersonMemoryRepository.invalidateSourceInTransaction(
        txn, scope, eventId, purgeContent: true,
      );
    });
  }

  /// Versioned, vendor-independent, transaction-consistent JSON for ALL
  /// characters belonging to ONE owner. The app's file-sharing UI is #37.
  Future<String> exportOwnerJson(String ownerId) async {
    _requireValue(ownerId, 'ownerId');
    return _db.transaction((txn) async {
      Future<List<Map<String, Object?>>> read(
        String table, String order,
      ) => txn.query(
        table,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
        orderBy: order,
      );
      return const JsonEncoder.withIndent('  ').convert({
        'format': 'erciyuan-person-memory-export',
        'schema_version': 1,
        'database_schema_version': schemaVersion,
        'owner_id': ownerId,
        'characters': await read('characters', 'character_id ASC'),
        'character_timelines':
            await read('character_timelines', 'character_id ASC'),
        'raw_events':
            await read('raw_events', 'character_id ASC, sequence ASC'),
        'generation_tasks':
            await read('generation_tasks', 'character_id ASC, request_id ASC'),
        'archive_segments':
            await read('archive_segments', 'character_id ASC, sequence_from ASC'),
        'archive_cursors':
            await read('archive_cursors', 'character_id ASC, generator_version ASC'),
        'memory_summaries':
            await read('memory_summaries', 'character_id ASC, summary_id ASC'),
        'memory_terms':
            await read('memory_terms', 'character_id ASC, summary_id ASC, term ASC'),
        'summary_sources':
            await read('summary_sources', 'character_id ASC, summary_id ASC, event_id ASC'),
        'persona_identity_versions':
            await read('persona_identity_versions', 'character_id ASC, version ASC'),
        'identity_candidates':
            await read('identity_candidates', 'character_id ASC, candidate_id ASC'),
        'attachments': <Object>[],
      });
    });
  }

  Future<void> close() => _db.close();
}
