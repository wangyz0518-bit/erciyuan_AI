import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';

import 'audio_controller.dart';
import 'chat_controller.dart';
import 'poc_tools_page.dart';
import 'widgets/character_scene.dart';
import 'widgets/chat_sidebar.dart';
import 'widgets/chat_messages.dart';
import 'widgets/chat_composer.dart';
import 'widgets/call_overlay.dart';

class ImmersiveChatPage extends StatefulWidget {
  const ImmersiveChatPage({super.key, required this.chat, required this.audio});
  final ChatController chat;
  final AudioController audio;
  @override
  State<ImmersiveChatPage> createState() => _ImmersiveChatPageState();
}

class _ImmersiveChatPageState extends State<ImmersiveChatPage>
    with WidgetsBindingObserver {
  final input = TextEditingController();
  final focus = FocusNode();
  final drafts = <String, String>{};
  bool textMode = false, menu = false, full = false, foreground = true;
  bool calling = false, muted = false, changingRole = false;
  bool panelOpen = false, toolsOpen = false;
  final callClock = Stopwatch();
  Timer? callTimer;
  ChatController get chat => widget.chat;
  AudioController get audio => widget.audio;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    chat.addListener(refresh);
    audio.addListener(refresh);
    input.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      endCall();
      unawaited(audio.stopAll());
    }
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chat.removeListener(refresh);
    audio.removeListener(refresh);
    input.dispose();
    focus.dispose();
    callTimer?.cancel();
    unawaited(audio.stopAll());
    super.dispose();
  }

  Future<void> switchRole(String id) async {
    if (changingRole || chat.switching || chat.selected == id) return;
    changingRole = true;
    drafts[chat.selected] = input.text;
    focus.unfocus();
    endCall();
    refresh();
    try {
      await audio.stopAll();
      await chat.switchCharacter(id);
      if (!mounted) return;
      input.text = drafts[id] ?? '';
      textMode = false;
    } finally {
      changingRole = false;
      refresh();
    }
  }

  Future<void> send() async {
    if (changingRole) return;
    final text = input.text, role = chat.selected;
    await chat.send(
      text,
      onSaved: () {
        if (!mounted) return;
        if (chat.selected == role && input.text == text) input.clear();
        if (drafts[role] == text) drafts.remove(role);
      },
    );
  }

  void changeMode() {
    unawaited(audio.stopAll());
    setState(() => textMode = !textMode);
    if (textMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && textMode) focus.requestFocus();
      });
    } else {
      focus.unfocus();
    }
  }

  Future<void> startCall() async {
    focus.unfocus();
    await audio.stopAll();
    if (!mounted || !foreground) return;
    callClock.reset();
    callClock.start();
    setState(() {
      calling = true;
      muted = false;
      menu = false;
    });
    callTimer?.cancel();
    callTimer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  void endCall() {
    callTimer?.cancel();
    callClock.stop();
    calling = false;
    muted = false;
    refresh();
  }

  Future<void> showPanel(String kind) async {
    if (panelOpen || toolsOpen) return;
    panelOpen = true;
    setState(() => menu = false);
    focus.unfocus();
    await audio.stopAll();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x210D0A13),
      builder: (sheetContext) => Theme(
        data: immersiveTheme,
        child: FractionallySizedBox(
          heightFactor: kind == 'history' ? .62 : .55,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Material(
                color: const Color(0x9C221D28),
                child: kind == 'history'
                    ? ChatHistory(
                        chat: chat,
                        close: () => Navigator.pop(sheetContext),
                      )
                    : panelContent(kind, sheetContext),
              ),
            ),
          ),
        ),
      ),
    );
    panelOpen = false;
    refresh();
  }

  Widget panelContent(String kind, BuildContext sheetContext) => SafeArea(
    top: false,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(switch (kind) {
                'roles' => '切换角色',
                'profile' => '个人信息',
                _ => '设置',
              }, style: const TextStyle(fontSize: 22)),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(sheetContext),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        if (kind == 'profile') ...[
          const ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('访客'),
            subtitle: Text('本机体验 · 暂未接入账号服务'),
          ),
        ],
        if (kind == 'roles')
          for (final role in chat.characters)
            ListTile(
              key: Key('select-${role.id}'),
              title: Text(role.name),
              subtitle: Text(role.description),
              trailing: role.id == chat.selected
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(switchRole(role.id));
              },
            ),
        if (kind == 'settings') ...[
          ListTile(
            title: const Text('镜头'),
            subtitle: Text(full ? '全身' : '半身'),
            onTap: () {
              setState(() => full = !full);
              Navigator.pop(sheetContext);
            },
          ),
          ListTile(
            key: const Key('open-tools'),
            title: const Text('本地验证工具'),
            subtitle: const Text('角色预览、声音测试、模拟回复'),
            onTap: () {
              Navigator.pop(sheetContext);
              unawaited(openTools());
            },
          ),
          const ListTile(
            title: Text('离线验证版'),
            subtitle: Text('回复为模拟内容；录音仅供试听，通话为交互演示。'),
          ),
        ],
      ],
    ),
  );
  Future<void> openTools() async {
    toolsOpen = true;
    drafts[chat.selected] = input.text;
    await audio.stopAll();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PocToolsPage(chat: chat, audio: audio),
      ),
    );
    await audio.stopAll();
    if (!mounted) return;
    input.text = drafts[chat.selected] ?? '';
    toolsOpen = false;
    refresh();
  }

  ThemeData get immersiveTheme => ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFF6BC9F),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF171620),
  );

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final recent = chat.messages
        .skip(
          (chat.messages.length - (keyboard ? 1 : 2)).clamp(
            0,
            chat.messages.length,
          ),
        )
        .toList();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: immersiveTheme,
        child: PopScope(
          canPop:
              !menu &&
              !calling &&
              !audio.recording &&
              audio.recordingPath == null &&
              !audio.working,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (menu) {
              setState(() => menu = false);
            } else if (calling) {
              endCall();
            } else {
              unawaited(audio.stopAll());
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Stack(
              fit: StackFit.expand,
              children: [
                CharacterScene(
                  role: chat.selected,
                  full: full,
                  replying: chat.busy,
                  foreground: foreground && !toolsOpen,
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                        child: Row(
                          children: [
                            if (!calling)
                              IconButton.filledTonal(
                                key: const Key('open-menu'),
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF302532),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(
                                      color: Color(0xFF67545C),
                                    ),
                                  ),
                                ),
                                tooltip: '展开主菜单',
                                onPressed: () {
                                  focus.unfocus();
                                  unawaited(audio.stopAll());
                                  setState(() => menu = true);
                                },
                                icon: const Icon(Icons.menu),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chat.character.name,
                                    key: const Key('character-name'),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    chat.busy ? '正在回应 · 模拟回复' : 'AI 角色 · 离线体验',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFE0C9C3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              key: const Key('camera-toggle'),
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF2C252D),
                                side: const BorderSide(
                                  color: Color(0xFF67545C),
                                ),
                              ),
                              onPressed: () => setState(() => full = !full),
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 18,
                              ),
                              label: Text(full ? '全身' : '半身'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: keyboard
                                ? (MediaQuery.viewInsetsOf(context).bottom -
                                          MediaQuery.paddingOf(context).bottom)
                                      .clamp(0, double.infinity)
                                : 0,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) => Align(
                              alignment: Alignment.bottomCenter,
                              child: SingleChildScrollView(
                                reverse: true,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    8,
                                    20,
                                    12,
                                  ),
                                  child: calling
                                      ? CallOverlay(
                                          seconds: callClock.elapsed.inSeconds,
                                          muted: muted,
                                          toggleMute: () =>
                                              setState(() => muted = !muted),
                                          end: endCall,
                                        )
                                      : panelOpen
                                      ? const SizedBox.shrink()
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (!keyboard)
                                              TextButton(
                                                key: const Key('open-history'),
                                                onPressed: () =>
                                                    showPanel('history'),
                                                child: const Text(
                                                  '─\n上拉看历史',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            GestureDetector(
                                              key: const Key('recent-messages'),
                                              behavior: HitTestBehavior.opaque,
                                              onVerticalDragEnd: (d) {
                                                if ((d.primaryVelocity ?? 0) <
                                                    -100) {
                                                  unawaited(
                                                    showPanel('history'),
                                                  );
                                                }
                                              },
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: recent.isEmpty
                                                      ? [
                                                          const Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                                  16,
                                                                ),
                                                            child: Text(
                                                              '向我打个招呼吧',
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                            ),
                                                          ),
                                                        ]
                                                      : recent
                                                            .map(
                                                              (
                                                                m,
                                                              ) => ChatMessage(
                                                                key: ValueKey(
                                                                  'recent-${m.id}',
                                                                ),
                                                                message: m,
                                                                chat: chat,
                                                                lines: keyboard
                                                                    ? 1
                                                                    : 2,
                                                              ),
                                                            )
                                                            .toList(),
                                                ),
                                              ),
                                            ),
                                            if (chat.error != null)
                                              Text(
                                                chat.error!,
                                                key: const Key('chat-error'),
                                                style: const TextStyle(
                                                  color: Color(0xFFFFBEA8),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            if (chat.busy)
                                              TextButton(
                                                key: const Key('cancel-reply'),
                                                onPressed: chat.cancel,
                                                child: const Text('停止回复'),
                                              ),
                                            if (audio.recordingPath != null)
                                              Container(
                                                key: const Key(
                                                  'recording-preview',
                                                ),
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                    ),
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xCC302532,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                child: Column(
                                                  children: [
                                                    Text(
                                                      '本地试听 · ${audio.seconds} 秒 · 尚未发送',
                                                    ),
                                                    Wrap(
                                                      alignment:
                                                          WrapAlignment.center,
                                                      children: [
                                                        TextButton(
                                                          key: const Key(
                                                            'preview-play',
                                                          ),
                                                          onPressed:
                                                              audio.working
                                                              ? null
                                                              : () =>
                                                                    audio
                                                                        .playing
                                                                    ? audio.stopAll(
                                                                        discardRecording:
                                                                            false,
                                                                      )
                                                                    : audio
                                                                          .play(),
                                                          child: Text(
                                                            audio.playing
                                                                ? '停止'
                                                                : '试听',
                                                          ),
                                                        ),
                                                        TextButton(
                                                          key: const Key(
                                                            'preview-delete',
                                                          ),
                                                          onPressed:
                                                              audio.stopAll,
                                                          child: const Text(
                                                            '删除',
                                                          ),
                                                        ),
                                                        TextButton(
                                                          key: const Key(
                                                            'preview-rerecord',
                                                          ),
                                                          onPressed:
                                                              audio.stopAll,
                                                          child: const Text(
                                                            '重新按住录音',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (!textMode &&
                                                (audio.recording ||
                                                    audio.recordingPath !=
                                                        null ||
                                                    audio.status.contains(
                                                      '失败',
                                                    ) ||
                                                    audio.status.contains(
                                                      '权限',
                                                    )))
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                child: Text(
                                                  audio.status,
                                                  key: const Key(
                                                    'audio-status',
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            ChatComposer(
                                              textMode: textMode,
                                              input: input,
                                              focus: focus,
                                              audio: audio,
                                              busy:
                                                  chat.busy ||
                                                  chat.switching ||
                                                  changingRole,
                                              mode: changeMode,
                                              send: () => unawaited(send()),
                                              call: () =>
                                                  unawaited(startCall()),
                                              startHold: () => unawaited(
                                                audio.startRecording(),
                                              ),
                                              endHold: (keep) => unawaited(
                                                keep
                                                    ? audio.finishRecording()
                                                    : audio.stopAll(),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (menu)
                  ChatSidebar(
                    close: () => setState(() => menu = false),
                    select: (kind) => unawaited(showPanel(kind)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
