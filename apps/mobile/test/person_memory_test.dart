import 'dart:convert';
import 'dart:io';

import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:erciyuan_mobile/features/memory/domain/memory_models.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:erciyuan_mobile/features/timeline/domain/raw_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class UncitedSummarizer implements MemorySummarizer {
  @override
  String get version => 'uncited-test';

  @override
  Future<MemoryDraft> summarize(List<RawEvent> events) async {
    return const MemoryDraft(
      text: 'uncited fake',
      terms: ['fake'],
      sourceEventIds: ['some-other-event'],
      confidence: 0.5,
    );
  }
}

void main() {
  sqfliteFfiInit();

  const star = PersonScope(ownerId: 'owner-a', characterId: 'star');
  const moon = PersonScope(ownerId: 'owner-a', characterId: 'moon');
  const foreign = PersonScope(ownerId: 'owner-b', characterId: 'star');
  const summarizer = DeterministicSummarizer();

  late Directory temp;
  late String dbPath;
  late PersonDatabase db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('erciyuan-memory-');
    dbPath = path.join(temp.path, 'memory.db');
    db = await PersonDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    for (final entry in [
      (star, 'star-timeline'),
      (moon, 'moon-timeline'),
      (foreign, 'foreign-timeline'),
    ]) {
      await db.createCharacter(
        character: Character(
          scope: entry.$1,
          name: entry.$1.characterId,
          description: 'test',
        ),
        timelineId: entry.$2,
        baseIdentityJson: '{"name":"星","tone":"kind"}',
      );
    }
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> add(
    PersonScope scope,
    String id,
    String text, {
    String? revisionOf,
    String status = 'complete',
  }) async {
    await db.appendEvent(
      scope: scope,
      eventId: id,
      speaker: 'user',
      content: text,
      status: status,
      revisionOf: revisionOf,
    );
  }

  test(
    'archive persists raw citations and is idempotent after restart',
    () async {
      await add(star, 'star-1', '我喜欢喝热茶');
      await add(star, 'star-2', '我希望一直记住这件事');
      await add(star, 'pending', '不应归档', status: 'failed');

      final first = await db.memory.archiveNext(
        scope: star,
        summarizer: summarizer,
      );
      expect(first, isNotNull);
      expect(
        await db.memory.archiveNext(scope: star, summarizer: summarizer),
        isNull,
      );
      final remembered = await db.memory.summariesFor(star, query: '热茶');
      expect(remembered, hasLength(1));
      expect(
        remembered.single.sourceEventIds,
        containsAll(['star-1', 'star-2']),
      );
      final sources = await db.memory.sourceEvents(star, first!);
      expect(sources.map((e) => e.eventId), ['star-1', 'star-2']);
      expect(await db.memory.archiveCursor(star, summarizer.version), 2);

      await db.close();
      db = await PersonDatabase.open(
        factory: databaseFactoryFfi,
        databasePath: dbPath,
      );
      expect(await db.memory.summariesFor(star), hasLength(1));
      expect(
        await db.memory.archiveNext(scope: star, summarizer: summarizer),
        isNull,
      );
      final raw = await db.rawEventsFor(scope: star);
      expect(raw, hasLength(3)); // Archiving never deletes the facts.
    },
  );

  test(
    'owner+character isolation applies to search, source and export',
    () async {
      await add(star, 'a1', '蓝色山茶花');
      await add(star, 'a2', '星期二去花店');
      await add(moon, 'm1', '银色月光');
      await add(moon, 'm2', '星空很美');
      await add(foreign, 'f1', '别人的私密资料');
      await add(foreign, 'f2', '禁止共享');
      final starSummary = await db.memory.archiveNext(
        scope: star,
        summarizer: summarizer,
      );
      await db.memory.archiveNext(scope: moon, summarizer: summarizer);
      await db.memory.archiveNext(scope: foreign, summarizer: summarizer);

      expect(await db.memory.summariesFor(star, query: '银色月光'), isEmpty);
      expect(await db.memory.summariesFor(moon, query: '蓝色山茶花'), isEmpty);
      expect(await db.memory.sourceEvents(foreign, starSummary!), isEmpty);
      final export = jsonDecode(
        await db.exportOwnerJson('owner-a'),
      ) as Map<String, dynamic>;
      expect((export['raw_events'] as List), hasLength(4));
      expect((export['archive_segments'] as List), hasLength(2));
      expect((export['memory_summaries'] as List), hasLength(2));
      expect((export['summary_sources'] as List), hasLength(4));
      expect(jsonEncode(export), isNot(contains('别人的私密资料')));
      expect(jsonEncode(export), contains('蓝色山茶花'));
    },
  );

  test('missing or fabricated citations cannot commit an archive', () async {
    await add(star, 'a1', 'one fact');
    await add(star, 'a2', 'another fact');
    await expectLater(
      db.memory.archiveNext(scope: star, summarizer: UncitedSummarizer()),
      throwsStateError,
    );
    expect(await db.memory.archiveCursor(star, 'uncited-test'), 0);
    expect(await db.memory.summariesFor(star), isEmpty);
  });

  test(
    'identity is proposed, scoped and confirmed before prefix changes',
    () async {
      await add(star, 'e1', 'I like oolong tea');
      await add(star, 'e2', 'It is a stable preference');
      final id = await db.memory.archiveNext(
        scope: star,
        summarizer: summarizer,
      );
      final initialPrefix = await db.memory.stablePrefix(star);
      final candidate = await db.memory.proposeIdentity(
        scope: star,
        candidateId: 'tea-preference',
        proposedState: {'favorite_drink': 'oolong'},
        sourceSummaryIds: [id!],
        confidence: 0.8,
      );
      expect(candidate.status, 'proposed');
      expect(await db.memory.stablePrefix(star), initialPrefix);
      await expectLater(
        db.memory.proposeIdentity(
          scope: moon,
          candidateId: 'foreign',
          proposedState: {'favorite_drink': 'tea'},
          sourceSummaryIds: [id],
          confidence: 0.8,
        ),
        throwsStateError,
      );
      await expectLater(
        db.memory.proposeIdentity(
          scope: star,
          candidateId: 'override-base',
          proposedState: {'tone': 'unsafe overwrite'},
          sourceSummaryIds: [id],
          confidence: 0.8,
        ),
        throwsStateError,
      );
      expect(
        await db.memory.approveIdentity(
          scope: star,
          candidateId: 'tea-preference',
          expectedVersion: 0,
          approvedBy: 'owner-confirmed',
        ),
        1,
      );
      final approvedPrefix = await db.memory.stablePrefix(star);
      expect(approvedPrefix, contains('identity_version=1'));
      expect(approvedPrefix, contains('favorite_drink'));
      expect(approvedPrefix, contains('tone'));
      expect(approvedPrefix, isNot(initialPrefix));
      expect(await db.memory.stablePrefix(moon), isNot(approvedPrefix));
      await expectLater(
        db.memory.approveIdentity(
          scope: star,
          candidateId: 'tea-preference',
          expectedVersion: 0,
          approvedBy: 'owner-confirmed',
        ),
        throwsStateError,
      );

      final context = await db.memory.assembleContext(
        scope: star,
        currentInput: 'oolong',
        expandSources: true,
      );
      expect(context.stablePrefix, approvedPrefix);
      expect(context.recalledSummaries, hasLength(1));
      expect(context.expandedSourceEvents, hasLength(2));
      expect(context.estimatedCharacters, greaterThan(0));
    },
  );

  test(
    'correction invalidates old summary and supports safe rebuilding',
    () async {
      await add(star, 'old', '我喜欢红茶');
      await add(star, 'other', '每天都想喝茶');
      final oldId = await db.memory.archiveNext(
        scope: star,
        summarizer: summarizer,
      );
      await db.memory.proposeIdentity(
        scope: star,
        candidateId: 'pref',
        proposedState: {'drink': 'black tea'},
        sourceSummaryIds: [oldId!],
        confidence: 0.5,
      );
      await add(star, 'corrected', '我现在喜欢绿茶', revisionOf: 'old');
      expect(await db.memory.summariesFor(star, query: '红茶'), isEmpty);
      expect(await db.memory.archiveCursor(star, summarizer.version), 0);
      await expectLater(
        db.memory.approveIdentity(
          scope: star,
          candidateId: 'pref',
          expectedVersion: 0,
          approvedBy: 'owner-confirmed',
        ),
        throwsStateError,
      );
      final replacement = await db.memory.archiveNext(
        scope: star,
        summarizer: summarizer,
      );
      expect(replacement, isNot(oldId));
      final current = await db.memory.summariesFor(star, query: '绿茶');
      expect(current, hasLength(1));
      expect(current.single.sourceEventIds, isNot(contains('old')));
      expect(current.single.sourceEventIds, contains('corrected'));
      final bundle = await db.memory.assembleContext(
        scope: star,
        currentInput: '绿茶',
      );
      expect(bundle.recentEvents.map((e) => e.eventId), isNot(contains('old')));
      expect((await db.rawEventsFor(scope: star)), hasLength(3));
    },
  );

  test(
    'explicit redaction purges old text and derived summaries from export',
    () async {
      await add(star, 'private', '需要清除的秘密777');
      await add(star, 'keep', '可以留下');
      await db.memory.archiveNext(scope: star, summarizer: summarizer);
      expect(await db.memory.summariesFor(star, query: '秘密'), hasLength(1));
      await db.redactEvent(scope: star, eventId: 'private');
      expect(await db.memory.summariesFor(star, query: '秘密'), isEmpty);
      final dump = await db.exportOwnerJson('owner-a');
      expect(dump, isNot(contains('需要清除的秘密777')));
      expect(dump, contains('"redacted"'));
      expect(await db.memory.archiveCursor(star, summarizer.version), 0);
    },
  );

  test('configured auto archiver reacts to committed events', () async {
    await db.close();
    db = await PersonDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: dbPath,
      automaticSummarizer: summarizer,
    );
    await add(star, 'auto-1', 'a committed memory');
    expect(await db.memory.summariesFor(star), isEmpty);
    await add(star, 'auto-2', 'the next committed event');
    expect(db.lastArchiveError, isNull);
    expect(await db.memory.summariesFor(star), hasLength(1));
    expect(await db.memory.archiveCursor(star, summarizer.version), 2);
  });

  test('stable prompt is unchanged by new messages or summaries', () async {
    final before = await db.memory.stablePrefix(star);
    await add(star, 'one', '记住这个');
    await add(star, 'two', '后续再说');
    await db.memory.archiveNext(scope: star, summarizer: summarizer);
    final after = await db.memory.stablePrefix(star);
    expect(after, before);
    final context = await db.memory.assembleContext(
      scope: star,
      currentInput: '记住',
      expandSources: false,
    );
    expect(context.stablePrefix, before);
    expect(context.recalledSummaries, hasLength(1));
    expect(context.expandedSourceEvents, isEmpty);
  });
}
