import 'package:material_ui/material_ui.dart';

import '../audio_controller.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.textMode,
    required this.input,
    required this.focus,
    required this.audio,
    required this.busy,
    required this.mode,
    required this.send,
    required this.call,
    required this.startHold,
    required this.endHold,
  });
  final bool textMode, busy;
  final TextEditingController input;
  final FocusNode focus;
  final AudioController audio;
  final VoidCallback mode, send, call, startHold;
  final ValueChanged<bool> endHold;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      IconButton.filledTonal(
        key: Key(textMode ? 'voice-mode' : 'text-mode'),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF24222F),
          foregroundColor: const Color(0xFFFAF0E8),
        ),
        tooltip: textMode ? '切换语音' : '切换键盘',
        onPressed: mode,
        icon: Icon(textMode ? Icons.mic_none : Icons.keyboard_outlined),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: textMode
            ? TextField(
                key: const Key('message-input'),
                controller: input,
                focusNode: focus,
                minLines: 1,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(
                  hintText: '说点什么…',
                  counterText: '',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                ),
                textInputAction: TextInputAction.newline,
              )
            : HoldToRecord(
                enabled: !busy && !audio.working,
                start: startHold,
                end: endHold,
                label: audio.recording ? '松开试听 · ${audio.seconds}s' : '按住说话',
              ),
      ),
      const SizedBox(width: 8),
      if (textMode)
        FilledButton(
          key: const Key('send'),
          onPressed: busy || input.text.trim().isEmpty ? null : send,
          child: const Text('发送'),
        )
      else
        IconButton.filledTonal(
          key: const Key('start-call'),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF24222F),
            foregroundColor: const Color(0xFFFAF0E8),
          ),
          tooltip: '通话演示',
          onPressed: audio.recording || audio.working ? null : call,
          icon: const Icon(Icons.call_outlined),
        ),
    ],
  );
}

class HoldToRecord extends StatefulWidget {
  const HoldToRecord({
    super.key,
    required this.enabled,
    required this.start,
    required this.end,
    required this.label,
  });
  final bool enabled;
  final VoidCallback start;
  final ValueChanged<bool> end;
  final String label;
  @override
  State<HoldToRecord> createState() => _HoldToRecordState();
}

class _HoldToRecordState extends State<HoldToRecord> {
  int? pointer;
  bool outside = false;
  void finish(bool keep) {
    if (pointer == null) return;
    pointer = null;
    widget.end(keep && !outside);
    if (mounted) setState(() => outside = false);
  }

  bool inside(Offset p) {
    final size = context.size;
    return size != null && (Offset.zero & size).contains(p);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    child: Listener(
      key: const Key('hold-record'),
      onPointerDown: (e) {
        if (!widget.enabled || pointer != null) return;
        pointer = e.pointer;
        outside = false;
        widget.start();
      },
      onPointerMove: (e) {
        if (pointer == e.pointer) {
          setState(() => outside = !inside(e.localPosition));
        }
      },
      onPointerUp: (e) {
        if (pointer == e.pointer) finish(inside(e.localPosition));
      },
      onPointerCancel: (e) {
        if (pointer == e.pointer) finish(false);
      },
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF302532),
          border: Border.all(color: const Color(0xFF67545C)),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Text(
          outside ? '松开取消' : widget.label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    ),
  );
}
