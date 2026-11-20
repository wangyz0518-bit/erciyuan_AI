// Run only on a disposable test installation. Never overwrite existing history.
// flutter build apk --debug -t tool/recovery_fixture.dart
import 'package:material_ui/material_ui.dart';
import 'package:companion_poc/data.dart';
import 'package:companion_poc/chat_controller.dart';
import 'package:companion_poc/audio_controller.dart';
import 'package:companion_poc/main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  if (await store.count() == 0) {
    for (var i = 0; i < 100; i++) {
      await store.save(
        Message(
          id: i + 1,
          characterId: i < 50 ? 'xing' : 'yue',
          author: i.isEven ? 'user' : 'assistant',
          text: '本地恢复验证样例 $i · 中文🙂',
          status: i == 99 ? 'pending' : 'complete',
        ),
      );
    }
    await store.setPreference('selected', 'yue');
    await store.setPreference(
      'fixture',
      '100 messages; final message deliberately pending',
    );
  }
  final chat = ChatController(store);
  await chat.init();
  runApp(CompanionApp(chat: chat, audio: AudioController()));
}
