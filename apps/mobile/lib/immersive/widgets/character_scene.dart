import 'package:material_ui/material_ui.dart';

import '../avatar.dart';

class CharacterScene extends StatelessWidget {
  const CharacterScene({
    super.key,
    required this.role,
    required this.full,
    required this.replying,
    required this.foreground,
  });
  final String role;
  final bool full, replying, foreground;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Center(
      child: FractionallySizedBox(
        widthFactor: full ? .65 : .95,
        heightFactor: full ? .65 : .9,
        child: Avatar(
          role: role,
          emotion: '平静',
          activity: replying ? '等待' : '待机',
          animate: foreground && !MediaQuery.disableAnimationsOf(context),
        ),
      ),
    );
    final name = 'chat-${full ? 'full' : 'half'}${replying ? '-reply' : ''}';
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF403448), Color(0xFF171620)],
              ),
            ),
          ),
          if (role == 'xing' && full)
            Image.asset(
              'assets/immersive_chat/chat-floor.png',
              fit: BoxFit.cover,
            ),
          if (role == 'xing')
            Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: full ? .805 : 1,
                child: Image.asset(
                  'assets/immersive_chat/$name.png',
                  key: ValueKey(name),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, _, _) => fallback(),
                ),
              ),
            )
          else
            fallback(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .3, .55, 1],
                colors: [
                  Color(0x70171620),
                  Color(0x00171620),
                  Color(0x20171620),
                  Color(0xF0171620),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
