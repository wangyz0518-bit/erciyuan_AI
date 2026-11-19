import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.js_interop) '../../../web/browser_http.dart';

import 'package:flutter/foundation.dart';

import '../../audio/domain/audio_ports.dart';

/// One character page owns the network request and native playback together.
class CharacterReplyPlayback extends ChangeNotifier {
  CharacterReplyPlayback(this.turnsUri, this.token, this.player);
  final Uri turnsUri;
  final String token;
  final AudioPcmPlaybackPort player;
  HttpClient? _client;
  bool _nativeStarted = false;
  bool _disposed = false;
  String status = '';
  bool speaking = false;
  double mouthLevel = 0;
  final _mouthClock = Stopwatch();

  Future<void> play(String requestId) async {
    if (_disposed || _client != null) return;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    _client = client;
    status = '正在准备角色声音';
    notifyListeners();
    try {
      final request = await client.postUrl(
        turnsUri.resolve('${Uri.encodeComponent(requestId)}/speech'),
      );
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok ||
          response.headers.contentType?.mimeType != 'application/x-ndjson') {
        throw const FormatException('Speech unavailable');
      }
      final demo = response.headers.value('x-voice-mode') == 'demo';
      bool received = false;
      await for (final line
          in response
              .timeout(const Duration(seconds: 35))
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (_client != client) return;
        final frame = jsonDecode(line);
        if (frame is! Map) throw const FormatException('Invalid frame');
        if (frame['done'] == true && received) {
          await player.end(requestId);
          if (_client != client) return;
          _nativeStarted = false;
          status = demo ? '测试音播放结束' : '角色朗读结束';
          return;
        }
        if (frame['pcm'] is! String) {
          throw const FormatException('Incomplete audio');
        }
        final bytes = base64Decode(frame['pcm'] as String);
        if (bytes.isEmpty || bytes.length.isOdd || bytes.length > 9600) {
          throw const FormatException('Invalid PCM');
        }
        if (!received) {
          _nativeStarted = true;
          await player.start(requestId);
          if (_client != client) return;
          received = true;
          speaking = true;
          status = demo ? '正在播放离线测试音' : '正在用角色音色朗读';
          notifyListeners();
        }
        await player.append(requestId, bytes);
        if (_client == client &&
            (!_mouthClock.isRunning || _mouthClock.elapsedMilliseconds >= 75)) {
          final samples = bytes.buffer.asByteData(
            bytes.offsetInBytes,
            bytes.length,
          );
          var total = 0, count = 0;
          for (var i = 0; i < bytes.length; i += 32) {
            total += samples.getInt16(i, Endian.little).abs();
            count++;
          }
          mouthLevel = (total / count / 4500).clamp(0.0, 1.0);
          _mouthClock
            ..reset()
            ..start();
          notifyListeners();
        }
      }
      throw const FormatException('Missing end frame');
    } catch (_) {
      if (_client == client) status = '角色声音不可用，文字回复已保留';
    } finally {
      client.close(force: true);
      if (_client == client) {
        await _stopNative();
        if (_client == client) {
          _client = null;
          speaking = false;
          mouthLevel = 0;
          if (!_disposed) notifyListeners();
        }
      }
    }
  }

  Future<void> _stopNative() async {
    if (!_nativeStarted) return;
    _nativeStarted = false;
    try {
      await player.stop();
    } catch (_) {
      // The device can already have released its audio route.
    }
  }

  Future<void> stop() {
    final client = _client;
    _client = null;
    client?.close(force: true);
    speaking = false;
    mouthLevel = 0;
    status = '';
    final stopped = _stopNative();
    if (!_disposed && client != null) notifyListeners();
    return stopped;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
