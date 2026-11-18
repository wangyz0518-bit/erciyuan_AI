import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

Future<LocalStore> openTestStore(String name) async {
  final store = await LocalStore.open(name: name);
  addTearDown(() async {
    if (store.db.isOpen) await store.db.close();
  });
  return store;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('failed initial SQLite write keeps a retryable pair on reopen', (
    tester,
  ) async {
    final name = 'write-failure-${DateTime.now().microsecondsSinceEpoch}.db';
    final original = await openTestStore(name);
    final chat = ChatController(original, chunkDelay: Duration.zero);
    addTearDown(chat.dispose);
    await chat.init();

    // Abort the second INSERT in the transaction. Once the reply is marked
    // failed, SQLite can write again, exposing any standalone reply write.
    await original.db.execute('''
      CREATE TRIGGER reject_pending_reply BEFORE INSERT ON messages
      WHEN NEW.author = 'assistant' AND NEW.status = 'pending'
      BEGIN SELECT RAISE(ABORT, 'test: initial reply write failed'); END
    ''');

    const message = '写入失败后重试这条消息';
    expect(await chat.send(message), isTrue);
    await original.db.close();

    final reopened = await openTestStore(name);
    final restored = ChatController(reopened, chunkDelay: Duration.zero);
    addTearDown(restored.dispose);
    await restored.init();

    expect(
      restored.messages,
      hasLength(2),
      reason: 'Both messages survive reopen',
    );
    final [user, failed] = restored.messages;
    expect(user.author, 'user');
    expect(user.text, message);
    expect(failed.status, 'failed');
    expect(failed.replyTo, user.id);

    await reopened.db.execute('DROP TRIGGER reject_pending_reply');
    expect(await restored.retry(failed), isTrue);
    expect(restored.messages.where((m) => m.author == 'user'), hasLength(1));
    final persisted = await reopened.messages(restored.selected);
    expect(persisted, hasLength(3));
    expect(persisted.last.status, 'complete');
    expect(persisted.last.replyTo, user.id);
  });

  testWidgets('persistent SQLite failure keeps the draft for resubmission', (
    tester,
  ) async {
    final store = await openTestStore(
      'unsaved-draft-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final chat = ChatController(store, chunkDelay: Duration.zero);
    final audio = AudioController();
    await chat.init();
    await store.db.execute('''
      CREATE TRIGGER reject_all_replies BEFORE INSERT ON messages
      WHEN NEW.author = 'assistant'
      BEGIN SELECT RAISE(ABORT, 'test: writes still failing'); END
    ''');

    try {
      await tester.pumpWidget(CompanionApp(chat: chat, audio: audio));
      final input = find.byKey(const Key('message-input'));
      const text = '存储恢复前保留这条草稿';
      await tester.enterText(input, text);
      await tester.pump();

      Future<void> submit() async {
        await tester.tap(find.byKey(const Key('send')));
        await tester.pump();
        for (var i = 0; i < 100 && chat.busy; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump();
        expect(chat.busy, isFalse);
      }

      await submit();
      expect(tester.widget<TextField>(input).controller!.text, text);
      expect(chat.error, contains('本地保存失败'));
      expect(chat.messages, isEmpty);
      expect(await store.count(), 0);

      await store.db.execute('DROP TRIGGER reject_all_replies');
      await submit();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      final saved = await store.messages(chat.selected);
      expect(saved, hasLength(2));
      expect(saved.first.text, text);
      expect(saved.last.status, 'complete');
      expect(saved.last.replyTo, saved.first.id);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await audio.close();
      chat.dispose();
    }
  });

  testWidgets('cancellation during a failed write leaves no orphan reply', (
    tester,
  ) async {
    final store = await openTestStore(
      'cancel-write-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final chat = ChatController(store, chunkDelay: Duration.zero);
    addTearDown(chat.dispose);
    await chat.init();
    await store.db.execute('''
      CREATE TRIGGER reject_user BEFORE INSERT ON messages
      WHEN NEW.author = 'user'
      BEGIN SELECT RAISE(ABORT, 'test: user write failed'); END
    ''');

    final send = chat.send('写入时立即取消');
    await chat.cancel();
    expect(await send, isFalse);
    expect(chat.busy, isFalse);
    expect(chat.messages, isEmpty);
    expect(await store.count(), 0);
  });
}
