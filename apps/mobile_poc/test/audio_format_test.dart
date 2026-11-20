import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:companion_poc/audio_controller.dart';

void main() {
  test('silence is not accepted as a working microphone signal', () {
    final tone = makeTone();
    expect(pcmRms(tone), greaterThan(0.05));
    tone.fillRange(44, tone.length, 0);
    expect(pcmRms(tone), 0);
    expect(pcmRms(Uint8List(20)), 0);
  });
}
