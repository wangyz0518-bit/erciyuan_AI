import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../immersive/avatar.dart' show FacePainter;

/// The same role art is used in the library, shares, and the import preview.
class RoleArtwork extends StatelessWidget {
  const RoleArtwork(this.avatar, {this.portrait, super.key});

  final String avatar;
  final String? portrait;

  @override
  Widget build(BuildContext context) {
    final custom = portrait;
    if (custom == null && avatar == 'moon') {
      return ColoredBox(
        color: const Color(0xFF20373A),
        child: CustomPaint(painter: FacePainter('yue', '平静', '待机')),
      );
    }
    final asset = switch (avatar) {
      'star' when !kIsWeb && defaultTargetPlatform == TargetPlatform.android =>
        'assets/dragon_avatar/idle.webp',
      'star' => 'assets/immersive_chat/chat-half.png',
      'sprout' => 'assets/sprout_avatar/portrait.webp',
      _ => null,
    };
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(Icons.person_outline, color: colors.onSecondaryContainer),
    );
    if (custom == null && asset == null) return fallback;
    return Image(
      image: custom != null
          ? MemoryImage(base64Decode(custom))
          : AssetImage(asset!) as ImageProvider,
      fit: BoxFit.cover,
      alignment: custom == null ? const Alignment(0, -.65) : Alignment.center,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class RolePortrait extends StatelessWidget {
  const RolePortrait(this.avatar, {super.key, this.portrait});

  final String avatar;
  final String? portrait;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: 44,
      child: RoleArtwork(avatar, portrait: portrait),
    ),
  );
}
