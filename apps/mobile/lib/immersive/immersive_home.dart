import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../features/characters/application/character_selection_controller.dart';
import '../features/chat/data/model_gateway_adapter.dart';
import '../features/timeline/data/person_database.dart';
import 'audio_controller.dart';
import 'chat_controller.dart';
import 'immersive_chat_page.dart';
import 'model_gateway.dart';

class ImmersiveHome extends StatefulWidget {
  const ImmersiveHome(
    this.selection,
    this.database,
    this.textGateway, {
    super.key,
  });
  final CharacterSelectionController selection;
  final PersonDatabase database;
  final ModelGatewayAdapter? textGateway;
  @override
  State<ImmersiveHome> createState() => _ImmersiveHomeState();
}

class _ImmersiveHomeState extends State<ImmersiveHome> {
  late final chat = ChatController(
    widget.selection,
    widget.database,
    widget.textGateway,
    ModelGateway.configured(),
  );
  late final ready = chat.init();
  final audio = AudioController();
  @override
  void dispose() {
    chat.dispose();
    unawaited(audio.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(body: Center(child: Text('无法读取本机人物与记录，请重新打开。')));
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return ImmersiveChatPage(chat: chat, audio: audio);
    },
  );
}
