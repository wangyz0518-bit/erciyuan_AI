import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../audio/application/audio_session_controller.dart';
import '../../audio/data/platform_audio_adapters.dart';
import '../../audio/domain/audio_ports.dart';
import '../../avatar/presentation/avatar_fallback_scene.dart';
import '../../chat/application/continuous_chat_controller.dart';
import '../../chat/data/model_gateway_adapter.dart';
import '../../timeline/data/person_database.dart';
import '../../timeline/domain/raw_event.dart';
import '../../voice/application/voice_assist_controller.dart';
import '../../voice/data/system_voice_adapters.dart';
import '../application/character_selection_controller.dart';
import '../domain/character.dart';

/// The only chat page for one character. No session identifier or new-chat UI.
class ContinuousChatPage extends StatefulWidget {
  const ContinuousChatPage({
    required this.selection,
    required this.database,
    required this.scope,
    this.gateway,
    this.audioSession,
    this.voiceAssist,
    super.key,
  });

  final CharacterSelectionController selection;
  final PersonDatabase database;
  final PersonScope scope;
  final ModelGatewayAdapter? gateway;

  /// Optional injectable audio scope for widget/device tests.
  final AudioSessionController? audioSession;
  final VoiceAssistController? voiceAssist;

  @override
  State<ContinuousChatPage> createState() => _ContinuousChatPageState();
}

class _ContinuousChatPageState extends State<ContinuousChatPage>
    with WidgetsBindingObserver {
  late final ContinuousChatController _chat;
  late final TextEditingController _input;
  late final AudioSessionController _audio;
  late final VoiceAssistController _voice;
  bool _speechActivated = false;
  bool _slideCancelled = false;
  final ScrollController _scroll = ScrollController();

  Character get _character => widget.selection.characters.firstWhere(
    (character) => character.scope == widget.scope,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio = widget.audioSession ?? createDeviceAudioSession();
    _voice = widget.voiceAssist ?? createDeviceVoiceAssist();
    _chat = ContinuousChatController(
      database: widget.database,
      scope: widget.scope,
      characterName: widget.selection.characters
          .firstWhere((character) => character.scope == widget.scope)
          .name,
      gateway: widget.gateway,
    );
    _input = TextEditingController(
      text: widget.selection.draftFor(widget.scope),
    );
    _input.addListener(_refreshInput);
    _chat.addListener(_scrollWhenFollowing);
    unawaited(_chat.load());
  }

  void _refreshInput() {
    if (mounted) setState(() {});
  }

  void _scrollWhenFollowing() {
    if (!_scroll.hasClients || _scroll.position.extentAfter < 140) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_audio.discard());
      unawaited(_voice.stopAll());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_audio.close());
    _audio.dispose();
    unawaited(_voice.close());
    _voice.dispose();
    _chat.removeListener(_scrollWhenFollowing);
    _chat.dispose();
    _input.removeListener(_refreshInput);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _switchCharacter(PersonScope scope) {
    if (scope == widget.scope) return;
    FocusScope.of(context).unfocus();
    widget.selection.selectCharacter(scope);
    unawaited(_audio.discard());
    unawaited(_voice.stopAll());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => ContinuousChatPage(
          selection: widget.selection,
          database: widget.database,
          scope: scope,
          gateway: widget.gateway,
        ),
      ),
    );
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || _chat.isSending) return;
    _input.clear();
    widget.selection.updateDraft(widget.scope, '');
    unawaited(_chat.send(text));
  }

  @override
  Widget build(BuildContext context) {
    final character = _character;
    return Scaffold(
      backgroundColor: const Color(0xFF161B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF22283B),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(character.name, style: const TextStyle(fontSize: 19)),
            const Text(
              '唯一持续时间线',
              style: TextStyle(fontSize: 11, color: Color(0xFFC7D1E4)),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<PersonScope>(
            key: const ValueKey('chat-switch-character'),
            tooltip: '切换人物',
            icon: const Icon(Icons.people_outline),
            onSelected: _switchCharacter,
            itemBuilder: (_) => [
              for (final choice in widget.selection.characters)
                PopupMenuItem(value: choice.scope, child: Text(choice.name)),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: Listenable.merge([_chat, _audio, _voice]),
          builder: (context, _) => Column(
            children: [
              _CharacterScene(
                character: character,
                isReplying: _chat.isSending,
              ),
              _modeRibbon(),
              Expanded(
                child: _chat.isLoading && _chat.events.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _chat.events.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有聊天记录。\n这里将一直保存与这位人物的对话。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFD7DBE7)),
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey('persistent-message-list'),
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        itemCount:
                            _chat.events.length +
                            (_chat.streamedText.isNotEmpty ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _chat.events.length) {
                            return _MessageBubble(
                              content: _chat.streamedText,
                              speaker: 'assistant',
                              name: character.name,
                              isStreaming: true,
                            );
                          }
                          final event = _chat.events[i];
                          return _MessageBubble.fromEvent(
                            event,
                            name: character.name,
                            onSpeak:
                                event.speaker == 'assistant' &&
                                    event.status == 'complete'
                                ? () => unawaited(
                                    _requestSystemSpeak(event.content),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
              if (_chat.statusMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: const Color(0xFF292D43),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        _chat.statusMessage!,
                        key: const ValueKey('turn-status'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE9E5F6),
                        ),
                      ),
                      if (_chat.isSending)
                        TextButton(
                          key: const ValueKey('cancel-turn'),
                          onPressed: () => unawaited(_chat.cancel()),
                          child: const Text('取消'),
                        ),
                      if (_chat.canRetry)
                        TextButton(
                          key: const ValueKey('retry-turn'),
                          onPressed: () => unawaited(_chat.retry()),
                          child: const Text('重试'),
                        ),
                      if (_chat.canReconcile)
                        TextButton(
                          key: const ValueKey('reconcile-turn'),
                          onPressed: () => unawaited(_chat.reconcile()),
                          child: const Text('查询原请求'),
                        ),
                    ],
                  ),
                ),
              _audioControls(),
              _speechControls(),
              _composer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeRibbon() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    color: const Color(0xFF303750),
    child: Row(
      children: [
        Icon(
          _chat.isMock ? Icons.science_outlined : Icons.cloud_outlined,
          color: const Color(0xFFD8C5FF),
          size: 16,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _chat.isMock ? '离线 Mock 模式 · 回复仅供界面测试' : '文字网关模式 · 服务端鉴权仅供受控开发',
            key: const ValueKey('chat-mode'),
            style: const TextStyle(fontSize: 12, color: Color(0xFFF3E9FF)),
          ),
        ),
        TextButton(
          key: const ValueKey('history-refresh'),
          onPressed: _chat.isLoading ? null : () => unawaited(_chat.load()),
          child: const Text('历史'),
        ),
      ],
    ),
  );

  Widget _composer() => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF22283B),
      border: Border(top: BorderSide(color: Color(0xFF444A63))),
    ),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('character-draft'),
            controller: _input,
            style: const TextStyle(color: Colors.white),
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            onChanged: (value) =>
                widget.selection.updateDraft(widget.scope, value),
            decoration: InputDecoration(
              hintText: '想和${_character.name}说什么？',
              hintStyle: const TextStyle(color: Color(0xFFB0BAD2)),
              filled: true,
              fillColor: const Color(0xFF323A52),
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _recordButton(),
        _recognizeButton(),
        const SizedBox(width: 6),
        IconButton.filled(
          key: const ValueKey('send-message'),
          tooltip: '发送文字消息',
          onPressed: _chat.isSending || _input.text.trim().isEmpty
              ? null
              : _send,
          icon: const Icon(Icons.send_rounded),
        ),
      ],
    ),
  );
  Future<void> _requestSystemSpeak(String text) async {
    // The user must explicitly authorize each use of a potentially
    // network-backed OS speech engine before any chat text is supplied to it.
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('使用系统语音朗读？'),
        content: const Text(
          '系统语音引擎由设备管理，可能联网处理本条回复。'
          '这不是人物专属音色；如果不同意向系统语音服务提供文字，请取消。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('同意朗读本条'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    await _voice.speak(text);
  }

  Future<void> _beginRecognition() async {
    _speechActivated = true;
    await _audio.discard();
    if (!mounted) return;
    await _voice.beginRecognition();
  }

  Widget _recognizeButton() => IconButton(
    key: const ValueKey('speech-recognize'),
    tooltip: _voice.listening ? '停止识别，等待编辑' : '设备端中文语音识别（需系统授权）',
    onPressed: () {
      _speechActivated = true;
      if (_voice.listening) {
        unawaited(_voice.stopRecognition());
      } else {
        unawaited(_beginRecognition());
      }
    },
    icon: Icon(
      _voice.listening
          ? Icons.stop_circle_outlined
          : Icons.record_voice_over_outlined,
    ),
  );

  Widget _speechControls() {
    if (!_speechActivated && !_voice.speaking) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('speech-result'),
      width: double.infinity,
      color: const Color(0xFF303750),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _voice.status,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
          if (_voice.editableCandidate.isNotEmpty)
            Text(
              '识别：${_voice.editableCandidate}',
              style: const TextStyle(fontSize: 11),
            ),
          if (_voice.editableCandidate.isNotEmpty && !_voice.listening)
            TextButton(
              key: const ValueKey('apply-recognition-to-draft'),
              onPressed: () {
                _input.text = _voice.editableCandidate;
                _input.selection = TextSelection.collapsed(
                  offset: _input.text.length,
                );
                widget.selection.updateDraft(widget.scope, _input.text);
                _voice.clearTranscript();
              },
              child: const Text('填入草稿（仍需编辑发送）'),
            ),
          if (_voice.speaking)
            TextButton(
              key: const ValueKey('stop-system-tts'),
              onPressed: () => unawaited(_voice.stopAll()),
              child: const Text('停止朗读'),
            ),
        ],
      ),
    );
  }

  Widget _audioControls() {
    if (_audio.state == AudioSessionState.idle ||
        _audio.state == AudioSessionState.closed) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('local-audio-status'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: const Color(0xFF32354C),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(
            _audio.status,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
          if (_audio.hasClip && _audio.state != AudioSessionState.playing)
            TextButton(
              key: const ValueKey('preview-local-audio'),
              onPressed: () => unawaited(_audio.play()),
              child: const Text('试听'),
            ),
          if (_audio.state == AudioSessionState.playing)
            TextButton(
              key: const ValueKey('stop-local-audio'),
              onPressed: () => unawaited(_audio.stopPlayback()),
              child: const Text('停止'),
            ),
          if (_audio.hasClip ||
              _audio.state == AudioSessionState.recording ||
              _audio.state == AudioSessionState.requestingPermission)
            TextButton(
              key: const ValueKey('discard-local-audio'),
              onPressed: () => unawaited(_audio.discard()),
              child: const Text('删除/取消'),
            ),
        ],
      ),
    );
  }

  Widget _recordButton() => Semantics(
    button: true,
    label: '按住录音，松开保存本地试听，向左滑出取消',
    onTap: () {
      if (_audio.state == AudioSessionState.recording) {
        unawaited(_audio.finish());
      } else {
        unawaited(_audio.begin());
      }
    },
    child: Listener(
      onPointerDown: (_) {
        _slideCancelled = false;
        unawaited(_voice.stopAll());
        unawaited(_audio.begin());
      },
      onPointerMove: (event) {
        if (event.localPosition.dx < -24 || event.localPosition.dy < -24) {
          _slideCancelled = true;
        }
      },
      onPointerUp: (_) =>
          unawaited(_slideCancelled ? _audio.discard() : _audio.finish()),
      onPointerCancel: (_) => unawaited(_audio.discard()),
      child: Container(
        key: const ValueKey('hold-to-record'),
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _audio.state == AudioSessionState.recording
              ? const Color(0xFF9E566D)
              : const Color(0xFF434B67),
          borderRadius: BorderRadius.circular(25),
        ),
        child: const Icon(Icons.mic_none_outlined, color: Colors.white),
      ),
    ),
  );
}

class _CharacterScene extends StatelessWidget {
  const _CharacterScene({required this.character, required this.isReplying});

  final Character character;
  final bool isReplying;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('character-scene'),
    height: 172,
    width: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF51456A), Color(0xFF252B42)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: 18,
          bottom: -38,
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 170,
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        Center(
          child: AvatarFallbackScene(
            characterId: character.scope.characterId,
            characterName: character.name,
            motion: isReplying
                ? AvatarSceneMotion.talking
                : AvatarSceneMotion.idle,
          ),
        ),
        Positioned(
          left: 16,
          bottom: 12,
          child: Text(
            isReplying ? '${character.name}正在回应…' : '和${character.name}继续今天的故事',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        const Positioned(
          right: 12,
          top: 12,
          child: Text(
            '静态形象占位 · Live2D 待接入',
            style: TextStyle(color: Color(0xFFE7E2F0), fontSize: 10),
          ),
        ),
      ],
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.content,
    required this.speaker,
    required this.name,
    this.isStreaming = false,
    this.onSpeak,
  });

  factory _MessageBubble.fromEvent(
    RawEvent event, {
    required String name,
    VoidCallback? onSpeak,
  }) => _MessageBubble(
    content: event.status == 'redacted' ? '（已删除的内容）' : event.content,
    speaker: event.speaker,
    name: name,
    onSpeak: onSpeak,
  );

  final String content;
  final String speaker;
  final String name;
  final bool isStreaming;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final mine = speaker == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFF62579E) : const Color(0xFF363E57),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mine ? '我' : name,
                style: const TextStyle(
                  color: Color(0xFFE7C7FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              SelectableText(
                content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              if (onSpeak != null && !mine && !isStreaming)
                TextButton.icon(
                  onPressed: onSpeak,
                  icon: const Icon(Icons.volume_up_outlined, size: 15),
                  label: const Text('系统朗读'),
                ),
              if (isStreaming)
                const Text(
                  '生成中 · 尚未写入历史',
                  style: TextStyle(color: Color(0xFFCEC6E6), fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
