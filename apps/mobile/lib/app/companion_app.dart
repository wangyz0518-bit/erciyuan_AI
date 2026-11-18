import 'package:material_ui/material_ui.dart';

import '../features/characters/application/character_selection_controller.dart';
import '../features/characters/presentation/character_home_page.dart';

/// Owns [controller]. The bootstrap composition root provides dependencies.
class CompanionApp extends StatefulWidget {
  const CompanionApp({required this.controller, super.key});

  final CharacterSelectionController controller;

  @override
  State<CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends State<CompanionApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '二次元 AI',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    ),
    home: CharacterHomePage(controller: widget.controller),
  );
}
