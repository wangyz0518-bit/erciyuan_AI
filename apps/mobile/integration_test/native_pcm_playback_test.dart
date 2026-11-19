import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Exercises the actual platform MethodChannel and native PCM sink on mobile
/// simulators. This does not test a physical audio route or human-perceived
/// quality; those remain in the next-stage device acceptance issue.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.erciyuan/pcm');

  testWidgets(
    'native PCM channel accepts bounded 24 kHz mono and stops an active stream',
    (tester) async {
      const frameCount = 6000;
      final streamId = 'ci-pcm-${DateTime.now().microsecondsSinceEpoch}';
      final bytes = ByteData(frameCount * 2);
      for (var frame = 0; frame < frameCount; frame++) {
        final sample = (math.sin(2 * math.pi * 440 * frame / 24000) * 1000)
            .round();
        bytes.setInt16(frame * 2, sample, Endian.little);
      }

      await channel
          .invokeMethod<void>('start', {'id': streamId, 'bufferMs': 100})
          .timeout(const Duration(seconds: 5));
      try {
        await channel
            .invokeMethod<void>('append', {
              'id': streamId,
              'bytes': bytes.buffer.asUint8List(),
            })
            .timeout(const Duration(seconds: 5));
        // Hosted Android/iOS simulators may have no audio output device. They
        // can verify the native MethodChannel and bounded PCM enqueue, but
        // cannot prove that the output clock drained the samples. End/drain,
        // audible output and route behavior are reserved for device QA (#78).
        await channel
            .invokeMethod<void>('stop')
            .timeout(const Duration(seconds: 5));
      } finally {
        await channel.invokeMethod<void>('stop');
      }
    },
    skip: !Platform.isAndroid && !Platform.isIOS,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
