import 'dart:async';

import 'package:material_ui/material_ui.dart';

enum AvatarSceneMotion { idle, listening, thinking, talking }

class AvatarFallbackScene extends StatelessWidget {
  const AvatarFallbackScene({
    required this.characterId,
    required this.characterName,
    required this.motion,
    this.mouth = 0,
    super.key,
  });

  final String characterId;
  final String characterName;
  final AvatarSceneMotion motion;
  final double mouth;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$characterName内置人物形象',
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
        child: AnimatedRotation(
          turns: motion == AvatarSceneMotion.listening
              ? -0.045
              : motion == AvatarSceneMotion.thinking
              ? 0.055
              : 0,
          duration: const Duration(milliseconds: 300),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                characterId == 'star'
                    ? Icons.star_rounded
                    : Icons.dark_mode_rounded,
                size: 86,
                color: const Color(0xFF403355),
              ),
              Transform.translate(
                offset: Offset(characterId == 'star' ? 0 : -7, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AvatarEyes(motion: motion),
                    const SizedBox(height: 3),
                    AnimatedContainer(
                      key: const ValueKey('avatar-mouth'),
                      duration: const Duration(milliseconds: 90),
                      width: 7,
                      height: motion == AvatarSceneMotion.talking
                          ? 2 + 7 * mouth.clamp(0, 1)
                          : 2,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC4CD),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AvatarEyes extends StatefulWidget {
  const _AvatarEyes({required this.motion});
  final AvatarSceneMotion motion;

  @override
  State<_AvatarEyes> createState() => _AvatarEyesState();
}

class _AvatarEyesState extends State<_AvatarEyes> {
  Timer? _blink;
  bool _closed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _blink?.cancel();
    _closed = false;
    if (TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context)) {
      _scheduleBlink();
    }
  }

  void _scheduleBlink() {
    _blink = Timer(
      _closed ? const Duration(milliseconds: 140) : const Duration(seconds: 4),
      () {
        setState(() => _closed = !_closed);
        _scheduleBlink();
      },
    );
  }

  @override
  void dispose() {
    _blink?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 2; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 3,
            height: _closed || widget.motion == AvatarSceneMotion.thinking
                ? 2
                : 5,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
    ],
  );
}
