import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:companion_poc/main.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/avatar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android offline acceptance: chat, isolation, SQLite, avatar, player',
    (tester) async {
      final store = await LocalStore.open(
        name: 'acceptance-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final chat = ChatController(
        store,
        chunkDelay: const Duration(milliseconds: 2),
      );
      await chat.init();
      final audio = AudioController();
      final evidence = <String, Object?>{};
      await tester.pumpWidget(CompanionApp(chat: chat, audio: audio));
      await tester.pump(const Duration(milliseconds: 300));
      Future<void> until(bool Function() done, {int seconds = 20}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(done(), isTrue);
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(Key key) async {
        await tester.tap(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 250));
      }

      Future<void> role(String id) async {
        await tap(const Key('role-selector'));
        await tester.tap(find.text(id == 'xing' ? '小星' : '小月').last);
        await tester.pump(const Duration(milliseconds: 250));
        await until(() => chat.selected == id && !chat.switching);
      }

      expect(
        tester.widget<FilledButton>(find.byKey(const Key('send'))).onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const Key('message-input')), '   \n  ');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('send'))).onPressed,
        isNull,
      );
      final longChinese = '你好，今天心情怎么样？🙂\n${'长消息与中文标点，。！？' * 60}';
      for (var i = 0; i < 20; i++) {
        final text = i == 0 ? longChinese : '第 $i 轮中文对话，晚安🌙';
        await tester.enterText(find.byKey(const Key('message-input')), text);
        await tester.pump();
        await tap(const Key('send'));
        await until(() => !chat.busy);
        expect(chat.messages[chat.messages.length - 2].text, text);
        expect(chat.messages.last.status, 'complete');
      }
      expect(chat.messages.length, 40);
      evidence['twenty_ui_rounds'] = 'passed; Chinese/emoji/multiline entered through Flutter test input, not a native IME';
      // Starting a second submission before any await must not create duplicate rows.
      final first = chat.send('防止重复提交');
      expect(await chat.send('防止重复提交'), isFalse);
      await first;
      expect(chat.messages.length, 42);
      chat.mode = ReplyMode.failure;
      await chat.send('失败后重试');
      final failed = chat.messages.last;
      expect(failed.status, 'failed');
      final usersBefore = chat.messages.where((m) => m.author == 'user').length;
      chat.mode = ReplyMode.normal;
      await chat.retry(failed);
      expect(chat.messages.last.status, 'complete');
      expect(
        chat.messages.where((m) => m.author == 'user').length,
        usersBefore,
      );
      evidence['dedupe_and_retry'] = 'passed; retry reused user message';

      chat.mode = ReplyMode.delayed;
      final late = chat.send('取消后不能出现的旧回复');
      await tester.pump(const Duration(milliseconds: 200));
      await tap(const Key('cancel-reply'));
      final cancelled = chat.messages.last;
      await late;
      expect(cancelled.status, 'cancelled');
      expect(cancelled.text, isEmpty);
      evidence['late_reply_after_cancel'] =
          'passed after waiting beyond six-second delay';
      final pending = <Future<bool>>[];
      for (var i = 0; i < 10; i++) {
        pending.add(chat.send('切换前 $i'));
        await tester.pump(const Duration(milliseconds: 100));
        await role(chat.selected == 'xing' ? 'yue' : 'xing');
        expect(
          chat.messages.every((m) => m.characterId == chat.selected),
          isTrue,
        );
      }
      await Future.wait(pending);
      expect(
        (await store.messages('xing')).where((m) => m.status == 'pending'),
        isEmpty,
      );
      expect(
        (await store.messages('yue')).where((m) => m.status == 'pending'),
        isEmpty,
      );
      evidence['ten_role_switches_while_waiting'] = 'passed';

      await tap(const Key('nav-avatar'));
      for (final emotion in ['平静', '开心', '疑惑', '难过']) {
        await tap(ValueKey('emotion-$emotion'));
        expect(tester.widget<Avatar>(find.byType(Avatar)).emotion, emotion);
      }
      await tap(const Key('missing-expression'));
      expect(tester.widget<Avatar>(find.byType(Avatar)).emotion, '平静');
      for (final activity in ['待机', '等待', '说话']) {
        await tap(ValueKey('activity-$activity'));
      }
      await tap(const Key('animate'));
      expect(tester.widget<Avatar>(find.byType(Avatar)).animate, isFalse);
      evidence['avatar_states_and_fallback'] =
          'passed; generated placeholder drawing, no image generation';

      await tap(const Key('nav-audio'));
      await tap(const Key('play-tone'));
      await until(() => audio.playing);
      expect(find.text('说话 · 占位形象'), findsOneWidget);
      await role(chat.selected == 'xing' ? 'yue' : 'xing');
      expect(audio.playing, isFalse);
      await tap(const Key('play-tone'));
      await until(() => audio.playing);
      await tap(const Key('audio-stop'));
      expect(audio.playing, isFalse);
      await tap(const Key('play-tone'));
      await until(() => audio.playing);
      await tap(const Key('nav-chat'));
      expect(audio.playing, isFalse);
      evidence['audio_play_stop_switch_page_role'] = 'passed through real Android player; host audible output requires separate check';

      // Exact 100-row recovery fixture in an isolated SQLite database.
      var recovery = await LocalStore.open(
        name: 'recovery-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final recoveryName = recovery.db.path.split('/').last;
      for (var i = 0; i < 100; i++) {
        await recovery.save(
          Message(
            id: i + 1,
            characterId: i < 50 ? 'xing' : 'yue',
            author: i.isEven ? 'user' : 'assistant',
            text: '恢复测试 $i 中文🙂',
            status: i == 99 ? 'pending' : 'complete',
          ),
        );
      }
      await recovery.setPreference('selected', 'yue');
      await recovery.db.close();
      recovery = await LocalStore.open(name: recoveryName);
      expect(await recovery.count(), 100);
      expect((await recovery.characters()).length, 2);
      expect(await recovery.preference('selected'), 'yue');
      final recovered = await recovery.messages('yue');
      expect(recovered.length, 50);
      expect(recovered.last.status, 'interrupted');
      expect(recovered.last.text, '恢复测试 99 中文🙂');
      evidence['sqlite_close_reopen_100_rows'] =
          'passed; real process and emulator restart checked separately';
      await recovery.db.close();

      // Seed the manual app only on its first run; never erase an existing history.
      final manual = await LocalStore.open();
      if (await manual.count() == 0) {
        for (var i = 0; i < 100; i++) {
          await manual.save(
            Message(
              id: i + 1,
              characterId: i < 50 ? 'xing' : 'yue',
              author: i.isEven ? 'user' : 'assistant',
              text: '本地恢复验证样例 $i · 中文🙂',
              status: i == 99 ? 'pending' : 'complete',
            ),
          );
        }
        await manual.setPreference('selected', 'yue');
      }
      await manual.db.close();
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/acceptance-results.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
      debugPrint('ACCEPTANCE_RESULTS ${jsonEncode(evidence)}');
      await tester.pumpWidget(const SizedBox());
      await audio.close();
      chat.dispose();
      await store.db.close();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
