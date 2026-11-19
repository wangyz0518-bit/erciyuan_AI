import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A single utterance. Closing without a commit discards its result.
class VoiceInputStream {
  VoiceInputStream(this.uri, this.token, this.onPartial) {
    _final.future.ignore();
    unawaited(_connect());
  }
  final Uri uri;
  final String token;
  final void Function(String) onPartial;
  final _final = Completer<String>();
  final _pending = <Uint8List>[];
  WebSocket? _socket;
  bool _ready = false, _committed = false, _closed = false;
  int bytes = 0;
  Future<String> get result => _final.future;

  Future<void> _connect() async {
    try {
      final connecting = WebSocket.connect(
        uri.toString(),
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );
      unawaited(
        connecting.then<void>((socket) {
          if (_closed) unawaited(socket.close());
        }, onError: (Object _) {}),
      );
      final socket = await connecting.timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw const SocketException('ASR timeout'),
      );
      if (_closed) {
        await socket.close();
        return;
      }
      _socket = socket;
      await for (final message in socket.timeout(const Duration(seconds: 70))) {
        if (_closed) return;
        final frame = jsonDecode(message as String);
        switch (frame['type']) {
          case 'ready':
            if (_ready) throw const FormatException();
            _ready = true;
            for (final pcm in _pending) {
              socket.add(pcm);
            }
            _pending.clear();
            if (_committed) socket.add('commit');
          case 'partial':
            onPartial(frame['text'] as String);
          case 'final':
            if (!_committed || !_ready) throw const FormatException();
            _final.complete(frame['text'] as String);
            return;
          default:
            throw StateError('语音识别不可用');
        }
      }
    } catch (_) {
      if (!_final.isCompleted) _final.completeError(StateError('语音识别未完成'));
    } finally {
      cancel();
    }
  }

  void add(Uint8List pcm) {
    if (_closed || _committed) return;
    bytes += pcm.length;
    if (bytes > 960000) {
      cancel();
      return;
    }
    if (_ready) {
      _socket!.add(pcm);
    } else {
      _pending.add(pcm);
    }
  }

  void commit() {
    if (_closed || _committed) return;
    if (bytes < 6400) {
      cancel();
      return;
    }
    _committed = true;
    if (_ready) _socket!.add('commit');
  }

  void cancel() {
    if (_closed) return;
    _closed = true;
    _pending.clear();
    if (!_final.isCompleted) _final.completeError(StateError('语音输入已结束'));
    unawaited(_socket?.close());
  }
}
