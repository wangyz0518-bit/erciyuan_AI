import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../features/characters/domain/character.dart';
import '../features/memory/domain/memory_models.dart';
import 'account_page.dart';
import 'community_api.dart';
import 'community_controller.dart';
import 'community_forms.dart';

mixin _RoleAction<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String error = '';
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await action();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget button(String label, Future<void> Function() action) => OutlinedButton(
    onPressed: busy ? null : () => run(action),
    child: Text(label),
  );
}

class MemoryPage extends StatefulWidget {
  const MemoryPage(this.model, this.role, {super.key});
  final CommunityController model;
  final String role;
  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> with _RoleAction<MemoryPage> {
  List<Json> notes = [];
  List<MemorySummary> summaries = [];
  CommunityApi get api => widget.model.api;
  String get path => '/community/characters/${widget.role}/memories';
  PersonScope get scope =>
      PersonScope(ownerId: api.owner!, characterId: localRole(widget.role));
  @override
  void initState() {
    super.initState();
    run(load);
  }

  Future<void> load() async {
    notes = await api.items(path);
    summaries = await widget.model.database.memory.summariesFor(scope);
  }

  Future<void> edit({Json? note, MemorySummary? summary}) async {
    final text = await communityText(
      context,
      note == null && summary == null ? '添加记忆' : '纠正记忆',
      '希望角色记住的内容',
      limit: 500,
      initial: note?['text'] ?? summary?.text ?? '',
      action: '保存',
    );
    if (text == null) return;
    await api.request(
      note == null ? 'POST' : 'PUT',
      note == null ? path : '$path/${note['id']}',
      {'text': text},
    );
    if (summary != null) {
      await widget.model.database.memory.invalidateSummary(
        scope,
        summary.summaryId,
      );
    }
    await load();
  }

  Future<void> forget({Json? note, MemorySummary? summary}) async {
    if (!await confirmAction(
      context,
      '忘记这条记忆？',
      '此条将从角色记忆中移除。原始聊天记录仍可在历史中查看。',
      '忘记',
    )) {
      return;
    }
    if (note != null) await api.request('DELETE', '$path/${note['id']}');
    if (summary != null) {
      await widget.model.database.memory.invalidateSummary(
        scope,
        summary.summaryId,
      );
    }
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('角色记忆')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty) Text(error),
        const Text('确认的记忆会用于这个角色的下一轮在线对话。'),
        button('添加记忆', () => edit()),
        for (final note in notes)
          ListTile(
            title: Text(note['text']),
            subtitle: Wrap(
              children: [
                button('纠正', () => edit(note: note)),
                button('忘记', () => forget(note: note)),
              ],
            ),
          ),
        if (summaries.isNotEmpty) const Text('本机摘要 · 确认后用于在线对话'),
        for (final summary in summaries)
          ListTile(
            title: Text(summary.text),
            subtitle: Wrap(
              children: [
                button('确认或纠正', () => edit(summary: summary)),
                button('忘记', () => forget(summary: summary)),
              ],
            ),
          ),
      ],
    ),
  );
}

class RoleAssetsPage extends StatefulWidget {
  const RoleAssetsPage(this.api, this.card, {super.key});
  final CommunityApi api;
  final Json card;
  @override
  State<RoleAssetsPage> createState() => _RoleAssetsPageState();
}

class _RoleAssetsPageState extends State<RoleAssetsPage>
    with _RoleAction<RoleAssetsPage> {
  late Json card = {...widget.card};
  List<Json> voices = [];
  Json binding = {};
  String? previewImage;
  bool replaceImage = false;
  final player = AudioPlayer();
  String get path => '/community/characters/${card['id']}';
  @override
  void initState() {
    super.initState();
    run(() async {
      voices = await widget.api.items('/community/voices');
      binding = await widget.api.request('GET', '$path/voice-binding');
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return;
    final raw = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (raw.length + chunk.length > 2200000) {
        throw const FormatException('请选择 2 MB 以内的图片');
      }
      raw.add(chunk);
    }
    previewImage = base64Encode(raw.takeBytes());
    replaceImage = true;
  }

  Future<void> saveImage() async {
    final result = await widget.api.request('PUT', '$path/portrait', {
      'image': previewImage,
    });
    card['portrait'] = result['portrait'];
    replaceImage = false;
  }

  Future<void> previewVoice(Json voice) async {
    if (!await confirmAction(
      context,
      '试听音色',
      '在线语音服务可能产生费用。模拟网关仅验证播放流程。',
      '试听',
    )) {
      return;
    }
    final data = await widget.api.request(
      'POST',
      "/community/voices/${voice['id']}/preview",
    );
    await player.play(
      BytesSource(base64Decode(data['audio']), mimeType: 'audio/wav'),
    );
  }

  Future<void> bind(String? id) async {
    binding = await widget.api.request('PUT', '$path/voice-binding', {
      'profile_id': id,
      'revision': binding['revision'],
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("${card['name']}的素材")),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty) Text(error),
        const Text('角色形象'),
        Center(
          child: RolePortrait(
            card['avatar'],
            portrait: replaceImage ? previewImage : card['portrait'],
          ),
        ),
        Wrap(
          children: [
            button('选择图片', pick),
            if (replaceImage) button('绑定形象', saveImage),
            if (card['portrait'] != null)
              button('恢复内置形象', () async {
                previewImage = null;
                await saveImage();
              }),
          ],
        ),
        const Divider(),
        const Text('对话音色'),
        const Text('私人绑定仅对本账户生效。分享采用角色卡的公开音色。'),
        for (final voice in voices)
          ListTile(
            title: Text(voice['name']),
            subtitle: Text(voice['public'] == true ? '公开预设' : '私人音色'),
            trailing: Wrap(
              children: [
                button('试听', () => previewVoice(voice)),
                button(
                  binding['profile_id'] == voice['id'] ? '已绑定' : '绑定',
                  () => bind(voice['id']),
                ),
              ],
            ),
          ),
        if (binding['profile_id'] != null)
          button('使用角色卡公开音色', () => bind(null)),
      ],
    ),
  );
}
