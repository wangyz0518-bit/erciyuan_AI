import 'package:material_ui/material_ui.dart';

import 'community/community_controller.dart';
import 'community/community_host.dart';
import 'features/timeline/data/person_database.dart';
import 'features/memory/domain/memory_models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final database = await PersonDatabase.open(
      automaticSummarizer: const DeterministicSummarizer(),
    );
    final community = CommunityController(database);
    await community.restore();
    runApp(CommunityHost(community));
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
