import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'audio_controller.dart';
import 'avatar.dart';
import 'chat_controller.dart';
import 'data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final chat = ChatController(await LocalStore.open());
    await chat.init();
    runApp(CompanionApp(chat: chat, audio: AudioController()));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('本地记录暂时无法打开，请重新启动应用。'))),
      ),
    );
  }
}

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key, required this.chat, required this.audio});
  final ChatController chat;
  final AudioController audio;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '星伴 · 本地验证',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7360A8)),
      scaffoldBackgroundColor: const Color(0xFFFAF8FD),
      useMaterial3: true,
    ),
    home: CompanionHome(chat: chat, audio: audio),
  );
}

class CompanionHome extends StatefulWidget {
  const CompanionHome({super.key, required this.chat, required this.audio});
  final ChatController chat;
  final AudioController audio;
  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome>
    with WidgetsBindingObserver {
  final input = TextEditingController();
  final scroll = ScrollController();
  final drafts = <String, String>{};
  int page = 0;
  bool foreground = true;
  bool animate = true;
  bool changingRole = false;
  String emotion = '平静';
  String previewActivity = '待机';
  bool missingExpression = false;
  ChatController get chat => widget.chat;
  AudioController get audio => widget.audio;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    chat.addListener(refresh);
    audio.addListener(refresh);
    input.addListener(inputChanged);
  }

  void inputChanged() {
    if (mounted) setState(() {});
  }

  void refresh() {
    if (!mounted) return;
    setState(() {});
    if (page == 0 && scroll.hasClients && scroll.position.extentAfter < 130) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(audio.stopAll());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chat.removeListener(refresh);
    audio.removeListener(refresh);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> switchRole(String id) async {
    if (changingRole || chat.selected == id) return;
    setState(() => changingRole = true);
    drafts[chat.selected] = input.text;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await audio.stopAll();
      await chat.switchCharacter(id);
      input.text = drafts[id] ?? '';
    } finally {
      if (mounted) setState(() => changingRole = false);
    }
  }

  Future<void> switchPage(int index) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await audio.stopAll();
    if (mounted) setState(() => page = index);
  }

  Future<void> send() async {
    if (chat.busy ||
        chat.switching ||
        changingRole ||
        input.text.trim().isEmpty) {
      return;
    }
    final text = input.text;
    final role = chat.selected;
    final task = chat.send(
      text,
      onSaved: () {
        if (!mounted) return;
        if (chat.selected == role && input.text == text) input.clear();
        if (drafts[role] == text) drafts.remove(role);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    });
    await task;
  }

  String get activity => audio.playing
      ? '说话'
      : chat.busy
      ? '等待'
      : '待机';

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('星伴 · 本地验证'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButton<String>(
              key: const Key('role-selector'),
              value: chat.selected,
              underline: const SizedBox(),
              items: chat.characters
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  )
                  .toList(),
              onChanged: changingRole || chat.switching
                  ? null
                  : (v) => unawaited(switchRole(v!)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFECE7F5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: const Text(
                '离线验证版 · 回复为模拟内容',
                style: TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: switch (page) {
                0 => chatPage(keyboard),
                1 => avatarPage(),
                _ => audioPage(),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: keyboard
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (i) => unawaited(switchPage(i)),
              destinations: const [
                NavigationDestination(
                  key: Key('nav-chat'),
                  icon: Icon(Icons.chat_bubble_outline),
                  label: '聊天',
                ),
                NavigationDestination(
                  key: Key('nav-avatar'),
                  icon: Icon(Icons.face_outlined),
                  label: '角色预览',
                ),
                NavigationDestination(
                  key: Key('nav-audio'),
                  icon: Icon(Icons.mic_none),
                  label: '声音测试',
                ),
              ],
            ),
    );
  }

  Widget characterPanel({required double height, bool preview = false}) =>
      Container(
        height: height,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFFF0ECF8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: height,
              child: Avatar(
                key: ValueKey('avatar-${chat.selected}'),
                role: chat.selected,
                emotion: missingExpression ? '平静' : emotion,
                activity: preview ? previewActivity : activity,
                animate: animate && foreground && height > 80,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.character.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (height > 80)
                      Text(
                        chat.character.description,
                        style: const TextStyle(fontSize: 12),
                      ),
                    Text(
                      '${preview ? previewActivity : activity} · 占位形象',
                      key: const Key('activity-label'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget chatPage(bool keyboard) => Column(
    children: [
      characterPanel(height: keyboard ? 64 : 126),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Text('回复场景', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 10),
            DropdownButton<ReplyMode>(
              key: const Key('reply-mode'),
              value: chat.mode,
              isDense: true,
              items: const [
                DropdownMenuItem(value: ReplyMode.normal, child: Text('正常')),
                DropdownMenuItem(value: ReplyMode.failure, child: Text('模拟失败')),
                DropdownMenuItem(
                  value: ReplyMode.delayed,
                  child: Text('延迟 6 秒'),
                ),
              ],
              onChanged: chat.busy
                  ? null
                  : (v) => setState(() => chat.mode = v!),
            ),
            const Spacer(),
            Text(
              '${chat.messages.length} 条消息',
              key: const Key('message-count'),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      if (chat.error != null)
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            chat.error!,
            style: const TextStyle(color: Colors.deepOrange, fontSize: 12),
          ),
        ),
      Expanded(
        child: chat.messages.isEmpty
            ? const Center(
                child: Text(
                  '向我打个招呼吧\n消息会保存在这台设备上',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : ListView.builder(
                key: const Key('message-list'),
                controller: scroll,
                padding: const EdgeInsets.all(12),
                itemCount: chat.messages.length,
                itemBuilder: (_, i) => messageBubble(chat.messages[i]),
              ),
      ),
      if (chat.busy)
        TextButton.icon(
          key: const Key('cancel-reply'),
          onPressed: () => unawaited(chat.cancel()),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('停止回复'),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('message-input'),
                controller: input,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '说点什么…',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('send'),
              onPressed:
                  chat.busy ||
                      chat.switching ||
                      changingRole ||
                      input.text.trim().isEmpty
                  ? null
                  : () => unawaited(send()),
              child: const Text('发送'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget messageBubble(Message m) {
    final mine = m.author == 'user';
    final label = switch (m.status) {
      'pending' => '回复中…',
      'failed' => '回复失败',
      'cancelled' => '已取消',
      'interrupted' => '上次回复已中断',
      _ => '',
    };
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('message-${m.id}'),
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFE3DCF4) : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mine ? '你' : chat.character.name,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (m.text.isNotEmpty) SelectableText(m.text),
            if (label.isNotEmpty)
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.deepPurple),
              ),
            if (['failed', 'cancelled', 'interrupted'].contains(m.status))
              TextButton(
                key: ValueKey('retry-${m.id}'),
                onPressed: chat.busy ? null : () => unawaited(chat.retry(m)),
                child: const Text('重试'),
              ),
          ],
        ),
      ),
    );
  }

  Widget avatarPage() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      characterPanel(height: 210, preview: true),
      const SizedBox(height: 14),
      const Text('表情', style: TextStyle(fontWeight: FontWeight.bold)),
      Wrap(
        spacing: 8,
        children: ['平静', '开心', '疑惑', '难过']
            .map(
              (e) => ChoiceChip(
                key: ValueKey('emotion-$e'),
                label: Text(e),
                selected: emotion == e,
                onSelected: (_) => setState(() {
                  emotion = e;
                  missingExpression = false;
                }),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 14),
      const Text('活动状态', style: TextStyle(fontWeight: FontWeight.bold)),
      Wrap(
        spacing: 8,
        children: ['待机', '等待', '说话']
            .map(
              (a) => ChoiceChip(
                key: ValueKey('activity-$a'),
                label: Text(a),
                selected: previewActivity == a,
                onSelected: (_) => setState(() => previewActivity = a),
              ),
            )
            .toList(),
      ),
      SwitchListTile(
        key: const Key('animate'),
        contentPadding: EdgeInsets.zero,
        title: const Text('待机动作'),
        value: animate,
        onChanged: (v) => setState(() => animate = v),
      ),
      SwitchListTile(
        key: const Key('missing-expression'),
        contentPadding: EdgeInsets.zero,
        title: const Text('模拟素材缺失'),
        subtitle: const Text('缺失时显示平静表情'),
        value: missingExpression,
        onChanged: (v) => setState(() => missingExpression = v),
      ),
      const Text(
        '占位头像用于检查切换、布局和简单动作。尚未接入图片生成、Live2D 或精确口型。',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    ],
  );

  Widget audioPage() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      characterPanel(height: 126),
      const Text(
        '录音与回放',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      Text(audio.status, key: const Key('audio-status')),
      if (audio.recording)
        Text('已录制 ${audio.seconds} 秒', key: const Key('recording-time')),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const Key('record-start'),
            onPressed: audio.working || audio.recording
                ? null
                : () => unawaited(audio.startRecording()),
            icon: const Icon(Icons.mic),
            label: const Text('开始录音'),
          ),
          OutlinedButton(
            key: const Key('record-finish'),
            onPressed: audio.recording && !audio.working
                ? () => unawaited(audio.finishRecording())
                : null,
            child: const Text('结束并保存'),
          ),
          OutlinedButton(
            key: const Key('record-cancel'),
            onPressed: audio.recording
                ? () => unawaited(audio.stopAll())
                : null,
            child: const Text('取消录音'),
          ),
          OutlinedButton(
            key: const Key('play-recording'),
            onPressed:
                audio.recordingPath != null &&
                    !audio.working &&
                    !audio.recording
                ? () => unawaited(audio.play())
                : null,
            child: const Text('回放录音'),
          ),
          OutlinedButton(
            key: const Key('play-tone'),
            onPressed: audio.working || audio.recording
                ? null
                : () => unawaited(audio.play(testTone: true)),
            child: const Text('播放测试音'),
          ),
          OutlinedButton(
            key: const Key('audio-stop'),
            onPressed: audio.playing ? () => unawaited(audio.stopAll()) : null,
            child: const Text('停止播放'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        '播放状态：${audio.playing ? '播放中' : '已停止'}',
        key: const Key('playback-status'),
      ),
      if (audio.recordingPath != null)
        Text(
          '录音大小：${audio.recordingBytes} 字节\n信号强度：${audio.rms.toStringAsFixed(5)}',
          key: const Key('recording-details'),
        ),
      const SizedBox(height: 16),
      const Text(
        '只验证采集和播放，不会上传录音。返回其他页面、切换角色或进入后台会停止音频。',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    ],
  );
}
