import 'package:material_ui/material_ui.dart';

import '../../../community/community_scope.dart';
import '../../../community/role_portrait.dart';
import '../../chat/data/model_gateway_adapter.dart';
import '../../timeline/data/person_database.dart';
import '../application/character_selection_controller.dart';
import '../domain/character.dart';
import 'continuous_chat_page.dart';
import 'data_management_page.dart';

/// A-first navigation: people are primary, not individual chat sessions.
class CharacterHomePage extends StatelessWidget {
  const CharacterHomePage({
    required this.controller,
    required this.database,
    this.gateway,
    this.onOpen,
    super.key,
  });

  final CharacterSelectionController controller;
  final PersonDatabase database;
  final ModelGatewayAdapter? gateway;
  final VoidCallback? onOpen;

  void _openTimeline(BuildContext context, PersonScope scope) {
    controller.selectCharacter(scope);
    if (onOpen != null) {
      onOpen!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ContinuousChatPage(
          selection: controller,
          database: database,
          scope: scope,
          gateway: gateway,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(onOpen == null ? '人物主页' : '角色'),
      actions: [
        if (CommunityScope.of(context) case final community?
            when onOpen == null)
          IconButton(
            tooltip: '社区',
            onPressed: () => community.open(AppSection.community),
            icon: const Icon(Icons.forum_outlined),
          ),
        if (onOpen == null)
          IconButton(
            key: const ValueKey('data-management'),
            tooltip: '我的 / 数据管理',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DataManagementPage(
                  database: database,
                  ownerId: controller.ownerId,
                ),
              ),
            ),
            icon: const Icon(Icons.person_outline),
          ),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            Text(
              '今天想和谁聊聊？',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            for (final character in controller.characters)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CharacterChoice(
                  character: character,
                  controller: controller,
                  onOpen: () => _openTimeline(context, character.scope),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('continue-timeline'),
              onPressed: () => _openTimeline(context, controller.activeScope),
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text('继续与${controller.activeCharacter.name}对话'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        !controller.activeCharacter.supportsLegacyGateway
                            ? '小芽的在线对话使用 v3 网关；当前入口提供本地演示。'
                            : gateway == null
                            ? '当前为离线 Mock：人物回复只是本地演示，历史保存在 SQLite。'
                            : '当前连接开发文字网关，人物历史保存在本地 SQLite。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CharacterChoice extends StatelessWidget {
  const _CharacterChoice({
    required this.character,
    required this.controller,
    required this.onOpen,
  });

  final Character character;
  final CharacterSelectionController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final selected = character.scope == controller.activeScope;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: selected
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        key: ValueKey('character-${character.scope.characterId}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => controller.selectCharacter(character.scope),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 66,
                  height: 80,
                  child: RoleArtwork(character.appearance),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      character.description,
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (selected)
                      Text(
                        '当前人物',
                        style: TextStyle(color: scheme.primary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '进入${character.name}的聊天',
                onPressed: onOpen,
                icon: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
