import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:companion_poc/widgets/chat_composer.dart';

void main() {
  testWidgets(
    'release still cancels while native startup disables new presses',
    (tester) async {
      var enabled = true;
      var starts = 0;
      final releases = <bool>[];
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                refresh = setState;
                return Center(
                  child: SizedBox(
                    width: 240,
                    child: HoldToRecord(
                      enabled: enabled,
                      label: '按住说话',
                      start: () => starts++,
                      end: releases.add,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final target = find.byKey(const Key('hold-record'));
      final finger = await tester.startGesture(tester.getCenter(target));
      refresh(() => enabled = false);
      await tester.pump();
      await finger.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(find.text('松开取消'), findsOneWidget);
      await finger.up();
      expect(starts, 1);
      expect(releases, [false]);
      await tester.tap(target);
      expect(starts, 1);
    },
  );

  testWidgets('second pointer cannot end another fingers recording', (
    tester,
  ) async {
    var starts = 0;
    final releases = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: HoldToRecord(
                enabled: true,
                label: '按住说话',
                start: () => starts++,
                end: releases.add,
              ),
            ),
          ),
        ),
      ),
    );
    final point = tester.getCenter(find.byKey(const Key('hold-record')));
    final first = await tester.startGesture(point, pointer: 1);
    final second = await tester.startGesture(point, pointer: 2);
    await second.up();
    expect(releases, isEmpty);
    await first.up();
    expect(starts, 1);
    expect(releases, [true]);
    final cancelled = await tester.startGesture(point, pointer: 3);
    await cancelled.cancel();
    expect(releases, [true, false]);
  });
}
