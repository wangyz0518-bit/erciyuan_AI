import 'package:erciyuan_mobile/bootstrap.dart';
import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:erciyuan_mobile/features/chat/data/model_gateway_adapter.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:erciyuan_mobile/immersive/chat_controller.dart';
import 'package:erciyuan_mobile/immersive/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test(
    'adds 小芽 once and keeps its local timeline without a v3 gateway',
    () async {
      final database = await PersonDatabase.open(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      const owner = localOwnerId;
      const star = PersonScope(ownerId: owner, characterId: 'star');
      const moon = PersonScope(ownerId: owner, characterId: 'moon');
      const sprout = PersonScope(
        ownerId: owner,
        characterId: sproutCharacterId,
      );
      await database.createCharacter(
        character: const Character(scope: star, name: '原有小星', description: 'A'),
        timelineId: 'legacy-star',
      );
      await database.createCharacter(
        character: const Character(scope: moon, name: '小月', description: 'B'),
        timelineId: 'legacy-moon',
      );
      await database.appendEvent(
        scope: star,
        eventId: 'legacy-message',
        speaker: 'user',
        content: '升级前的记录',
      );

      final app = await bootstrapCompanionApp(database: database);
      final selection = app.controller;
      addTearDown(selection.dispose);
      expect(selection.activeScope, star);
      expect(
        selection.characters.map((c) => c.scope),
        unorderedEquals([star, moon, sprout]),
      );
      expect(selection.activeCharacter.name, '原有小星');
      expect(await database.timelineIdFor(star), 'legacy-star');
      expect(await database.timelineIdFor(moon), 'legacy-moon');
      final sproutTimeline = await database.timelineIdFor(sprout);
      expect(sproutTimeline, isNotNull);

      final gateway = ModelGatewayAdapter(
        baseUri: Uri.parse('http://127.0.0.1:1'),
        accessToken: 'test-token',
        database: database,
      );
      addTearDown(gateway.close);
      final chat = ChatController(selection, database, gateway, null);
      await chat.init();
      addTearDown(chat.dispose);
      expect(chat.online, isTrue);
      await chat.switchCharacter(sproutCharacterId);
      expect(chat.online, isFalse);
      expect(chat.messages, isEmpty);
      expect(await chat.send('你好，小芽'), isTrue);
      expect(
        (await database.rawEventsFor(scope: sprout)).first.content,
        '你好，小芽',
      );
      await chat.switchCharacter('xing');
      expect(chat.online, isTrue);
      expect(chat.messages.single.text, '升级前的记录');

      final reopened = await bootstrapCompanionApp(database: database);
      addTearDown(reopened.controller.dispose);
      expect(reopened.controller.characters, hasLength(3));
      expect(await database.timelineIdFor(sprout), sproutTimeline);
    },
  );

  test(
    'v4 preserves official history, isolated roles and stable voice turn IDs',
    () async {
      final database = await PersonDatabase.open(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final app = await bootstrapCompanionApp(database: database);
      final selection = app.controller;
      final chat = ChatController(selection, database, null, null);
      final starScope = selection.characters
          .firstWhere((c) => c.scope.characterId == 'star')
          .scope;
      selection.selectCharacter(starScope);
      await database.appendEvent(
        scope: starScope,
        eventId: 'prior',
        speaker: 'user',
        content: '合并前的记录',
      );
      await chat.init();
      expect(chat.selected, 'xing');
      expect(chat.messages.single.text, '合并前的记录');
      Message input() => Message(
        id: 1,
        characterId: 'xing',
        author: 'user',
        text: '测试录音',
        status: 'complete',
        eventId: 'v3-user-test',
        turnId: 'test',
      );
      Message reply() => Message(
        id: 2,
        characterId: 'xing',
        author: 'assistant',
        text: '收到',
        status: 'complete',
        eventId: 'v3-assistant-test',
        turnId: 'test',
      );
      chat.saveVoiceMessage(input());
      chat.saveVoiceMessage(input());
      chat.saveVoiceMessage(reply());
      await chat.flushed;
      await chat.switchCharacter('yue');
      expect(chat.messages, isEmpty);
      chat.saveVoiceMessage(reply());
      await chat.flushed;
      expect(chat.messages, isEmpty);
      await chat.switchCharacter('xing');
      expect(chat.messages.map((m) => m.text), ['合并前的记录', '测试录音', '收到']);
      await database.redactEvent(scope: starScope, eventId: 'v3-user-test');
      await chat.switchCharacter('yue');
      await chat.switchCharacter('xing');
      chat.saveVoiceMessage(input());
      await chat.flushed;
      expect(chat.messages.map((m) => m.text), ['合并前的记录', '收到']);
      expect(await database.rawEventsFor(scope: starScope), hasLength(3));
      chat.dispose();
      selection.dispose();
      await database.close();
    },
  );
}
