import 'dart:async';

import 'package:erciyuan_mobile/features/audio/data/platform_audio_adapters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.erciyuan/test-native-pcm');
  late List<MethodCall> received;

  setUp(() {
    received = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received.add(call);
          if (call.method == 'end') return <String, Object>{'frames': 2};
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'start, append, drain, stop and dispose share the iOS/Android protocol',
    () async {
      final player = NativePcmPlayback(channel: channel, isSupported: true);
      await player.start('owner-character-1', bufferMs: 400);
      await player.append(
        'owner-character-1',
        Uint8List.fromList([1, 0, 2, 0]),
      );
      await player.end('owner-character-1');
      await player.stop();
      await player.dispose();

      expect(received.map((call) => call.method).toList(), [
        'stop',
        'start',
        'append',
        'end',
        'stop',
        'stop',
      ]);
      expect(
        (received[1].arguments as Map<Object?, Object?>)['id'],
        'owner-character-1',
      );
      await expectLater(player.start('after-dispose'), throwsStateError);
    },
  );

  test(
    'stale stream and invalid PCM packets never reach native layer',
    () async {
      final player = NativePcmPlayback(channel: channel, isSupported: true);
      addTearDown(player.dispose);
      await player.start('current');
      await expectLater(
        player.append('stale', Uint8List.fromList([1, 0])),
        throwsStateError,
      );
      await expectLater(
        player.append('current', Uint8List(1)),
        throwsArgumentError,
      );
      await expectLater(
        player.append('current', Uint8List(0)),
        throwsArgumentError,
      );
      expect(received.where((call) => call.method == 'append'), isEmpty);
      await player.stop();
      await expectLater(
        player.append('current', Uint8List.fromList([1, 0])),
        throwsStateError,
      );
    },
  );

  test('stop invalidates a native start that completes later', () async {
    final nativeStart = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received.add(call);
          if (call.method == 'start') await nativeStart.future;
          return null;
        });

    final player = NativePcmPlayback(channel: channel, isSupported: true);
    addTearDown(player.dispose);
    final pendingStart = player.start('late');
    await Future<void>.delayed(Duration.zero);
    expect(received.map((call) => call.method), contains('start'));

    await player.stop();
    nativeStart.complete();
    await pendingStart;
    expect(
      received.where((call) => call.method == 'stop').length,
      greaterThanOrEqualTo(3),
    );
    await expectLater(
      player.append('late', Uint8List.fromList([1, 0])),
      throwsStateError,
    );
  });

  test(
    'unsupported desktop rejects native start without invoking channel',
    () async {
      final player = NativePcmPlayback(channel: channel, isSupported: false);
      addTearDown(player.dispose);
      await expectLater(player.start('desktop'), throwsUnsupportedError);
      expect(received, isEmpty);
    },
  );
}
