import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live2d_avatar/live2d_avatar.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('render a real Mark cover and capture MOC parameter ranges', (
    tester,
  ) async {
    final c = Live2dController();
    await c.create();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Live2dView(controller: c)),
      ),
    );
    await c.load('assets/live2d/Mark/Mark.model3.json');
    await c.setPose({
      for (final p in c.parameters.values) p.id: p.defaultValue,
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final source = await Live2dController.channel.invokeMethod<String>(
      'capture',
    );
    final dir = await getApplicationDocumentsDirectory();
    await File(source!).copy('${dir.path}/mark-preview.png');
    final stats = await c.stats();
    expect(stats['error'], isNull);
    await File('${dir.path}/avatar-package-fixture.json')
        .writeAsString(jsonEncode(stats));
    await c.close();
    await tester.pumpWidget(const SizedBox());
  });
}
