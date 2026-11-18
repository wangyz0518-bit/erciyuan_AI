import 'package:material_ui/material_ui.dart';

/// Deliberate non-Live2D fallback until licensed models are installed.
enum AvatarSceneMotion { idle, listening, talking }

class AvatarFallbackScene extends StatelessWidget {
  const AvatarFallbackScene({
    required this.characterId,
    required this.characterName,
    required this.motion,
    super.key,
  });

  final String characterId;
  final String characterName;
  final AvatarSceneMotion motion;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${characterName}静态角色占位，Live2D 未配置',
    child: AnimatedScale(
      key: const ValueKey('avatar-fallback-motion'),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      scale: motion == AvatarSceneMotion.talking
          ? 1.08
          : motion == AvatarSceneMotion.listening
          ? 1.03
          : 1,
      child: CircleAvatar(
        radius: 51,
        backgroundColor: const Color(0xFFB9A3E4),
        child: Icon(
          characterId == 'star' ? Icons.star_rounded : Icons.dark_mode_rounded,
          size: 67,
          color: const Color(0xFF2A2442),
        ),
      ),
    ),
  );
}
