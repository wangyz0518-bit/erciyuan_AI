import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'audio_controller.dart';
import 'immersive_chat_page.dart';
import 'chat_controller.dart';
import 'data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final chat = ChatController(await LocalStore.open());
    await chat.init();
    runApp(CompanionApp(chat: chat, audio: AudioController()));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('本地记录暂时无法打开，请重新启动应用。'))),
      ),
    );
  }
}

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key, required this.chat, required this.audio});
  final ChatController chat;
  final AudioController audio;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '星伴 · 本地验证',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7360A8)),
      scaffoldBackgroundColor: const Color(0xFFFAF8FD),
      useMaterial3: true,
    ),
    home: ImmersiveChatPage(chat: chat, audio: audio),
  );
}
