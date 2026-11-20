import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:erciyuan_mobile/features/audio/domain/audio_ports.dart';
import 'package:erciyuan_mobile/features/voice/data/character_reply_playback.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player implements AudioPcmPlaybackPort {
  final calls = <String>[];
  final appended = Completer<void>();

  @override
  Future<void> start(String id, {int bufferMs = 400}) async =>
      calls.add('start $id');
  @override
  Future<void> append(String id, Uint8List bytes) async {
    expect(bytes, [1, 2, 3, 4]);
    calls.add('append $id');
    if (!appended.isCompleted) appended.complete();
  }

  @override
  Future<void> end(String id) async => calls.add('end $id');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> dispose() async {}
}

void main() {
  for (final outcome in ['complete', 'truncated', 'switched']) {
    test('scoped saved-reply playback: $outcome', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final release = Completer<void>();
      final player = _Player();
      final uri = Uri.parse(
        'http://127.0.0.1:${server.port}/v1/characters/star/turns/',
      );
      final speech = CharacterReplyPlayback(uri, 'local-fixture', player);
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        speech.dispose();
        await server.close(force: true);
      });
      server.listen((req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v1/characters/star/turns/test-id/speech');
        expect(req.headers.value('authorization'), 'Bearer local-fixture');
        final response = req.response;
        response.headers.contentType = ContentType('application', 'x-ndjson');
        response.headers.set('x-voice-mode', 'demo');
        response.bufferOutput = false;
        response.write('{"pcm":"AQIDBA=="}\n');
        await response.flush();
        if (outcome == 'switched') await release.future;
        if (outcome == 'complete') response.write('{"done":true}\n');
        await response.close();
      });
      final done = speech.play('test-id');
      if (outcome == 'switched') {
        await player.appended.future;
        await speech.stop();
        release.complete();
      }
      await done;
      expect(player.calls, [
        'start test-id',
        'append test-id',
        outcome == 'complete' ? 'end test-id' : 'stop',
      ]);
      expect(speech.speaking, isFalse);
      expect(speech.status, switch (outcome) {
        'complete' => '测试音播放结束',
        'switched' => '',
        _ => '角色声音不可用，文字回复已保留',
      });
    });
  }
}
