import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_controller.dart';
import 'model_gateway.dart';

class ReplySpeechController extends ChangeNotifier {
  ReplySpeechController(this.gateway, this.audio) {
    audio.addListener(_audioChanged);
  }
  final ModelGateway gateway;
  final AudioController audio;
  String status = '';
  bool busy = false, failed = false;
  String? _replyId, _character, _request;
  int _generation = 0, _audioEpoch = -1;
  bool _closed = false;

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _audioChanged() {
    if (_audioEpoch != -1 && audio.operationEpoch != _audioEpoch) {
      _generation++;
      final id = _request;
      _request = null;
      _audioEpoch = -1;
      if (id != null) unawaited(gateway.cancelSpeech(id));
      busy = false;
      failed = false;
      status = '';
    }
    _notify();
  }

  Future<void> speak(
    String replyId,
    String character, {
    bool retry = false,
  }) async {
    final stopping = audio.stopAll();
    final expectedEpoch = audio.operationEpoch;
    await stopping;
    if (_closed || audio.operationEpoch != expectedEpoch) return;
    final generation = ++_generation;
    _audioEpoch = audio.operationEpoch;
    _replyId = replyId;
    _character = character;
    final request = _request = gateway.useV2
        ? replyId
        : ModelGateway.requestId();
    busy = true;
    failed = false;
    status = '正在生成语音…';
    _notify();
    try {
      if (gateway.useV2) {
        final retryStart =
            gateway.streaming.turns[replyId]?.clock.elapsedMicroseconds;
        final turn = retry
            ? await gateway.streaming.retry(replyId, ModelGateway.requestId())
            : gateway.streaming.turns[replyId];
        if (turn == null || turn.speechId.isEmpty) {
          throw const GatewayException('VOICE_UNAVAILABLE');
        }
        final baseline = retry
            ? (retryStart ?? turn.clock.elapsedMicroseconds) / 1000
            : turn.completedAtMs!;
        final playerStart = turn.clock.elapsedMicroseconds / 1000;
        await audio.startPcm(turn.speechId, _audioEpoch);
        bool completed = false;
        await for (final event in turn.audio.stream.timeout(
          const Duration(seconds: 100),
        )) {
          if (_closed || generation != _generation) return;
          switch (event['event']) {
            case 'audio.chunk':
              await audio.appendPcm(
                turn.speechId,
                event['pcm'] as Uint8List,
                _audioEpoch,
              );
              status = audio.playing ? '正在朗读' : '正在缓冲声音…';
              _notify();
            case 'audio.completed':
              await audio.endPcm(turn.speechId, _audioEpoch);
              completed = true;
            case 'audio.failed':
            case 'audio.cancelled':
              throw GatewayException(event['code'] as String? ?? 'CANCELLED');
          }
        }
        if (!completed) throw const GatewayException('AUDIO_INCOMPLETE');
        if (_closed || generation != _generation) return;
        audio.streamMetrics.addAll(turn.metrics);
        final output = audio.streamMetrics['firstOutputMs'] as num?;
        if (output != null) {
          audio.streamMetrics['ttsToOutputMs'] =
              playerStart + output - baseline;
          audio.streamMetrics['sendToOutputMs'] = playerStart + output;
        }
        status = '朗读结束';
        busy = false;
        _request = null;
        _notify();
        return;
      }
      final bytes = await gateway.speech(
        requestId: request,
        replyRequestId: replyId,
        character: character,
      );
      if (_closed || generation != _generation) return;
      status = '正在朗读';
      await audio.playGenerated(bytes, expectedEpoch: _audioEpoch);
      if (_closed || generation != _generation) return;
      if (audio.status.contains('失败')) {
        throw const GatewayException('PLAYBACK_FAILED');
      }
      busy = false;
      _request = null;
    } catch (_) {
      if (_closed || generation != _generation) return;
      if (gateway.useV2) {
        await audio.pcm.stop();
        audio.playing = false;
        unawaited(gateway.cancelSpeech(replyId));
      }
      busy = false;
      failed = true;
      _request = null;
      status = '语音暂不可用，文字已保留';
    }
    _notify();
  }

  Future<void> retry() async {
    if (_replyId != null && _character != null && !busy) {
      await speak(_replyId!, _character!, retry: true);
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    audio.removeListener(_audioChanged);
    if (_request != null) unawaited(gateway.cancelSpeech(_request!));
    super.dispose();
  }
}
