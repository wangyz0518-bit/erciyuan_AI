import 'package:material_ui/material_ui.dart';

import 'live2d_preview_page.dart';
import 'dragon_idle_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DragonIdlePreviewApp());
}

class Live2dPreviewApp extends StatelessWidget {
  const Live2dPreviewApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '星伴 · Live2D 验证',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7962BA)),
    ),
    home: const Live2dPreviewPage(),
  );
}
