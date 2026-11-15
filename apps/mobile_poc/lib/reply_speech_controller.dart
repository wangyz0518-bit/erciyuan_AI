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
      if (id != null) unawaited(gateway.cancel(id));
      busy = false;
      failed = false;
      status = '';
    }
    _notify();
  }

  Future<void> speak(String replyId, String character) async {
    final stopping = audio.stopAll();
    final expectedEpoch = audio.operationEpoch;
    await stopping;
    if (_closed || audio.operationEpoch != expectedEpoch) return;
    final generation = ++_generation;
    _audioEpoch = audio.operationEpoch;
    _replyId = replyId;
    _character = character;
    final request = _request = ModelGateway.requestId();
    busy = true;
    failed = false;
    status = '正在生成语音…';
    _notify();
    try {
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
      busy = false;
      failed = true;
      _request = null;
      status = '语音暂不可用，文字已保留';
    }
    _notify();
  }

  Future<void> retry() async {
    if (_replyId != null && _character != null && !busy) {
      await speak(_replyId!, _character!);
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    audio.removeListener(_audioChanged);
    if (_request != null) unawaited(gateway.cancel(_request!));
    super.dispose();
  }
}
