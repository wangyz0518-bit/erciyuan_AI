import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../characters/domain/character.dart';
import '../../timeline/domain/raw_event.dart';
import '../domain/memory_models.dart';

/// SQLite-derived memory. All SQL operations carry BOTH ownership keys.
final class PersonMemoryRepository {
  const PersonMemoryRepository(this._db);

  final Database _db;
  static const String promptVersion = 'person-prefix-v1';

  static List<Object?> _scope(PersonScope scope) {
    if (scope.ownerId.trim().isEmpty || scope.characterId.trim().isEmpty) {
      throw ArgumentError('Owner and character are required');
    }
    return [scope.ownerId, scope.characterId];
  }

  static Future<void> createSchema(Database db) async {
    for (final ddl in <String>[
      '''
      CREATE TABLE archive_segments (
        owner_id TEXT NOT NULL, character_id TEXT NOT NULL,
        archive_id TEXT NOT NULL,
        sequence_from INTEGER NOT NULL, sequence_to INTEGER NOT NULL,
        source_digest TEXT NOT NULL, generator_version TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        PRIMARY KEY(owner_id, character_id, archive_id),
        UNIQUE(owner_id, character_id, sequence_from, sequence_to,
               source_digest, generator_version),
        FOREIGN KEY(owner_id, character_id)
          REFERENCES character_timelines(owner_id, character_id) ON DELETE CASCADE,
        CHECK(sequence_from > 0 AND sequence_to >= sequence_from)
      )
      ''',
      '''
      CREATE TABLE memory_summaries (
        owner_id TEXT NOT NULL, character_id TEXT NOT NULL,
        summary_id TEXT NOT NULL, archive_id TEXT NOT NULL,
        summary TEXT NOT NULL, confidence REAL NOT NULL,
        generator_version TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('active', 'invalidated')),
        created_at_utc TEXT NOT NULL,
        PRIMARY KEY(owner_id, character_id, summary_id),
        FOREIGN KEY(owner_id, character_id, archive_id)
          REFERENCES archive_segments(owner_id, character_id, archive_id)
          ON DELETE CASCADE
      )
      ''',
      '''
      CREATE TABLE summary_sources (
        owner_id TEXT NOT NULL, character_id TEXT NOT NULL,
        summary_id TEXT NOT NULL, event_id TEXT NOT NULL,
        PRIMARY KEY(owner_id, character_id, summary_id, event_id),
        FOREIGN KEY(owner_id, character_id, summary_id)
          REFERENCES memory_summaries(owner_id, character_id, summary_id)
          ON DELETE CASCADE,
        FOREIGN KEY(owner_id, character_id, event_id)
          REFERENCES raw_events(owner_id, character_id, event_id)
      )
      ''',
      '''
      CREATE TABLE memory_terms (
        owner_id TEXT NOT NULL, character_id TEXT NOT NULL,
        summary_id TEXT NOT NULL, term TEXT NOT NULL,
        PRIMARY KEY(owner_id, character_id, summary_id, term),
        FOREIGN KEY(owner_id, character_id, summary_id)
          REFERENCES memory_summaries(owner_id, character_id, summary_id)
          ON DELETE CASCADE
      )
      ''',
      '''
      CREATE TABLE archive_cursors (
        owner_id TEXT NOT NULL, character_id TEXT NOT NULL,
        generator_version TEXT NOT NULL,
        last_committed_sequence INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(owner_id, character_id, generator_version),
        FOREIGN KEY(owner_id, character_id)
          REFERENCES character_timelines(owner_id, character_id) ON DELETE CASCADE
      )
      ''',
      '''
      CREATE TABLE persona_identity_versions (
        owner_id TEXT NOT NULL, character_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        base_identity_json TEXT NOT NULL,
        stable_state_json TEXT NOT NULL,
        source_summary_ids_json TEXT NOT NULL,
        approved_by TEXT NOT NULL, created_at_utc TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('active', 'invalidated')),
        PRIMARY KEY(owner_id, character_id, version),
        FOREIGN KEY(owner_id, character_id)
          REFERENCES character_timelines(owner_id, character_id) ON DELETE CASCADE
      )
      ''',
      '''
      CREATE TABLE identity_candidates (
        owner_id TEXT NOT NULL, character_id TEXT NOT NULL,
        candidate_id TEXT NOT NULL, proposed_json TEXT NOT NULL,
        source_summary_ids_json TEXT NOT NULL,
        confidence REAL NOT NULL,
        status TEXT NOT NULL
          CHECK(status IN ('proposed', 'approved', 'rejected', 'invalidated')),
        created_at_utc TEXT NOT NULL,
        PRIMARY KEY(owner_id, character_id, candidate_id),
        FOREIGN KEY(owner_id, character_id)
          REFERENCES character_timelines(owner_id, character_id) ON DELETE CASCADE
      )
      ''',
      'CREATE INDEX idx_memory_terms ON memory_terms(owner_id, character_id, term)',
      'CREATE INDEX idx_memory_source ON summary_sources(owner_id, character_id, event_id)',
      'CREATE INDEX idx_memory_status ON memory_summaries(owner_id, character_id, status)',
    ]) {
      await db.execute(ddl);
    }
  }

  static RawEvent _event(Map<String, Object?> row) => RawEvent(
    scope: PersonScope(
      ownerId: row['owner_id'] as String,
      characterId: row['character_id'] as String,
    ),
    eventId: row['event_id'] as String,
    sequence: row['sequence'] as int,
    occurredAtUtc: row['occurred_at_utc'] as String,
    speaker: row['speaker'] as String,
    kind: row['kind'] as String,
    content: row['content'] as String,
    status: row['status'] as String,
    requestId: row['request_id'] as String?,
    revisionOf: row['revision_of'] as String?,
  );

  static Future<List<RawEvent>> _eligibleEvents(
    DatabaseExecutor db,
    PersonScope scope,
    int after,
    int limit,
  ) async {
    // A completed correction supersedes the earlier event in new contexts.
    final rows = await db.rawQuery(
      '''
      SELECT e.* FROM raw_events e
      WHERE e.owner_id = ? AND e.character_id = ?
        AND e.sequence > ? AND e.status = 'complete'
        AND NOT EXISTS (
          SELECT 1 FROM raw_events revision
          WHERE revision.owner_id = e.owner_id
            AND revision.character_id = e.character_id
            AND revision.revision_of = e.event_id
            AND revision.status = 'complete'
        )
      ORDER BY e.sequence ASC LIMIT ?
    ''',
      [..._scope(scope), after, limit],
    );
    return rows.map(_event).toList(growable: false);
  }

  static String _digest(
    PersonScope scope,
    String version,
    List<RawEvent> events,
  ) {
    final bytes = utf8.encode(
      jsonEncode([
        scope.ownerId,
        scope.characterId,
        version,
        for (final e in events)
          [e.eventId, e.sequence, e.content, e.speaker, e.status, e.revisionOf],
      ]),
    );
    return sha256.convert(bytes).toString();
  }

  Future<int> archiveCursor(PersonScope scope, String version) async {
    final rows = await _db.query(
      'archive_cursors',
      columns: ['last_committed_sequence'],
      where: 'owner_id = ? AND character_id = ? AND generator_version = ?',
      whereArgs: [..._scope(scope), version],
    );
    return rows.isEmpty ? 0 : rows.single['last_committed_sequence'] as int;
  }

  /// Archives at most one batch. Summarization runs outside the transaction;
  /// the source digest and expected cursor are rechecked before commit.
  Future<String?> archiveNext({
    required PersonScope scope,
    required MemorySummarizer summarizer,
    int minimumEvents = 2,
    int batchSize = 24,
  }) async {
    if (minimumEvents < 1 || batchSize < minimumEvents || batchSize > 500) {
      throw ArgumentError('Invalid archive window');
    }
    if (summarizer.version.trim().isEmpty) {
      throw ArgumentError('Summarizer version is required');
    }
    final cursor = await archiveCursor(scope, summarizer.version);
    final events = await _eligibleEvents(_db, scope, cursor, batchSize);
    if (events.length < minimumEvents) return null;
    final digest = _digest(scope, summarizer.version, events);
    final draft = await summarizer.summarize(events);
    final ids = events.map((event) => event.eventId).toList();
    if (jsonEncode(draft.sourceEventIds) != jsonEncode(ids) ||
        draft.text.trim().isEmpty ||
        !draft.confidence.isFinite ||
        draft.confidence < 0 ||
        draft.confidence > 1) {
      throw StateError('Summary has incomplete or invalid source citations');
    }
    final archiveId = 'archive-${digest.substring(0, 32)}';
    final summaryId = 'summary-${digest.substring(0, 32)}';
    final terms = draft.terms
        .map((term) => term.trim().toLowerCase())
        .where((term) => term.isNotEmpty && term.length <= 120)
        .toSet()
        .toList();
    final now = DateTime.now().toUtc().toIso8601String();
    return _db.transaction((txn) async {
      final cursors = await txn.query(
        'archive_cursors',
        columns: ['last_committed_sequence'],
        where: 'owner_id = ? AND character_id = ? AND generator_version = ?',
        whereArgs: [..._scope(scope), summarizer.version],
      );
      final actualCursor = cursors.isEmpty
          ? 0
          : cursors.single['last_committed_sequence'] as int;
      if (actualCursor != cursor) {
        throw StateError('Concurrent archive cursor change: retry safely');
      }
      final latest = await _eligibleEvents(txn, scope, cursor, batchSize);
      if (_digest(scope, summarizer.version, latest) != digest) {
        throw StateError('Archive source changed: retry safely');
      }
      await txn.insert('archive_segments', {
        'owner_id': scope.ownerId,
        'character_id': scope.characterId,
        'archive_id': archiveId,
        'sequence_from': events.first.sequence,
        'sequence_to': events.last.sequence,
        'source_digest': digest,
        'generator_version': summarizer.version,
        'created_at_utc': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('memory_summaries', {
        'owner_id': scope.ownerId,
        'character_id': scope.characterId,
        'summary_id': summaryId,
        'archive_id': archiveId,
        'summary': draft.text,
        'confidence': draft.confidence,
        'generator_version': summarizer.version,
        'status': 'active',
        'created_at_utc': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      // An invalidated identical archive may be intentionally regenerated.
      await txn.update(
        'memory_summaries',
        {'status': 'active'},
        where: 'owner_id = ? AND character_id = ? AND summary_id = ?',
        whereArgs: [..._scope(scope), summaryId],
      );
      for (final id in ids) {
        await txn.insert('summary_sources', {
          'owner_id': scope.ownerId,
          'character_id': scope.characterId,
          'summary_id': summaryId,
          'event_id': id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final term in terms) {
        await txn.insert('memory_terms', {
          'owner_id': scope.ownerId,
          'character_id': scope.characterId,
          'summary_id': summaryId,
          'term': term,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.insert('archive_cursors', {
        'owner_id': scope.ownerId,
        'character_id': scope.characterId,
        'generator_version': summarizer.version,
        'last_committed_sequence': events.last.sequence,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return summaryId;
    });
  }

  /// Called by an event-commit hook or app lifecycle retry worker. If an
  /// offline summarizer fails the cursor stays put; a later call can resume.
  Future<int> archiveReady({
    required PersonScope scope,
    required MemorySummarizer summarizer,
    int minimumEvents = 2,
    int batchSize = 24,
    int maxBatches = 32,
  }) async {
    if (maxBatches < 1 || maxBatches > 1000) {
      throw ArgumentError('Invalid maxBatches');
    }
    var completed = 0;
    while (completed < maxBatches) {
      final result = await archiveNext(
        scope: scope,
        summarizer: summarizer,
        minimumEvents: minimumEvents,
        batchSize: batchSize,
      );
      if (result == null) break;
      completed++;
    }
    return completed;
  }

  Future<List<MemorySummary>> summariesFor(
    PersonScope scope, {
    String query = '',
    int limit = 20,
  }) async {
    if (limit < 1 || limit > 200) throw ArgumentError('Invalid limit');
    final needle = query.trim().toLowerCase();
    final found = await _db.rawQuery(
      '''
      SELECT s.* FROM memory_summaries s
      INNER JOIN archive_segments a
        ON a.owner_id = s.owner_id AND a.character_id = s.character_id
        AND a.archive_id = s.archive_id
      WHERE s.owner_id = ? AND s.character_id = ? AND s.status = 'active'
        AND (? = '' OR instr(lower(s.summary), ?) > 0 OR EXISTS (
          SELECT 1 FROM memory_terms t
          WHERE t.owner_id = s.owner_id AND t.character_id = s.character_id
            AND t.summary_id = s.summary_id
            AND instr(t.term, ?) > 0
        ))
      ORDER BY a.sequence_to DESC LIMIT ?
    ''',
      [..._scope(scope), needle, needle, needle, limit],
    );
    final result = <MemorySummary>[];
    for (final row in found) {
      final id = row['summary_id'] as String;
      final sources = await _db.query(
        'summary_sources',
        columns: ['event_id'],
        where: 'owner_id = ? AND character_id = ? AND summary_id = ?',
        whereArgs: [..._scope(scope), id],
        orderBy: 'event_id ASC',
      );
      final termRows = await _db.query(
        'memory_terms',
        columns: ['term'],
        where: 'owner_id = ? AND character_id = ? AND summary_id = ?',
        whereArgs: [..._scope(scope), id],
        orderBy: 'term ASC',
      );
      result.add(
        MemorySummary(
          scope: scope,
          summaryId: id,
          archiveId: row['archive_id'] as String,
          text: row['summary'] as String,
          generatorVersion: row['generator_version'] as String,
          status: row['status'] as String,
          confidence: (row['confidence'] as num).toDouble(),
          sourceEventIds: [
            for (final source in sources) source['event_id'] as String,
          ],
          terms: [for (final term in termRows) term['term'] as String],
        ),
      );
    }
    return List.unmodifiable(result);
  }

  Future<List<RawEvent>> sourceEvents(
    PersonScope scope,
    String summaryId,
  ) async {
    final rows = await _db.rawQuery(
      '''
      SELECT e.* FROM raw_events e
      INNER JOIN summary_sources src
        ON src.owner_id = e.owner_id AND src.character_id = e.character_id
        AND src.event_id = e.event_id
      WHERE e.owner_id = ? AND e.character_id = ?
        AND src.summary_id = ?
      ORDER BY e.sequence ASC
    ''',
      [..._scope(scope), summaryId],
    );
    return List.unmodifiable(rows.map(_event));
  }

  /// Invalidate derived results and rewind all affected generator cursors.
  /// Called within the raw-event transaction on correction/redaction.
  static Future<void> invalidateSourceInTransaction(
    Transaction txn,
    PersonScope scope,
    String eventId, {
    bool purgeContent = false,
  }) async {
    final impacted = await txn.rawQuery(
      '''
      SELECT DISTINCT s.summary_id, a.sequence_from, a.generator_version
      FROM summary_sources src
      JOIN memory_summaries s
        ON src.owner_id = s.owner_id AND src.character_id = s.character_id
        AND src.summary_id = s.summary_id
      JOIN archive_segments a
        ON s.owner_id = a.owner_id AND s.character_id = a.character_id
        AND s.archive_id = a.archive_id
      WHERE src.owner_id = ? AND src.character_id = ? AND src.event_id = ?
        AND s.status IN ('active', 'invalidated')
    ''',
      [..._scope(scope), eventId],
    );
    final affectedIds = <String>{};
    for (final row in impacted) {
      final id = row['summary_id'] as String;
      affectedIds.add(id);
      await txn.update(
        'memory_summaries',
        {'status': 'invalidated', if (purgeContent) 'summary': ''},
        where: 'owner_id = ? AND character_id = ? AND summary_id = ?',
        whereArgs: [..._scope(scope), id],
      );
      await txn.delete(
        'memory_terms',
        where: 'owner_id = ? AND character_id = ? AND summary_id = ?',
        whereArgs: [..._scope(scope), id],
      );
      final from = row['sequence_from'] as int;
      await txn.rawUpdate(
        '''
        UPDATE archive_cursors SET last_committed_sequence =
          MIN(last_committed_sequence, ?)
        WHERE owner_id = ? AND character_id = ? AND generator_version = ?
      ''',
        [from - 1, ..._scope(scope), row['generator_version']],
      );
    }
    if (affectedIds.isEmpty) return;
    for (final table in ['identity_candidates', 'persona_identity_versions']) {
      final rows = await txn.query(
        table,
        where: purgeContent
            ? "owner_id = ? AND character_id = ? AND status IN ('proposed','approved','active','invalidated')"
            : "owner_id = ? AND character_id = ? AND status IN ('proposed','approved','active')",
        whereArgs: _scope(scope),
      );
      for (final row in rows) {
        final refs = (jsonDecode(
          row['source_summary_ids_json'] as String,
        ) as List).cast<String>();
        if (refs.any(affectedIds.contains)) {
          final key = table == 'identity_candidates'
              ? 'candidate_id'
              : 'version';
          await txn.update(
            table,
            {
              'status': 'invalidated',
              if (purgeContent && table == 'identity_candidates')
                'proposed_json': '{}',
              if (purgeContent && table == 'persona_identity_versions')
                'stable_state_json': '{}',
            },
            where: 'owner_id = ? AND character_id = ? AND $key = ?',
            whereArgs: [..._scope(scope), row[key]],
          );
        }
      }
    }
  }

  /// Correct a source by appending a new RawEvent with revisionOf set, using
  /// PersonDatabase.appendEvent; this public method handles manual rebuilding.
  Future<void> invalidateSummary(PersonScope scope, String summaryId) async {
    await _db.transaction((txn) async {
      final sources = await txn.query(
        'summary_sources',
        columns: ['event_id'],
        where: 'owner_id = ? AND character_id = ? AND summary_id = ?',
        whereArgs: [..._scope(scope), summaryId],
      );
      if (sources.isEmpty) throw StateError('Summary does not exist');
      for (final row in sources) {
        await invalidateSourceInTransaction(
          txn,
          scope,
          row['event_id'] as String,
        );
      }
    });
  }

  Future<PersonaCandidate> proposeIdentity({
    required PersonScope scope,
    required String candidateId,
    required Map<String, Object?> proposedState,
    required List<String> sourceSummaryIds,
    required double confidence,
  }) async {
    if (candidateId.trim().isEmpty ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1 ||
        sourceSummaryIds.isEmpty) {
      throw ArgumentError(
        'Candidate requires ID, valid confidence and sources',
      );
    }
    final refs = sourceSummaryIds.toSet().toList()..sort();
    await _db.transaction((txn) async {
      final identity = await txn.query(
        'characters',
        columns: ['base_identity_json'],
        where: 'owner_id = ? AND character_id = ?',
        whereArgs: _scope(scope),
      );
      if (identity.isEmpty) throw StateError('Character is missing');
      final base = jsonDecode(identity.single['base_identity_json'] as String);
      if (base is Map) {
        if (proposedState.keys.any(base.containsKey)) {
          throw StateError('Cannot overwrite user-defined identity fields');
        }
      }
      for (final id in refs) {
        final summary = await txn.query(
          'memory_summaries',
          columns: ['summary_id'],
          where: "owner_id = ? AND character_id = ? AND summary_id = ? AND status = 'active'",
          whereArgs: [..._scope(scope), id],
        );
        if (summary.isEmpty) throw StateError('Missing active memory evidence');
      }
      await txn.insert('identity_candidates', {
        'owner_id': scope.ownerId,
        'character_id': scope.characterId,
        'candidate_id': candidateId,
        'proposed_json': _canonicalJson(proposedState),
        'source_summary_ids_json': jsonEncode(refs),
        'confidence': confidence,
        'status': 'proposed',
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
      });
    });
    return PersonaCandidate(
      candidateId: candidateId,
      scope: scope,
      proposedJson: _canonicalJson(proposedState),
      sourceSummaryIds: List.unmodifiable(refs),
      status: 'proposed',
    );
  }

  /// Candidates are inspectable before the user approves or rejects them.
  Future<List<PersonaCandidate>> candidatesFor(PersonScope scope) async {
    final rows = await _db.query(
      'identity_candidates',
      where: 'owner_id = ? AND character_id = ?',
      whereArgs: _scope(scope),
      orderBy: 'created_at_utc DESC, candidate_id ASC',
    );
    return List.unmodifiable(
      rows.map(
        (row) => PersonaCandidate(
          candidateId: row['candidate_id'] as String,
          scope: scope,
          proposedJson: row['proposed_json'] as String,
          sourceSummaryIds: List.unmodifiable(
            (jsonDecode(row['source_summary_ids_json'] as String) as List)
                .cast<String>(),
          ),
          status: row['status'] as String,
        ),
      ),
    );
  }

  /// Full audit versions, including invalidated versions, remain inspectable.
  Future<List<Map<String, Object?>>> identityHistory(PersonScope scope) async {
    final rows = await _db.query(
      'persona_identity_versions',
      where: 'owner_id = ? AND character_id = ?',
      whereArgs: _scope(scope),
      orderBy: 'version DESC',
    );
    return List.unmodifiable(rows);
  }

  /// Explicit user confirmation only; never called by archiving.
  Future<int> approveIdentity({
    required PersonScope scope,
    required String candidateId,
    required int expectedVersion,
    required String approvedBy,
  }) async {
    if (approvedBy.trim().isEmpty) {
      throw ArgumentError('Explicit approving actor is required');
    }
    return _db.transaction((txn) async {
      final candidates = await txn.query(
        'identity_candidates',
        where: "owner_id = ? AND character_id = ? AND candidate_id = ? AND status = 'proposed'",
        whereArgs: [..._scope(scope), candidateId],
      );
      if (candidates.isEmpty) throw StateError('Candidate not approvable');
      final proposal = candidates.single;
      final versions = await txn.query(
        'persona_identity_versions',
        columns: ['version'],
        where: 'owner_id = ? AND character_id = ?',
        whereArgs: _scope(scope),
        orderBy: 'version DESC',
        limit: 1,
      );
      final current = versions.isEmpty ? 0 : versions.single['version'] as int;
      if (current != expectedVersion) {
        throw StateError('Identity version conflict');
      }
      final refs = (jsonDecode(
        proposal['source_summary_ids_json'] as String,
      ) as List).cast<String>();
      for (final id in refs) {
        final summary = await txn.query(
          'memory_summaries',
          columns: ['summary_id'],
          where: "owner_id = ? AND character_id = ? AND summary_id = ? AND status = 'active'",
          whereArgs: [..._scope(scope), id],
        );
        if (summary.isEmpty) throw StateError('Identity evidence is stale');
      }
      final base = await txn.query(
        'characters',
        columns: ['base_identity_json'],
        where: 'owner_id = ? AND character_id = ?',
        whereArgs: _scope(scope),
      );
      if (base.isEmpty) throw StateError('Character is missing');
      await txn.insert('persona_identity_versions', {
        'owner_id': scope.ownerId,
        'character_id': scope.characterId,
        'version': current + 1,
        'base_identity_json': base.single['base_identity_json'],
        'stable_state_json': proposal['proposed_json'],
        'source_summary_ids_json': proposal['source_summary_ids_json'],
        'approved_by': approvedBy,
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
        'status': 'active',
      });
      await txn.update(
        'identity_candidates',
        {'status': 'approved'},
        where: 'owner_id = ? AND character_id = ? AND candidate_id = ?',
        whereArgs: [..._scope(scope), candidateId],
      );
      return current + 1;
    });
  }

  Future<void> rejectIdentity(PersonScope scope, String candidateId) async {
    final count = await _db.update(
      'identity_candidates',
      {'status': 'rejected'},
      where: "owner_id = ? AND character_id = ? AND candidate_id = ? AND status = 'proposed'",
      whereArgs: [..._scope(scope), candidateId],
    );
    if (count != 1) throw StateError('Candidate not rejectable');
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static String _canonicalJson(Object? value) => jsonEncode(_canonical(value));

  /// Stable prefix changes only when user-defined base or approved identity
  /// state changes; recent messages and retrieval are deliberately excluded.
  Future<String> stablePrefix(PersonScope scope) async {
    final base = await _db.query(
      'characters',
      columns: ['base_identity_json'],
      where: 'owner_id = ? AND character_id = ?',
      whereArgs: _scope(scope),
    );
    if (base.isEmpty) throw StateError('Character not found');
    final versions = await _db.query(
      'persona_identity_versions',
      where: "owner_id = ? AND character_id = ? AND status = 'active'",
      whereArgs: _scope(scope),
      orderBy: 'version DESC',
      limit: 1,
    );
    final chosen = versions.isEmpty ? null : versions.single;
    return [
      promptVersion,
      'owner=${scope.ownerId}',
      'character=${scope.characterId}',
      'base=${_canonicalJson(jsonDecode(base.single['base_identity_json'] as String))}',
      "identity_version=${chosen?['version'] ?? 0}",
      "approved_state=${_canonicalJson(chosen == null ? <String, Object?>{} : jsonDecode(chosen['stable_state_json'] as String))}",
    ].join('\n');
  }

  Future<MemoryContext> assembleContext({
    required PersonScope scope,
    required String currentInput,
    int recentLimit = 12,
    int recallLimit = 4,
    bool expandSources = false,
    String? excludeEventId,
  }) async {
    if (recentLimit < 1 || recentLimit > 500) {
      throw ArgumentError('Invalid recentLimit');
    }
    final prefix = await stablePrefix(scope);
    final latest = await _db.rawQuery(
      '''
      SELECT e.* FROM raw_events e
      WHERE e.owner_id = ? AND e.character_id = ?
        AND e.status = 'complete'
        AND (? IS NULL OR e.event_id != ?)
        AND NOT EXISTS (
          SELECT 1 FROM raw_events revision
          WHERE revision.owner_id = e.owner_id
            AND revision.character_id = e.character_id
            AND revision.revision_of = e.event_id
            AND revision.status = 'complete'
        )
      ORDER BY e.sequence DESC LIMIT ?
    ''',
      [..._scope(scope), excludeEventId, excludeEventId, recentLimit],
    );
    final recent = latest.map(_event).toList().reversed.toList();
    final summaries =
        (await summariesFor(scope, query: currentInput, limit: recallLimit))
            .where((summary) {
              // A retry of the same user event must not duplicate it in retrieved memory.
              return excludeEventId == null ||
                  !summary.sourceEventIds.contains(excludeEventId);
            })
            .toList(growable: false);
    final expanded = <RawEvent>[];
    if (expandSources) {
      final seen = <String>{};
      for (final summary in summaries) {
        for (final event in await sourceEvents(scope, summary.summaryId)) {
          if (seen.add(event.eventId)) expanded.add(event);
        }
      }
      expanded.sort((a, b) => a.sequence.compareTo(b.sequence));
    }
    return MemoryContext(
      stablePrefix: prefix,
      promptTemplateVersion: promptVersion,
      recentEvents: List.unmodifiable(recent),
      recalledSummaries: summaries,
      expandedSourceEvents: List.unmodifiable(expanded),
      estimatedCharacters:
          prefix.length +
          currentInput.length +
          recent.fold<int>(0, (n, e) => n + e.content.length) +
          summaries.fold<int>(0, (n, s) => n + s.text.length) +
          expanded.fold<int>(0, (n, e) => n + e.content.length),
    );
  }
}
