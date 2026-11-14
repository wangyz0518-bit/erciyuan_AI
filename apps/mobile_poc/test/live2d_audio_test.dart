import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:companion_poc/live2d_preview_page.dart';

void main() {
  test('PCM envelope handles padded chunks, silence and loudness', () {
    final b = ByteData(58 + 3200);
    b.setUint32(0, 0x52494646);
    b.setUint32(4, b.lengthInBytes - 8, Endian.little);
    b.setUint32(8, 0x57415645);
    b.setUint32(12, 0x4a554e4b);
    b.setUint32(16, 5, Endian.little); // odd JUNK chunk + padding
    b.setUint32(26, 0x666d7420);
    b.setUint32(30, 16, Endian.little);
    b.setUint16(34, 1, Endian.little);
    b.setUint16(36, 1, Endian.little);
    b.setUint32(38, 16000, Endian.little);
    b.setUint16(48, 16, Endian.little);
    b.setUint32(50, 0x64617461);
    b.setUint32(54, 3200, Endian.little);
    for (int i = 800; i < 1600; i++) {
      b.setInt16(58 + 2 * i, 10000, Endian.little);
    }
    expect(wavEnvelope(b), [0, 1]);
    expect(() => wavEnvelope(ByteData(10)), throwsFormatException);
    b.setUint32(54, 999999, Endian.little);
    expect(() => wavEnvelope(b), throwsFormatException);
  });
}
