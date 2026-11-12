import 'package:material_ui/material_ui.dart';

class CallOverlay extends StatelessWidget {
  const CallOverlay({
    super.key,
    required this.seconds,
    required this.muted,
    required this.toggleMute,
    required this.end,
  });
  final int seconds;
  final bool muted;
  final VoidCallback toggleMute, end;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('通话演示', style: TextStyle(color: Color(0xFFF6BC9F))),
      Text(
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
        key: const Key('call-time'),
        style: const TextStyle(fontSize: 36),
      ),
      const Text('尚未接通语音服务', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              IconButton.filledTonal(
                key: const Key('mute-call'),
                tooltip: muted ? '取消静音' : '静音',
                iconSize: 30,
                onPressed: toggleMute,
                icon: Icon(muted ? Icons.mic_off : Icons.mic),
              ),
              Text(muted ? '已静音' : '静音'),
            ],
          ),
          Column(
            children: [
              IconButton.filled(
                key: const Key('end-call'),
                tooltip: '挂断',
                iconSize: 30,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFBD4E59),
                ),
                onPressed: end,
                icon: const Icon(Icons.call_end),
              ),
              const Text('挂断'),
            ],
          ),
        ],
      ),
      const SizedBox(height: 24),
    ],
  );
}
