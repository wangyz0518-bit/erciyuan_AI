import 'package:material_ui/material_ui.dart';

import 'bootstrap.dart';
import 'immersive/immersive_home.dart';
import 'immersive/model_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final voice = ModelGateway.configured();
    final app = await bootstrapCompanionApp(
      homeBuilder: voice != null && voice.useV3
          ? (selection, database, textGateway) => ImmersiveHome(
              selection,
              database,
              textGateway,
              voiceGateway: voice,
            )
          : null,
      gatewayUri: const String.fromEnvironment('PERSON_GATEWAY_URL').isEmpty
          ? null
          : Uri.parse(const String.fromEnvironment('PERSON_GATEWAY_URL')),
      gatewayToken:
          const String.fromEnvironment('PERSON_GATEWAY_DEV_TOKEN').isEmpty
          ? null
          : const String.fromEnvironment('PERSON_GATEWAY_DEV_TOKEN'),
    );
    runApp(app);
  } catch (error) {
    // Never overwrite or reset an existing database on startup failure.
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('无法打开本地人物数据，请保留原始文件后检查：$error'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
