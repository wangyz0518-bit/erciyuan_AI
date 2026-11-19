import 'package:erciyuan_mobile/bootstrap.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:erciyuan_mobile/immersive/chat_controller.dart';
import 'package:erciyuan_mobile/immersive/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
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
