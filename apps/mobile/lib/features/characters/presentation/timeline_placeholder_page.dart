import 'package:flutter/material.dart';

import '../application/character_selection_controller.dart';
import '../domain/character.dart';

/// A single user-visible timeline entrance per character. No sessions.
class TimelinePlaceholderPage extends StatefulWidget {
  const TimelinePlaceholderPage({
    required this.controller,
    required this.scope,
    super.key,
  });

  final CharacterSelectionController controller;
  final PersonScope scope;

  @override
  State<TimelinePlaceholderPage> createState() =>
      _TimelinePlaceholderPageState();
}

class _TimelinePlaceholderPageState extends State<TimelinePlaceholderPage> {
  late final TextEditingController _draft;

  @override
  void initState() {
    super.initState();
    _draft = TextEditingController(
      text: widget.controller.draftFor(widget.scope),
    );
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('持续对话（Mock）')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('这是一条持续存在的逻辑时间线占位页。'),
            const Text('原始记录、自动归档和真实回复将在后续 Issue 接入。'),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('character-draft'),
              controller: _draft,
              onChanged: (text) =>
                  widget.controller.updateDraft(widget.scope, text),
              decoration: const InputDecoration(
                labelText: '人物专属草稿（内存 Mock）',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
