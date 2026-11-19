import 'package:erciyuan_mobile/features/avatar/presentation/avatar_fallback_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('static fallback is available without Cubism binaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AvatarFallbackScene(
            characterId: 'star',
            characterName: '小星',
            motion: AvatarSceneMotion.talking,
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('avatar-fallback-motion')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    final talking = tester.widget<AnimatedScale>(
      find.byKey(const ValueKey('avatar-fallback-motion')),
    );
    expect(talking.scale, 1.08);
  });

  testWidgets(
    'listening and idle states have distinct stable fallback motion',
    (tester) async {
      Widget scene(AvatarSceneMotion motion) => MaterialApp(
        home: Scaffold(
          body: AvatarFallbackScene(
            characterId: 'moon',
            characterName: '小月',
            motion: motion,
          ),
        ),
      );

      await tester.pumpWidget(scene(AvatarSceneMotion.listening));
      await tester.pump(const Duration(milliseconds: 300));
      var avatar = tester.widget<AnimatedScale>(
        find.byKey(const ValueKey('avatar-fallback-motion')),
      );
      expect(avatar.scale, 1.03);

      await tester.pumpWidget(scene(AvatarSceneMotion.idle));
      await tester.pump(const Duration(milliseconds: 300));
      avatar = tester.widget<AnimatedScale>(
        find.byKey(const ValueKey('avatar-fallback-motion')),
      );
      expect(avatar.scale, 1);
    },
  );
}
