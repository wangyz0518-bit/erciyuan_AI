import 'dart:io';

import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:erciyuan_mobile/features/chat/application/continuous_chat_controller.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  const star = PersonScope(ownerId: 'owner-a', characterId: 'star');
  const moon = PersonScope(ownerId: 'owner-a', characterId: 'moon');
  late Directory directory;
  late PersonDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('erciyuan-chat-logic-');
    database = await PersonDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: path.join(directory.path, 'people.db'),
    );
    for (final character in const [
      Character(scope: star, name: '星', description: 'A'),
      Character(scope: moon, name: '月', description: 'B'),
    ]) {
      await database.createCharacter(
        character: character,
        timelineId: 'timeline-${character.scope.characterId}',
      );
    }
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'offline send persists one real user and one clearly marked mock reply',
    () async {
      final chat = ContinuousChatController(
        database: database,
        scope: star,
        characterName: '星',
      );
      await chat.load();
      await chat.send('今天怎样');
      expect(chat.isMock, isTrue);
      expect(chat.events, hasLength(2));
      expect(chat.events.first.speaker, 'user');
      expect(chat.events.last.speaker, 'assistant');
      expect(chat.events.last.content, contains('离线 Mock'));
      expect(await database.rawEventsFor(scope: moon), isEmpty);
      chat.dispose();
    },
  );

  test(
    'mock cancellation saves user input but never partial assistant answer',
    () async {
      final chat = ContinuousChatController(
        database: database,
        scope: star,
        characterName: '星',
      );
      final sending = chat.send('可取消');
      // Chat enters a pending state synchronously before the SQLite calls.
      expect(chat.isSending, isTrue);
      await chat.cancel();
      await sending;
      expect(chat.isSending, isFalse);
      expect(chat.events.where((e) => e.speaker == 'user'), hasLength(1));
      expect(chat.events.where((e) => e.speaker == 'assistant'), isEmpty);
      expect(chat.canRetry, isTrue);
      await chat.retry();
      expect(chat.events.where((e) => e.speaker == 'user'), hasLength(1));
      expect(chat.events.where((e) => e.speaker == 'assistant'), hasLength(1));
      chat.dispose();
    },
  );

  test(
    'reload and independent controller read the same durable timeline',
    () async {
      final first = ContinuousChatController(
        database: database,
        scope: moon,
        characterName: '月',
      );
      await first.send('月的秘密');
      first.dispose();
      final reopened = ContinuousChatController(
        database: database,
        scope: moon,
        characterName: '月',
      );
      await reopened.load();
      expect(reopened.events.first.content, '月的秘密');
      final other = ContinuousChatController(
        database: database,
        scope: star,
        characterName: '星',
      );
      await other.load();
      expect(other.events, isEmpty);
      reopened.dispose();
      other.dispose();
    },
  );
}
