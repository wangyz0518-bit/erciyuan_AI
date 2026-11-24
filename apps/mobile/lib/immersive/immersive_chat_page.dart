import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';

import 'audio_controller.dart';
import 'chat_controller.dart';
import 'conversation_controller.dart';
import '../features/characters/domain/character.dart';
import '../features/characters/presentation/data_management_page.dart';
import '../community/community_scope.dart';
import '../features/avatar/presentation/character_avatar_scene.dart';
import '../features/avatar/presentation/avatar_fallback_scene.dart';
import '../features/avatar/presentation/avatar_zoom.dart';
import '../features/avatar/presentation/sprout_avatar_scene.dart';
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
  bool textMode = false, menu = false, foreground = true;
  bool calling = false, muted = false, changingRole = false;
  bool panelOpen = false, toolsOpen = false;
  final callClock = Stopwatch();
  Timer? callTimer;
  final avatars = <String, GlobalKey<CharacterAvatarSceneState>>{};
  GlobalKey<CharacterAvatarSceneState> get avatar => avatars.putIfAbsent(
    chat.selected,
    GlobalKey<CharacterAvatarSceneState>.new,
  );
  ChatController get chat => widget.chat;
  final zoomByRole = <String, double>{};
  double get halfZoom => chat.character.appearance == sproutCharacterId
      ? sproutHalfZoom
      : halfAvatarZoom;
  double get zoom => zoomByRole[chat.selected] ?? halfZoom;
  void changeZoom(double value) {
    if (value != zoom) setState(() => zoomByRole[chat.selected] = value);
  }

  AudioController get audio => widget.audio;
  ConversationController? get session => chat.conversation;
  @override
  void initState() {
    super.initState();
    textMode = !chat.online && !chat.character.supportsLegacyGateway;
    WidgetsBinding.instance.addObserver(this);
    chat.addListener(refresh);
    audio.addListener(refresh);
    input.addListener(refresh);
    if (chat.gateway?.useV3 == true) {
      final voice = ConversationController(
        chat.gateway!,
        audio,
        onTimelineMessage: chat.saveVoiceMessage,
      );
      chat.conversation = voice;
      voice.addListener(chat.refreshConversation);
      unawaited(session?.load(chat.selected));
    }
  }

  void refresh() {
    if (!mounted) return;
    if (calling && session != null && !session!.calling) {
      callTimer?.cancel();
      callClock.stop();
      calling = false;
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (session != null) {
      if (state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        endCall();
        unawaited(audio.stopAll());
      }
    } else if (!foreground) {
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
    final voice = chat.conversation;
    if (voice != null) {
      voice.removeListener(chat.refreshConversation);
      chat.conversation = null;
      unawaited(voice.shutdown());
    }
    unawaited(audio.stopAll());
    super.dispose();
  }

  Future<void> switchRole(String id) async {
    if (changingRole || chat.switching || chat.selected == id) return;
    changingRole = true;
    drafts[chat.selected] = input.text;
    focus.unfocus();
    endCall(closeSession: false);
    refresh();
    try {
      await audio.stopAll();
      await chat.switchCharacter(id);
      if (!mounted) return;
      input.text = drafts[id] ?? '';
      textMode = !chat.online && !chat.character.supportsLegacyGateway;
    } finally {
      changingRole = false;
      refresh();
    }
  }

  Future<void> send() async {
    if (changingRole) return;
    final text = input.text, role = chat.selected;
    // Invalidate late speech synchronously, but reserve chat.busy immediately.
    // Waiting for the native player here creates a gap before submission starts.
    unawaited(audio.stopAll());
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
    if (session?.inputBusy ?? false) return;
    session?.interrupt();
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
    final voice = session;
    if (voice != null) {
      await voice.startCall(chat.selected);
      if (!mounted || !voice.calling) return;
    } else {
      await audio.stopAll();
      if (!mounted || !foreground) return;
    }
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

  void endCall({bool closeSession = true}) {
    final voice = session;
    if (voice != null && closeSession) unawaited(voice.close());
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
    if (kind == 'community') {
      endCall();
      CommunityScope.of(context)?.open();
      panelOpen = false;
      return;
    }
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
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(CommunityScope.of(context)?.username ?? '访客'),
            subtitle: const Text('社区与账户'),
            onTap: () {
              Navigator.pop(sheetContext);
              CommunityScope.of(context)?.open();
            },
          ),
        ],
        if (kind == 'roles')
          for (final role in chat.characters)
            ListTile(
              key: Key('select-${voiceRole(role.scope.characterId)}'),
              leading: role.appearance == sproutCharacterId
                  ? const CircleAvatar(
                      backgroundImage: AssetImage(sproutPortrait),
                    )
                  : null,
              title: Text(role.name),
              subtitle: Text(role.description),
              trailing: voiceRole(role.scope.characterId) == chat.selected
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(switchRole(voiceRole(role.scope.characterId)));
              },
            ),
        if (kind == 'settings') ...[
          ListTile(
            title: const Text('镜头'),
            subtitle: Text(avatarShotLabel(zoom, halfZoom)),
            onTap: () {
              changeZoom(zoom == fullAvatarZoom ? halfZoom : fullAvatarZoom);
              Navigator.pop(sheetContext);
            },
          ),
          ListTile(
            key: const Key('open-tools'),
            title: const Text('本机数据管理'),
            onTap: () {
              Navigator.pop(sheetContext);
              unawaited(openTools());
            },
          ),
          if (avatar.currentState case final scene?
              when scene.canChooseAppearance)
            ListTile(
              title: Text(scene.showsDragon ? '切回原形象' : '使用龙角形象'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(scene.chooseDragonAppearance(!scene.showsDragon));
              },
            ),
          if (avatar.currentState case final scene? when scene.supportsDragon)
            ListTile(
              title: const Text('龙角动作预览'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(scene.previewDragon());
              },
            ),
          if (avatar.currentState?.supportsSprout ?? false)
            ListTile(
              title: const Text('小芽动作预览'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(
                  showSproutAvatarPreview(
                    context,
                    zoom: zoom,
                    onZoomChanged: changeZoom,
                  ),
                );
              },
            ),
          if (avatar.currentState?.canImport == true)
            ListTile(
              title: const Text('导入人物形象'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(avatar.currentState!.choosePackage());
              },
            ),
          if (avatar.currentState case final scene?
              when scene.hasModel && !scene.showsDragon)
            ListTile(
              title: const Text('恢复内置形象'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(avatar.currentState!.clearPackage());
              },
            ),
          if (session != null)
            ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: const Text('角色声音'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(showVoices());
              },
            ),
          ListTile(
            title: Text(!chat.online ? '离线验证版' : '模型接口验证版'),
            subtitle: Text(
              !chat.online
                  ? '回复为模拟内容；录音仅供试听，通话为交互演示。'
                  : session != null
                  ? '支持文字、按住说话和连续通话。'
                  : '文字通过后端生成。录音仅本地试听，通话为演示。',
            ),
          ),
        ],
      ],
    ),
  );
  Future<void> showVoices() async {
    final voice = session;
    if (voice == null || voice.inputBusy || voice.busy) return;
    try {
      final role = chat.selected;
      final catalog = await voice.transport.voices();
      final binding = await voice.transport.binding(role);
      if (!mounted || role != chat.selected) return;
      final choices = [
        <String, Object?>{'id': '', 'name': '默认声音'},
        ...catalog.where((row) => row['status'] == 'ready'),
      ];
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('角色声音'),
          children: [
            for (final item in choices)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, item['id'] as String),
                child: Text(item['name'] as String),
              ),
          ],
        ),
      );
      if (selected != null && mounted && role == chat.selected) {
        await voice.chooseVoice(
          selected.isEmpty ? null : selected,
          binding['revision'] as int,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('声音切换失败，请结束其他通话后重试。')));
      }
    }
  }

  Future<void> openTools() async {
    toolsOpen = true;
    drafts[chat.selected] = input.text;
    await audio.stopAll();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DataManagementPage(
          database: chat.database,
          ownerId: chat.selection.ownerId,
        ),
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
              !audio.working &&
              !(session?.inputBusy ?? false),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (menu) {
              setState(() => menu = false);
            } else if (calling || (session?.inputBusy ?? false)) {
              endCall();
            } else {
              unawaited(audio.stopAll());
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: AvatarZoomGesture(
              zoom: zoom,
              onChanged: changeZoom,
              children: [
                CharacterAvatarScene(
                  key: avatar,
                  character: chat.character,
                  showMenu: false,
                  dragonImmersive: true,
                  zoom: zoom,
                  motion: session?.playing == true
                      ? AvatarSceneMotion.talking
                      : chat.busy
                      ? AvatarSceneMotion.thinking
                      : (calling && !(session?.muted ?? muted)) ||
                            session?.recording == true ||
                            audio.recording
                      ? AvatarSceneMotion.listening
                      : AvatarSceneMotion.idle,
                  mouth: session?.playing == true ? .55 : 0,
                  fallback: SizedBox.expand(
                    child: CharacterScene(
                      role: voiceRole(chat.character.appearance),
                      zoom: zoom,
                      replying: chat.busy,
                      foreground: foreground && !toolsOpen,
                    ),
                  ),
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
                                onPressed: (session?.inputBusy ?? false)
                                    ? null
                                    : () {
                                        focus.unfocus();
                                        session?.interrupt();
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
                                    !chat.online
                                        ? (chat.busy
                                              ? '正在回应 · 模拟回复'
                                              : 'AI 角色 · 离线体验')
                                        : (chat.busy
                                              ? '正在回应…'
                                              : 'AI 角色 · 在线对话'),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFE0C9C3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AvatarZoomControls(
                              zoom: zoom,
                              halfZoom: halfZoom,
                              onChanged: changeZoom,
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
                                          live: session != null,
                                          status: session?.status,
                                          subtitle: session?.subtitle,
                                          muted: session?.muted ?? muted,
                                          toggleMute: () {
                                            final voice = session;
                                            if (voice == null) {
                                              setState(() => muted = !muted);
                                            } else {
                                              unawaited(voice.toggleMute());
                                            }
                                          },
                                          end: () => endCall(),
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
                                            if (session?.status.isNotEmpty ??
                                                false)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 6,
                                                ),
                                                child: Text(
                                                  session!.status,
                                                  key: const Key(
                                                    'conversation-status',
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
                                              liveVoice: session != null,
                                              captureSeconds:
                                                  session?.recordingSeconds ??
                                                  0,
                                              capturing:
                                                  session?.holding ?? false,
                                              preparing:
                                                  session?.preparing ?? false,
                                              busy:
                                                  chat.busy ||
                                                  chat.switching ||
                                                  changingRole ||
                                                  (session?.inputBusy ?? false),
                                              mode: changeMode,
                                              send: () => unawaited(send()),
                                              call: () =>
                                                  unawaited(startCall()),
                                              startHold: () => unawaited(
                                                session?.startHold(
                                                      chat.selected,
                                                    ) ??
                                                    audio.startRecording(),
                                              ),
                                              endHold: (keep) => unawaited(
                                                session?.finishHold(keep) ??
                                                    (keep
                                                        ? audio
                                                              .finishRecording()
                                                        : audio.stopAll()),
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
