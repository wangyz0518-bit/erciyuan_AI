import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../characters/domain/character.dart';
import '../../timeline/data/person_database.dart';
import '../../timeline/domain/raw_event.dart';
import '../data/model_gateway_adapter.dart';

/// UI state for exactly one owner+character timeline. It never creates sessions.
final class ContinuousChatController extends ChangeNotifier {
  ContinuousChatController({
    required this.database,
    required this.scope,
    required this.characterName,
    this.gateway,
    this.onReplySaved,
  });

  final PersonDatabase database;
  final PersonScope scope;
  final String characterName;
  final ModelGatewayAdapter? gateway;
  final void Function(String requestId)? onReplySaved;

  final List<RawEvent> _events = [];
  List<RawEvent> get events => List.unmodifiable(_events);
  bool get isMock => gateway == null;
  bool isLoading = false;
  bool isSending = false;
  String streamedText = '';
  String? statusMessage;
  String? errorCode;
  String? activeRequestId;
  String? _retryEventId;
  String? _retryContent;
  String? _retryOf;
  bool _unknownResult = false;
  bool _cancelRequested = false;
  bool _disposed = false;
  int _serial = 0;

  bool get canRetry => !isSending && _retryEventId != null && !_unknownResult;
  bool get canReconcile =>
      !isSending && _unknownResult && gateway != null && _retryOf != null;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  /// Reads the real SQLite history in sequence; memory archive never hides it.
  Future<void> load() async {
    isLoading = true;
    _emit();
    try {
      final collected = <RawEvent>[];
      var after = 0;
      while (true) {
        final page = await database.rawEventsFor(
          scope: scope,
          afterSequence: after,
          limit: 250,
        );
        collected.addAll(page);
        if (page.isEmpty || page.length < 250) break;
        after = page.last.sequence;
      }
      _events
        ..clear()
        ..addAll(collected);
      errorCode = null;
    } catch (error) {
      errorCode = 'HISTORY_LOAD_FAILED';
      statusMessage = '读取历史失败：$error';
    } finally {
      isLoading = false;
      _emit();
    }
  }

  String _nextRequestId() =>
      'req-${DateTime.now().toUtc().microsecondsSinceEpoch}-${_serial++}';

  Future<void> send(String content) async {
    if (isSending || content.trim().isEmpty) return;
    await _runTurn(content: content.trim());
  }

  Future<void> retry() async {
    if (!canRetry) return;
    await _runTurn(
      content: _retryContent!,
      originalEventId: _retryEventId!,
      retryOf: _retryOf,
    );
  }

  Future<void> _runTurn({
    required String content,
    String? originalEventId,
    String? retryOf,
  }) async {
    final requestId = _nextRequestId();
    final userEventId = originalEventId ?? 'user-$requestId';
    isSending = true;
    _cancelRequested = false;
    activeRequestId = requestId;
    streamedText = '';
    statusMessage = isMock ? '离线 Mock 回复生成中' : '正在等待模型回复';
    errorCode = null;
    _retryContent = null;
    _retryEventId = null;
    _retryOf = null;
    _unknownResult = false;
    _emit();

    try {
      ModelTurnResult result;
      if (gateway == null) {
        final inserted = await database.registerGeneration(
          scope: scope,
          requestId: requestId,
          retryOf: retryOf,
        );
        if (!inserted) throw StateError('Request ID already exists');
        if (originalEventId == null) {
          await database.appendEvent(
            scope: scope,
            eventId: userEventId,
            speaker: 'user',
            content: content,
            requestId: requestId,
          );
        }
        await load();
        // An explicit, deterministic local fallback; never call it real AI.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_cancelRequested) {
          await database.setGenerationStatus(
            scope: scope,
            requestId: requestId,
            status: 'cancelled',
          );
          result = ModelTurnResult(
            scope: scope,
            requestId: requestId,
            status: ModelTurnStatus.cancelled,
          );
        } else {
          final reply = '【离线 Mock】$characterName 收到你的消息：$content';
          await database.completeGeneration(
            scope: scope,
            requestId: requestId,
            eventId: 'assistant-$requestId',
            content: reply,
          );
          result = ModelTurnResult(
            scope: scope,
            requestId: requestId,
            status: ModelTurnStatus.completed,
            content: reply,
          );
        }
      } else {
        result = await gateway!.sendTurn(
          scope: scope,
          requestId: requestId,
          userEventId: userEventId,
          content: content,
          retryOf: retryOf,
          onUpdate: (update) {
            if (update.scope != scope || update.requestId != activeRequestId) {
              return;
            }
            if (update.type == ModelTurnUpdateType.delta) {
              streamedText += update.delta ?? '';
              _emit();
            }
          },
        );
      }

      // A late response always belongs to the original scope; never another
      // character's visible history or message stream.
      if (activeRequestId != requestId) return;
      switch (result.status) {
        case ModelTurnStatus.completed:
          statusMessage = isMock ? '离线 Mock · 已保存' : '已完成并保存';
          if (!_disposed && !isMock) onReplySaved?.call(requestId);
          break;
        case ModelTurnStatus.failed:
          statusMessage = '回复失败，可点击重试';
          errorCode = result.errorCode ?? 'MODEL_FAILED';
          _rememberRetry(userEventId, content, requestId);
          break;
        case ModelTurnStatus.cancelled:
          statusMessage = '已取消回复，原始消息已保存';
          _rememberRetry(userEventId, content, requestId);
          break;
        case ModelTurnStatus.unknown:
          statusMessage = '结果尚不明确，请先查询状态，避免重复发送';
          errorCode = result.errorCode ?? 'RESULT_UNKNOWN';
          _rememberRetry(userEventId, content, requestId);
          _unknownResult = true;
          break;
      }
    } catch (error) {
      errorCode = 'TURN_EXCEPTION';
      statusMessage = '发送异常：$error';
      // The adapter may have committed the user event before an exception.
      // The same event ID is reused so retry cannot duplicate the input.
      final existing = await database.rawEventById(
        scope: scope,
        eventId: userEventId,
      );
      if (existing != null) {
        _rememberRetry(userEventId, content, requestId);
        // A transport exception can be an uncertain delivery. Never blindly
        // retry a remote request before reconciling its ID.
        _unknownResult = gateway != null;
      }
    } finally {
      if (activeRequestId == requestId) {
        isSending = false;
        activeRequestId = null;
        streamedText = '';
        await load();
        _emit();
      }
    }
  }

  void _rememberRetry(String userEventId, String content, String requestId) {
    _retryEventId = userEventId;
    _retryContent = content;
    _retryOf = requestId;
  }

  Future<void> cancel() async {
    if (!isSending || activeRequestId == null) return;
    _cancelRequested = true;
    final requestId = activeRequestId!;
    statusMessage = '正在取消回复';
    _emit();
    if (gateway == null) return;
    try {
      final result = await gateway!.cancelTurn(
        scope: scope,
        requestId: requestId,
      );
      if (activeRequestId == requestId &&
          result.status == ModelTurnStatus.unknown) {
        statusMessage = '取消结果不确定，请先查询状态';
      }
    } catch (_) {
      if (activeRequestId == requestId) {
        statusMessage = '取消确认失败，请查询请求状态';
      }
    }
    _emit();
  }

  Future<void> reconcile() async {
    if (!canReconcile) return;
    final requestId = _retryOf!;
    isSending = true;
    statusMessage = '正在查询既有请求状态';
    _emit();
    try {
      final result = await gateway!.reconcileTurn(
        scope: scope,
        requestId: requestId,
      );
      switch (result.status) {
        case ModelTurnStatus.completed:
          statusMessage = '已恢复服务器完成的回复';
          _retryEventId = null;
          _retryContent = null;
          _retryOf = null;
          _unknownResult = false;
          break;
        case ModelTurnStatus.failed:
        case ModelTurnStatus.cancelled:
          statusMessage = '已确认请求结束，可以重试';
          _unknownResult = false;
          break;
        case ModelTurnStatus.unknown:
          statusMessage = '服务器仍未确认结果，请稍后重查';
          break;
      }
    } catch (_) {
      statusMessage = '状态查询失败，请稍后重查';
    } finally {
      isSending = false;
      await load();
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
