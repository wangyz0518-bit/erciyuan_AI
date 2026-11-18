import 'package:material_ui/material_ui.dart';

import '../application/character_selection_controller.dart';
import '../domain/character.dart';
import 'timeline_placeholder_page.dart';

class CharacterHomePage extends StatelessWidget {
  const CharacterHomePage({required this.controller, super.key});

  final CharacterSelectionController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('人物主页（Mock）')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('正式工程最小验证版，尚未连接真实聊天与记忆。'),
            const SizedBox(height: 12),
            for (final character in controller.characters)
              _CharacterChoice(character: character, controller: controller),
            const SizedBox(height: 16),
            Text('当前人物：${controller.activeCharacter.name}'),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('continue-timeline'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => TimelinePlaceholderPage(
                      controller: controller,
                      scope: controller.activeScope,
                    ),
                  ),
                );
              },
              child: const Text('继续与 TA 对话'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CharacterChoice extends StatelessWidget {
  const _CharacterChoice({required this.character, required this.controller});

  final Character character;
  final CharacterSelectionController controller;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('character-${character.scope.characterId}'),
    title: Text(character.name),
    subtitle: Text(character.description),
    selected: character.scope == controller.activeScope,
    onTap: () => controller.selectCharacter(character.scope),
  );
}
