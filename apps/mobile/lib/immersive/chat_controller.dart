import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/characters/application/character_selection_controller.dart';
import '../features/characters/domain/character.dart';
import '../features/chat/application/continuous_chat_controller.dart';
import '../features/chat/data/model_gateway_adapter.dart';
import '../features/timeline/data/person_database.dart';
import '../features/timeline/domain/raw_event.dart';
import 'conversation_controller.dart';
import 'data.dart';
import 'model_gateway.dart';

/// The voice service uses the original role identifiers. SQLite keeps the
/// official app's owner and character keys, including installations predating v4.
String voiceRole(String id) => switch (id) {
  'star' => 'xing',
  'moon' => 'yue',
  _ => id,
};

class ChatController extends ChangeNotifier {
  ChatController(this.selection, this.database, this.textGateway, this.gateway);

  final CharacterSelectionController selection;
  final PersonDatabase database;
  final ModelGatewayAdapter? textGateway;
  final ModelGateway? gateway;
  ConversationController? conversation;
  late ContinuousChatController _timeline;
  bool switching = false, _disposed = false;
  String? _saveError;
  Future<void> _writes = Future.value();
  final _queued = <(PersonScope, String)>{};
  final _events = <String, RawEvent>{};
  final _hidden = <String>{};
  List<Message> messages = [];
  List<Character> get characters => selection.characters;
  Character get character => selection.activeCharacter;
  String get selected => voiceRole(character.scope.characterId);
  bool get busy => conversation?.busy ?? _timeline.isSending;
  String? get error =>
      _saveError ??
      (_timeline.errorCode == null ? null : _timeline.statusMessage);
  bool get online =>
      gateway?.useV3 == true ||
      (character.supportsLegacyGateway &&
          (gateway != null || textGateway != null));
  Future<void> get flushed => _writes;

  Future<void> init() async {
    _timeline = ContinuousChatController(
      database: database,
      scope: character.scope,
      characterName: character.name,
      gateway: character.supportsLegacyGateway ? textGateway : null,
    )..addListener(_readTimeline);
    await _timeline.load();
  }

  void _readTimeline() {
    for (final row in _timeline.events) {
      _events[row.eventId] = row;
      if (row.status == 'redacted') _hidden.add(row.eventId);
    }
    refreshConversation();
  }

  void refreshConversation() {
    if (_disposed) return;
    final session = conversation;
    final live = {
      if (session != null && session.role == selected)
        for (final message in session.messages)
          if (message.characterId == selected &&
              !_hidden.contains(message.eventId))
            message.eventId: message,
    };
    messages = [
      for (final event in _events.values)
        if (!_hidden.contains(event.eventId) &&
            (event.speaker == 'user' || event.speaker == 'assistant'))
          live.remove(event.eventId) ??
              Message(
                id: -event.sequence,
                eventId: event.eventId,
                characterId: selected,
                author: event.speaker,
                text: event.content,
                status: event.status,
              ),
      ...live.values,
    ];
    notifyListeners();
  }

  // Only durable protocol events reach SQLite. Streaming PCM and text deltas
  // remain in the original voice controller. A reconnect replays stable IDs.
  void saveVoiceMessage(Message message) {
    final role = characters
        .where((c) => voiceRole(c.scope.characterId) == message.characterId)
        .firstOrNull;
    if (role == null || _disposed || message.status == 'pending') return;
    final scope = role.scope;
    final id = message.eventId;
    if (scope == character.scope && _events.containsKey(id)) return;
    final key = (scope, id);
    if (!_queued.add(key)) return;
    final content = message.text;
    final status = switch (message.status) {
      'complete' => 'complete',
      'interrupted' || 'cancelled' => 'cancelled',
      _ => 'failed',
    };
    _writes = _writes.then((_) async {
      try {
        final row =
            await database.rawEventById(scope: scope, eventId: id) ??
            await database.appendEvent(
              scope: scope,
              eventId: id,
              requestId: message.turnId,
              speaker: message.author,
              content: content,
              status: status,
              occurredAt: message.occurredAt,
            );
        if (!_disposed && scope == character.scope) {
          _events[id] = row;
          if (row.status == 'redacted') _hidden.add(id);
          _saveError = null;
          refreshConversation();
        }
      } catch (_) {
        if (!_disposed) {
          _saveError = '本机记录写入失败，重新连接后可恢复。';
          refreshConversation();
        }
      } finally {
        _queued.remove(key);
      }
    });
  }

  Future<bool> send(String text, {VoidCallback? onSaved}) async {
    if (switching || busy || text.trim().isEmpty) return false;
    final session = conversation;
    if (session != null) return session.text(text, selected, saved: onSaved);
    await _timeline.send(text);
    if (_timeline.errorCode != null) return false;
    onSaved?.call();
    return true;
  }

  Future<void> cancel() async {
    final session = conversation;
    if (session != null) {
      session.interrupt();
    } else {
      await _timeline.cancel();
    }
  }

  Future<void> retry(Message failed) async {
    if (conversation == null) return _timeline.retry();
    final user = messages.where((m) => m.id == failed.replyTo).firstOrNull;
    if (user != null) await send(user.text);
  }

  Future<void> switchCharacter(String id) async {
    if (switching || selected == id) return;
    switching = true;
    notifyListeners();
    try {
      await cancel();
      await conversation?.close();
      await _writes;
      final next = characters.firstWhere(
        (c) => voiceRole(c.scope.characterId) == id,
      );
      _timeline.removeListener(_readTimeline);
      _timeline.dispose();
      selection.selectCharacter(next.scope);
      _events.clear();
      _hidden.clear();
      _saveError = null;
      messages = [];
      await init();
      await conversation?.load(id);
    } finally {
      switching = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timeline.removeListener(_readTimeline);
    _timeline.dispose();
    if (gateway != null) unawaited(gateway!.close());
    super.dispose();
  }
}
