import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data.dart';

enum ReplyMode { normal, failure, delayed }

class ChatController extends ChangeNotifier {
  ChatController(
    this.store, {
    this.chunkDelay = const Duration(milliseconds: 75),
  });
  final LocalStore store;
  final Duration chunkDelay;
  List<Character> characters = [];
  List<Message> messages = [];
  String selected = 'xing';
  ReplyMode mode = ReplyMode.normal;
  bool busy = false;
  bool switching = false;
  String? error;
  Message? _active;
  int _generation = 0;
  int _lastId = DateTime.now().microsecondsSinceEpoch;
  int _nextId() => ++_lastId;
  Character get character => characters.firstWhere((c) => c.id == selected);

  Future<void> init() async {
    characters = await store.characters();
    final saved = await store.preference('selected');
    if (characters.any((c) => c.id == saved)) selected = saved!;
    messages = await store.messages(selected);
    notifyListeners();
  }

  Future<bool> send(String text, {Message? retry}) async {
    text = text.trim();
    if (text.isEmpty || busy || switching) return false;
    busy = true; // Reserve synchronously, before the first database await.
    error = null;
    final token = ++_generation;
    final role = selected;
    final currentMode = mode;
    final user =
        retry ??
        Message(
          id: _nextId(),
          characterId: role,
          author: 'user',
          text: text,
          status: 'complete',
        );
    final reply = Message(
      id: _nextId(),
      characterId: role,
      author: 'assistant',
      text: '',
      status: 'pending',
      replyTo: user.id,
    );
    _active = reply;
    if (retry == null) messages.add(user);
    messages.add(reply);
    notifyListeners();
    try {
      if (retry == null) {
        await store.savePair(user, reply);
      } else {
        await store.save(reply);
      }
      // Cancellation may have occurred while the initial transaction was pending.
      if (token != _generation) return true;
      if (currentMode == ReplyMode.delayed) {
        await Future<void>.delayed(const Duration(seconds: 6));
      }
      if (token != _generation) return true;
      if (currentMode == ReplyMode.failure) throw StateError('模拟服务暂时不可用，请重试');
      final name = characters.firstWhere((c) => c.id == role).name;
      final preview = String.fromCharCodes(text.runes.take(35));
      final response = '我是$name，收到你的消息：“$preview”。这是本地模拟回复，我们可以继续聊聊。';
      for (final rune in response.runes) {
        await Future<void>.delayed(chunkDelay);
        if (token != _generation) return true;
        reply.text += String.fromCharCode(rune);
        notifyListeners();
      }
      reply.status = 'complete';
      await store.save(reply);
    } catch (e) {
      if (token == _generation) {
        reply.status = 'failed';
        error = currentMode == ReplyMode.failure
            ? '模拟服务暂时不可用，请重试'
            : '保存或回复失败，请重试';
        try {
          await store.save(reply);
        } catch (_) {
          error = '本地保存失败，请检查存储空间';
        }
      }
    } finally {
      if (token == _generation) {
        busy = false;
        _active = null;
        notifyListeners();
      }
    }
    return true;
  }

  Future<void> cancel() async {
    ++_generation;
    final pending = _active;
    _active = null;
    busy = false;
    if (pending != null) {
      pending.status = 'cancelled';
      await store.save(pending);
    }
    notifyListeners();
  }

  Future<void> switchCharacter(String id) async {
    if (switching || selected == id) return;
    switching = true;
    notifyListeners();
    try {
      await cancel();
      selected = id;
      messages = await store.messages(id);
      await store.setPreference('selected', id);
      error = null;
    } finally {
      switching = false;
      notifyListeners();
    }
  }

  Future<bool> retry(Message failed) async {
    final user = messages.where((m) => m.id == failed.replyTo).firstOrNull;
    if (user == null) return false;
    return send(user.text, retry: user);
  }
}
