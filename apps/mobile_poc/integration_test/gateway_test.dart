import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/main.dart';
import 'package:companion_poc/model_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

class ControlledGateway extends ModelGateway {
  ControlledGateway() : super('', '');
  bool failVoice = true;
  bool waitVoice = false;
  Completer<Uint8List>? pending;
  final spoken = <String>[];
  final cancelled = <String>[];
  final contexts = <List<Map<String, String>>>[];
  Completer<void>? replyGate;
  bool failReply = false;
  @override
  Stream<String> reply({
    required String requestId,
    required String character,
    required String content,
    required List<Map<String, String>> history,
  }) async* {
    contexts.add(history);
    if (replyGate != null) await replyGate!.future;
    if (failReply) throw const GatewayException('MODEL_TIMEOUT');
    yield '测试完整回复';
  }

  @override
  Future<Uint8List> speech({
    required String requestId,
    required String replyRequestId,
    required String character,
  }) async {
    spoken.add(replyRequestId);
    if (waitVoice) {
      pending = Completer<Uint8List>();
      return pending!.future;
    }
    if (failVoice) throw const GatewayException('VOICE_UNAVAILABLE');
    return makeTone();
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'remote cancellation, failure retry, and context remain role scoped',
    (tester) async {
      final store = await LocalStore.open(
        name: 'gateway-context-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final gateway = ControlledGateway();
      final chat = ChatController(store, gateway: gateway);
      await chat.init();
      try {
        await chat.send('小星上下文');
        gateway.replyGate = Completer<void>();
        final pending = chat.send('取消这一次');
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (gateway.contexts.length < 2 &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(gateway.contexts.length, 2);
        await chat.switchCharacter('yue');
        gateway.replyGate!.complete();
        await pending;
        gateway.replyGate = null;
        expect(chat.messages, isEmpty);
        expect(gateway.cancelled, isNotEmpty);
        await chat.send('小月自己的消息');
        expect(gateway.contexts.last, isEmpty);
        await chat.switchCharacter('xing');
        gateway.failReply = true;
        await chat.send('失败后重试');
        final failed = chat.messages.last;
        expect(failed.status, 'failed');
        final users = chat.messages.where((m) => m.author == 'user').length;
        gateway.failReply = false;
        await chat.retry(failed);
        expect(chat.messages.last.status, 'complete');
        expect(chat.messages.where((m) => m.author == 'user').length, users);
        expect(
          gateway.contexts.last.every((m) => m['content'] != '小月自己的消息'),
          isTrue,
        );
        expect(
          gateway.contexts.last.every((m) => m['content'] != '失败后重试'),
          isTrue,
        );
        expect(
          gateway.contexts.last.every((m) => m['content'] != '取消这一次'),
          isTrue,
        );
        expect(
          (await store.messages('xing')).any((m) => m.status == 'cancelled'),
          isTrue,
        );
      } finally {
        chat.dispose();
        await store.db.close();
      }
    },
  );
  testWidgets(
    'configured gateway: real HTTP chat then WAV playback and SQLite reopen',
    (tester) async {
      final gateway = ModelGateway.configured();
      expect(
        gateway,
        isNotNull,
        reason:
            'Supply --dart-define-from-file with local gateway configuration',
      );
      final client = HttpClient();
      final healthResponse = await (await client.getUrl(
        Uri.parse('${gateway!.baseUrl}/health'),
      )).close();
      final health =
          jsonDecode(await utf8.decoder.bind(healthResponse).join()) as Map;
      client.close();
      final dbName = 'gateway-${DateTime.now().microsecondsSinceEpoch}.db';
      final store = await LocalStore.open(name: dbName);
      final chat = ChatController(store, gateway: gateway);
      final audio = AudioController();
      await chat.init();
      Future<void> until(bool Function() done, {int seconds = 110}) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          done(),
          isTrue,
          reason: 'chat error=${chat.error}; audio=${audio.status}',
        );
        expect(tester.takeException(), isNull);
      }

      try {
        await tester.pumpWidget(CompanionApp(chat: chat, audio: audio));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byKey(const Key('text-mode')));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.enterText(
          find.byKey(const Key('message-input')),
          '请用一句简短中文向我问好，不超过二十个字。',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('send')));
        await until(() => chat.messages.length == 2 && !chat.busy);
        expect(chat.messages.last.status, 'complete');
        expect(chat.messages.last.text, isNotEmpty);
        await until(() => audio.playing);
        expect(find.byKey(const Key('stop-speech')), findsOneWidget);
        expect(await store.count(), 2, reason: 'TTS adds no message rows');
        await tester.tap(find.byKey(const Key('stop-speech')));
        await until(() => !audio.playing && !audio.working);
        await tester.pumpWidget(const SizedBox());
        await audio.close();
        chat.dispose();
        await store.db.close();
        final reopened = await LocalStore.open(name: dbName);
        final restored = ChatController(reopened);
        await restored.init();
        expect(restored.messages.length, 2);
        expect(restored.messages.last.status, 'complete');
        expect(restored.selected, 'xing');
        restored.dispose();
        await reopened.db.close();
        debugPrint(
          'GATEWAY_DEVICE_RESULT mode=${health['mode']} chat_complete=true playback_started=true rows=2 reopen=true human_listening=pending',
        );
      } catch (_) {
        await tester.pumpWidget(const SizedBox());
        await audio.close();
        chat.dispose();
        await store.db.close();
        rethrow;
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'voice failure retry and late audio after role switch never corrupt text',
    (tester) async {
      final store = await LocalStore.open(
        name: 'voice-fault-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final gateway = ControlledGateway();
      final chat = ChatController(store, gateway: gateway);
      final audio = AudioController();
      await chat.init();
      Future<void> until(bool Function() done) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!done() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(done(), isTrue);
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(String key) async {
        await tester.pump();
        await tester.tap(find.byKey(Key(key)));
        await tester.pump(const Duration(milliseconds: 500));
      }

      try {
        await tester.pumpWidget(CompanionApp(chat: chat, audio: audio));
        await tester.pump(const Duration(seconds: 1));
        await chat.send('声音失败不影响文字');
        await until(
          () => find.byKey(const Key('retry-speech')).evaluate().isNotEmpty,
        );
        expect(chat.messages.last.status, 'complete');
        expect(await store.count(), 2);
        gateway.failVoice = false;
        await tap('retry-speech');
        await until(() => audio.playing);
        expect(await store.count(), 2);
        expect(gateway.spoken.length, 2);
        await tap('stop-speech');
        gateway.waitVoice = true;
        await chat.send('切换角色取消迟到声音');
        await until(() => gateway.pending != null);
        await tap('open-menu');
        await tap('menu-roles');
        await tap('select-yue');
        await until(() => chat.selected == 'yue' && !chat.switching);
        gateway.pending!.complete(makeTone());
        await tester.pump(const Duration(seconds: 1));
        expect(audio.playing, isFalse);
        expect(chat.messages, isEmpty);
        expect(gateway.cancelled, isNotEmpty);
        expect((await store.messages('xing')).length, 4);
        expect(find.byKey(const Key('reply-speech')), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await audio.close();
        chat.dispose();
        await store.db.close();
      }
    },
  );
}
