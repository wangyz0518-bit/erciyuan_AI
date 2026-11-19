import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/main.dart';
import 'package:companion_poc/model_gateway.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const run = bool.fromEnvironment('CONVERSATION_LIVE_SMOKE');
  testWidgets('configured Android chat renders a live reply and drains PCM', (
    tester,
  ) async {
    final gateway = ModelGateway.configured()!;
    expect(gateway.useV3, isTrue);
    final store = await LocalStore.open(name: 'conversation-live-smoke.db');
    final chat = ChatController(store, gateway: gateway);
    final audio = AudioController();
    await chat.init();
    await tester.pumpWidget(CompanionApp(chat: chat, audio: audio));

    Future<void> until(bool Function() done, {int seconds = 12}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue, reason: chat.conversation?.status);
      expect(tester.takeException(), isNull);
    }

    try {
      await until(() => chat.conversation?.transport.connected == true);
      expect(chat.conversation!.transport.mode, 'live');
      final voices = await chat.conversation!.transport.voices();
      expect(voices.any((item) => item['status'] == 'ready'), isTrue);
      final before = chat.messages.length;
      await tester.tap(find.byKey(const Key('text-mode')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const Key('message-input')),
        '请只说一句：欢迎你来聊天。',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('send')));
      await until(
        () =>
            chat.messages.length >= before + 2 &&
            !chat.busy &&
            audio.streamMetrics['event'] == 'firstOutput',
        seconds: 85,
      );
      final reply = chat.messages.last;
      expect(reply.status, 'complete');
      expect(reply.text, isNotEmpty);
      expect(chat.conversation!.latency(reply), contains('到开播'));
      await chat.conversation!.close();
      await chat.conversation!.load(chat.selected);
      expect(chat.messages.last.text, reply.text);
      expect(audio.pcm.active, isNull);
    } finally {
      final voice = chat.conversation;
      if (voice != null) await voice.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await audio.close();
      chat.dispose();
      await store.db.close();
    }
  }, skip: !run);
}
