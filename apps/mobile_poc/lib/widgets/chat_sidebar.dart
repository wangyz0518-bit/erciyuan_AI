import 'dart:ui';

import 'package:material_ui/material_ui.dart';

class ChatSidebar extends StatelessWidget {
  const ChatSidebar({super.key, required this.close, required this.select});
  final VoidCallback close;
  final ValueChanged<String> select;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          key: const Key('sidebar-scrim'),
          onTap: close,
          child: Container(color: const Color(0x29100D16)),
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: 72,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
            child: Container(
              key: const Key('sidebar-panel'),
              color: const Color(0xDC211B26),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      IconButton(
                        key: const Key('close-menu'),
                        tooltip: '收起菜单',
                        onPressed: close,
                        icon: const Icon(Icons.close),
                      ),
                      for (final item in const [
                        ('profile', Icons.person_outline, '个人信息'),
                        ('roles', Icons.people_outline, '切换角色'),
                        ('history', Icons.history, '聊天记录'),
                        ('settings', Icons.settings_outlined, '设置'),
                      ])
                        InkWell(
                          key: Key('menu-${item.$1}'),
                          onTap: () => select(item.$1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: SizedBox(
                              width: 72,
                              child: Column(
                                children: [
                                  Icon(item.$2),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.$3,
                                    style: const TextStyle(fontSize: 11),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
