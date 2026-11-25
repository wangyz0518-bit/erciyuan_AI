import 'package:erciyuan_mobile/community/role_portrait.dart';
import 'package:erciyuan_mobile/immersive/avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'library and share artwork match the platform starter appearances',
    (tester) async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      Future<void> show(
        String avatar,
        TargetPlatform platform, {
        String? portrait,
      }) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.square(
                dimension: 88,
                child: RoleArtwork(avatar, portrait: portrait),
              ),
            ),
          ),
        );
      }

      String asset() =>
          (tester.widget<Image>(find.byType(Image)).image as AssetImage)
              .assetName;
      await show('star', TargetPlatform.android);
      expect(asset(), 'assets/dragon_avatar/idle.webp');
      await show('star', TargetPlatform.iOS);
      expect(asset(), 'assets/immersive_chat/chat-half.png');
      await show('sprout', TargetPlatform.android);
      expect(asset(), 'assets/sprout_avatar/portrait.webp');
      await show('moon', TargetPlatform.android);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter is FacePainter &&
              (w.painter! as FacePainter).role == 'yue',
        ),
        findsOneWidget,
      );
      await show(
        'moon',
        TargetPlatform.android,
        portrait: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+X1kAAAAASUVORK5CYII=',
      );
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<MemoryImage>(),
      );
    },
  );
}
