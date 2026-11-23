import 'package:erciyuan_mobile/bootstrap.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:erciyuan_mobile/immersive/immersive_chat_page.dart';
import 'package:erciyuan_mobile/immersive/immersive_home.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const run = bool.fromEnvironment('CONVERSATION_LIVE_SMOKE');
  const role = String.fromEnvironment(
    'CONVERSATION_TEST_ROLE',
    defaultValue: 'xing',
  );
  testWidgets(
    'native v4 entry sends through the bound voice and saves to the official timeline',
    (tester) async {
      final db = await PersonDatabase.open(databasePath: ':memory:');
      final app = await bootstrapCompanionApp(
        database: db,
        homeBuilder: ImmersiveHome.new,
      );
      await tester.pumpWidget(app);
      Future<void> until(bool Function() done, {int seconds = 15}) async {
        final clock = Stopwatch()..start();
        while (!done() && clock.elapsed < Duration(seconds: seconds)) {
          await tester.pump(const Duration(milliseconds: 60));
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        expect(done(), isTrue);
        expect(tester.takeException(), isNull);
      }

      await until(() => find.byType(ImmersiveChatPage).evaluate().isNotEmpty);
      final page = tester.widget<ImmersiveChatPage>(
        find.byType(ImmersiveChatPage),
      );
      final chat = page.chat;
      final voice = chat.conversation!;
      await until(() => voice.transport.connected);
      if (chat.selected != role) {
        await tester.tap(find.byKey(const Key('open-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('menu-roles')));
        final choice = find.byKey(const Key('select-$role'));
        await until(() => choice.evaluate().isNotEmpty);
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await until(
          () =>
              chat.selected == role &&
              !chat.switching &&
              voice.transport.connected,
        );
      }
      expect(voice.role, role);
      expect(chat.online, isTrue);
      expect(voice.transport.mode, 'live');
      expect(find.byKey(const Key('hold-record')), findsOneWidget);
      expect(find.byKey(const Key('start-call')), findsOneWidget);
      final binding = await voice.transport.binding(chat.selected);
      expect(binding['character_id'], role);
      if (role == 'xing') expect(binding['profile_id'], isNotNull);
      var audioStarted = false;
      String? usedVoice;
      final sub = voice.transport.events.listen((event) {
        if (event['event'] == 'audio.started') {
          audioStarted = true;
          usedVoice = event['voice_profile_id'] as String?;
        }
      });
      try {
        await tester.tap(find.byKey(const Key('text-mode')));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.enterText(
          find.byKey(const Key('message-input')),
          role == 'sprout' ? '请用一句简短的话告诉我你叫什么名字。' : '请只说一句：欢迎你来聊天。',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('send')));
        await until(
          () =>
              !chat.busy &&
              audioStarted &&
              page.audio.streamMetrics['event'] == 'firstOutput',
          seconds: 90,
        );
        expect(usedVoice, binding['profile_id']);
        await chat.flushed;
        final scope = chat.character.scope;
        final durable = await db.rawEventsFor(scope: scope);
        expect(durable.last.speaker, 'assistant');
        expect(durable.last.status, 'complete');
        expect(durable.last.content, chat.messages.last.text);
        expect(durable.last.content, isNotEmpty);
        if (role == 'sprout') expect(durable.last.content, contains('小芽'));
        await voice.close();
        await voice.load(chat.selected);
        await chat.flushed;
        expect(await db.rawEventsFor(scope: scope), hasLength(durable.length));
        expect(
          chat.messages.where((m) => m.eventId == durable.last.eventId),
          hasLength(1),
        );
      } finally {
        await sub.cancel();
        await voice.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
    skip: !run,
  );
}
