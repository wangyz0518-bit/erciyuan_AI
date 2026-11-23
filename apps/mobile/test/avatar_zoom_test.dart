import 'package:erciyuan_mobile/features/avatar/presentation/avatar_zoom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'pinch and slider share zoom, preserve one-finger input and clamp at both limits',
    (tester) async {
      var zoom = fullAvatarZoom;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, update) {
              void change(double value) => update(() => zoom = value);
              return Scaffold(
                body: AvatarZoomGesture(
                  zoom: zoom,
                  onChanged: change,
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: AvatarZoomControls(
                        zoom: zoom,
                        halfZoom: sproutHalfZoom,
                        onChanged: change,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.dragFrom(const Offset(300, 220), const Offset(40, 10));
      expect(zoom, fullAvatarZoom);

      Future<void> pinch(double initialDistance, List<double> distances) async {
        const center = Offset(390, 240);
        Offset offset(double distance) => Offset(distance / 2, 0);
        final left = await tester.startGesture(
          center - offset(initialDistance),
        );
        final right = await tester.startGesture(
          center + offset(initialDistance),
        );
        for (final distance in distances) {
          await left.moveTo(center - offset(distance));
          await right.moveTo(center + offset(distance));
          await tester.pump();
        }
        await left.up();
        await right.up();
        await tester.pump();
      }

      await pinch(70, [100, 140, 220, 400, 550]);
      expect(zoom, maxAvatarZoom);
      await pinch(400, [340, 260, 180, 100, 50]);
      expect(zoom, minAvatarZoom);

      await tester.tap(find.byKey(const Key('avatar-zoom-button')));
      await tester.pumpAndSettle();
      final slider = find.byKey(const Key('avatar-zoom-slider'));
      await tester.tapAt(tester.getCenter(slider));
      await tester.pump();
      expect(zoom, closeTo(1.9, .05));
      expect(tester.widget<Slider>(slider).value, zoom);
      await tester.tap(find.byTooltip('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera-toggle')));
      await tester.pump();
      expect(zoom, fullAvatarZoom);
      await tester.tap(find.byKey(const Key('camera-toggle')));
      await tester.pump();
      expect(zoom, sproutHalfZoom);
    },
  );
}
