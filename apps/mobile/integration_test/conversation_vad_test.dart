import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native Silero classifies a silent 32 ms capture frame', (
    _,
  ) async {
    const detector = MethodChannel('dev.erciyuan/vad');
    await detector.invokeMethod<void>('reset');
    final score = await detector.invokeMethod<double>(
      'probability',
      Uint8List(1024),
    );
    expect(score, inInclusiveRange(0, 0.35));
  });
}
