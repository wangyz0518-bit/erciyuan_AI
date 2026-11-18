import 'dart:async';

import 'package:flutter/material.dart';

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
    super.key,
  });

  final CharacterSelectionController controller;
  final PersonDatabase database;
  final ModelGatewayAdapter? gateway;

  void _openTimeline(BuildContext context, PersonScope scope) {
    controller.selectCharacter(scope);
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
    backgroundColor: const Color(0xFF151A29),
    appBar: AppBar(
      title: const Text('人物主页'),
      backgroundColor: const Color(0xFF22283B),
      foregroundColor: Colors.white,
      actions: [
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
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            children: [
              const Text(
                '今天想和谁聊聊？',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '每位人物只有一条持续的对话时间线，回到这里不会丢失历史。',
                style: TextStyle(color: Color(0xFFC4CDE0), height: 1.5),
              ),
              const SizedBox(height: 20),
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
                  backgroundColor: const Color(0xFF7969C3),
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Card(
                color: const Color(0xFF292F45),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFD2BAFF)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          gateway == null
                              ? '当前为离线 Mock：人物回复只是本地演示，历史保存在 SQLite。'
                              : '当前连接开发文字网关，人物历史保存在本地 SQLite。',
                          style: const TextStyle(
                            color: Color(0xFFDEE2EE),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (constraints.maxWidth < 375)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '支持窄屏滚动操作',
                    style: TextStyle(color: Color(0xFFC4CDE0)),
                  ),
                ),
            ],
          ),
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
    return Card(
      margin: EdgeInsets.zero,
      color: selected ? const Color(0xFF474265) : const Color(0xFF2B3145),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? const Color(0xFFD2BAFF) : Colors.transparent,
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
              CircleAvatar(
                backgroundColor: const Color(0xFFD4C7F3),
                radius: 31,
                child: Icon(
                  character.scope.characterId == 'star'
                      ? Icons.star_rounded
                      : Icons.dark_mode_rounded,
                  color: const Color(0xFF39304D),
                  size: 38,
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
                      style: const TextStyle(
                        color: Color(0xFFD3D8E5),
                        fontSize: 13,
                      ),
                    ),
                    if (selected)
                      const Text(
                        '当前人物',
                        style: TextStyle(
                          color: Color(0xFFE7D0FF),
                          fontSize: 12,
                        ),
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
