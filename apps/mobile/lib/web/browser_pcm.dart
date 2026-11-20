import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../features/audio/domain/audio_ports.dart';

class BrowserPcmPlayback implements AudioPcmPlaybackPort {
  web.AudioContext? _context;
  String? _id;
  double _next = 0;
  final _scheduled = <web.AudioBufferSourceNode>{};
  Future<void> unlock() async {
    final context = _context ??= web.AudioContext();
    await context.resume().toDart.timeout(const Duration(seconds: 3));
  }

  @override
  Future<void> start(String streamId, {int bufferMs = 400}) async {
    await stop();
    await unlock();
    _id = streamId;
    _next = _context!.currentTime + .05;
  }

  @override
  Future<void> append(String streamId, Uint8List pcm16le) async {
    if (_id != streamId) return;
    final context = _context!;
    final count = pcm16le.length ~/ 2;
    final buffer = context.createBuffer(1, count, 24000);
    final samples = Float32List(count);
    final data = ByteData.sublistView(pcm16le);
    for (var i = 0; i < count; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
    }
    buffer.copyToChannel(samples.toJS, 0);
    final source = context.createBufferSource()..buffer = buffer;
    source.connect(context.destination);
    _scheduled.add(source);
    source.onended = ((web.Event _) {
      _scheduled.remove(source);
      source.disconnect();
    }).toJS;
    if (_next < context.currentTime) _next = context.currentTime;
    source.start(_next);
    _next += count / 24000;
    // Limit queued audio so the displayed mouth level follows what is playing.
    final lead = _next - context.currentTime - .12;
    if (lead > 0) {
      await Future<void>.delayed(Duration(milliseconds: (lead * 1000).round()));
    }
  }

  @override
  Future<void> end(String streamId) async {
    while (_id == streamId && _scheduled.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 35));
    }
    if (_id == streamId) _id = null;
  }

  @override
  Future<void> stop() async {
    _id = null;
    for (final source in _scheduled.toList()) {
      source.stop();
    }
    _scheduled.clear();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _context?.close().toDart;
    _context = null;
  }
}

AudioPcmPlaybackPort createReplyPlayer({required bool Function() inCall}) =>
    BrowserPcmPlayback();
Future<void> unlockReplyPlayer(AudioPcmPlaybackPort? player) async {
  if (player is BrowserPcmPlayback) await player.unlock();
}
