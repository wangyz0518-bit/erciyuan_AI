import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:companion_poc/main.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/widgets/character_scene.dart';
import 'package:companion_poc/widgets/chat_messages.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'immersive UI, recovery, retry, call and real temporary recording',
    (tester) async {
      final store = await LocalStore.open(
        name: 'immersive-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final chat = ChatController(store, chunkDelay: Duration.zero);
      final audio = AudioController();
      final screenshotKey = GlobalKey();
      await chat.init();
      Future<void> until(bool Function() done, {int seconds = 20}) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(done(), isTrue);
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(String key) async {
        await tester.pump();
        final target = find.byKey(Key(key));
        await until(() => target.evaluate().isNotEmpty);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      }

      Future<void> screenshot(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        final dir = await getApplicationDocumentsDirectory();
        final boundary =
            screenshotKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = png!.buffer.asUint8List();
        image.dispose();
        await File('${dir.path}/$name.png').writeAsBytes(bytes);
      }

      Future<void> select(String role) async {
        await tap('open-menu');
        await tap('menu-roles');
        await tap('select-$role');
        await until(() => !chat.switching && chat.selected == role);
      }

      try {
        await chat.send('今天有些疲惫，想和你说说话。');
        await tester.pumpWidget(
          RepaintBoundary(
            key: screenshotKey,
            child: CompanionApp(chat: chat, audio: audio),
          ),
        );
        await tester.pump(const Duration(seconds: 2));

        await tester.pump();
        expect(find.byKey(const Key('hold-record')), findsOneWidget);
        expect(find.byType(ChatMessage), findsNWidgets(2));
        await screenshot('immersive-voice');
        await tap('camera-toggle');
        expect(
          tester.widget<CharacterScene>(find.byType(CharacterScene)).full,
          isTrue,
        );
        await screenshot('immersive-full');
        await tap('camera-toggle');
        await tap('open-menu');
        expect(
          tester.getSize(find.byKey(const Key('sidebar-panel'))).width,
          72,
        );
        await screenshot('immersive-sidebar');
        await tap('menu-profile');
        expect(find.text('访客'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.fling(
          find.byKey(const Key('recent-messages')),
          const Offset(0, -150),
          800,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const Key('message-list')), findsOneWidget);
        await screenshot('immersive-history');
        await tap('close-history');
        await tap('text-mode');
        // A synthetic inset verifies layout logic; real IME is checked separately.
        tester.view.viewInsets = FakeViewPadding(
          bottom: 280 * tester.view.devicePixelRatio,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ChatMessage), findsOneWidget);
        await screenshot('immersive-keyboard-layout');
        await tester.enterText(
          find.byKey(const Key('message-input')),
          '中文🙂\n多行消息',
        );
        await tap('send');
        await until(() => !chat.busy);
        expect(chat.messages[chat.messages.length - 2].text, '中文🙂\n多行消息');
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('message-input')))
              .controller!
              .text,
          isEmpty,
        );
        tester.view.resetViewInsets();
        await tap('voice-mode');
        chat.mode = ReplyMode.failure;
        await chat.send('失败重试检查');
        await tester.pump();
        final failed = chat.messages.last;
        final users = chat.messages.where((m) => m.author == 'user').length;
        chat.mode = ReplyMode.normal;
        await tap('retry-${failed.id}');
        await until(() => !chat.busy);
        expect(chat.messages.where((m) => m.author == 'user').length, users);
        chat.mode = ReplyMode.delayed;
        final cancelled = chat.send('取消后不能串入新角色');
        await tester.pump(const Duration(milliseconds: 100));
        await tap('cancel-reply');
        await cancelled;
        expect(chat.messages.last.status, 'cancelled');
        // In-memory drafts remain scoped to each character.
        await tap('text-mode');
        await tester.enterText(
          find.byKey(const Key('message-input')),
          '小星的未发送草稿',
        );
        await select('yue');
        expect(chat.messages, isEmpty);
        await tap('text-mode');
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('message-input')))
              .controller!
              .text,
          isEmpty,
        );
        await tester.enterText(find.byKey(const Key('message-input')), '小月草稿');
        await select('xing');
        await tap('text-mode');
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('message-input')))
              .controller!
              .text,
          '小星的未发送草稿',
        );
        await tap('voice-mode');
        for (var i = 0; i < 10; i++) {
          await tap('start-call');
          expect(find.text('00:00'), findsOneWidget);
          if (i == 0) {
            await tester.pump(const Duration(seconds: 2));
            expect(find.text('00:00'), findsNothing);
            await screenshot('immersive-call');
          }
          await tap('mute-call');
          expect(find.text('已静音'), findsOneWidget);
          await tap('end-call');
          expect(find.byKey(const Key('hold-record')), findsOneWidget);
        }
        final count = await store.count();
        final hold = find.byKey(const Key('hold-record'));
        // Instant release during native startup must leave no running recorder.
        var finger = await tester.startGesture(tester.getCenter(hold));
        await finger.up();
        await tester.pump();
        await until(() => !audio.working);
        expect(audio.recording, isFalse);
        tester.view.physicalSize = Size(
          375 * tester.view.devicePixelRatio,
          812 * tester.view.devicePixelRatio,
        );
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        await tester.pump(const Duration(milliseconds: 300));
        await tap('text-mode');
        await tester.enterText(
          find.byKey(const Key('message-input')),
          '窄屏与较大字体检查',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tap('voice-mode');
        await tap('open-menu');
        await tap('menu-history');
        await tap('close-history');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.resetPhysicalSize();
        expect(audio.recordingPath, isNull);
        finger = await tester.startGesture(tester.getCenter(hold));
        await until(() => audio.recording);
        await tester.pump(const Duration(seconds: 2));
        await finger.up();
        await until(() => !audio.working && audio.recordingPath != null);
        final recorded = audio.recordingPath!;
        expect(await File(recorded).length(), greaterThan(44));
        await screenshot('immersive-recording-preview');
        await tap('preview-play');
        await until(() => audio.playing);
        await tap('preview-delete');
        await until(() => !audio.working);
        expect(await File(recorded).exists(), isFalse);
        finger = await tester.startGesture(tester.getCenter(hold));
        await until(() => audio.recording);
        await finger.moveBy(const Offset(0, -100));
        await finger.up();
        await until(() => !audio.working);
        expect(audio.recording, isFalse);
        expect(audio.recordingPath, isNull);
        // Keep holding: the real controller must stop at 30 seconds by itself.
        finger = await tester.startGesture(tester.getCenter(hold));
        await until(() => audio.recording);
        await until(
          () => !audio.recording && audio.recordingPath != null,
          seconds: 35,
        );
        expect(audio.seconds, 30);
        await finger.up();
        await select('yue');
        await until(() => !audio.working);
        expect(audio.recordingPath, isNull);
        expect(await File(recorded).exists(), isFalse);
        expect(
          await store.count(),
          count,
          reason: 'recordings and mock calls never create messages',
        );
        final restored = ChatController(store);
        await restored.init();
        expect(restored.selected, 'yue');
        expect(restored.messages, isEmpty);
        restored.dispose();
        await tap('start-call');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(milliseconds: 300));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(find.byKey(const Key('call-time')), findsNothing);
        expect(audio.recording, isFalse);
        debugPrint(
          'IMMERSIVE_RESULT passed: UI, per-role drafts, retry, cancel, 10 calls, recording release/cancel/30s/cleanup; no voice rows',
        );
      } finally {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.resetPhysicalSize();
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox());
        await audio.close();
        chat.dispose();
        await store.db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
