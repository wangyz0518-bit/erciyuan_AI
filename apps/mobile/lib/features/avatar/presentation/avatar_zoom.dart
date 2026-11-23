import 'package:material_ui/material_ui.dart';

const minAvatarZoom = .8;
const maxAvatarZoom = 3.0;
const fullAvatarZoom = 1.0;
const halfAvatarZoom = 1.45;
const sproutHalfZoom = 8 / 3;

String _multiplier(double zoom) =>
    '${zoom.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '')}×';

String avatarShotLabel(double zoom, double halfZoom) {
  if ((zoom - fullAvatarZoom).abs() < .001) return '全身';
  if ((zoom - halfZoom).abs() < .001) return '半身';
  return '自定义';
}

class AvatarZoomGesture extends StatefulWidget {
  const AvatarZoomGesture({
    super.key,
    required this.zoom,
    required this.onChanged,
    required this.children,
  });
  final double zoom;
  final ValueChanged<double> onChanged;
  final List<Widget> children;

  @override
  State<AvatarZoomGesture> createState() => _AvatarZoomGestureState();
}

class _AvatarZoomGestureState extends State<AvatarZoomGesture> {
  double _start = 1;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    excludeFromSemantics: true,
    onScaleStart: (_) => _start = widget.zoom,
    onScaleUpdate: (details) {
      if (details.pointerCount < 2) return;
      final next = (_start * details.scale)
          .clamp(minAvatarZoom, maxAvatarZoom)
          .toDouble();
      if (next != widget.zoom) widget.onChanged(next);
    },
    child: Stack(fit: StackFit.expand, children: widget.children),
  );
}

/// Both the touch gesture and the accessible slider update the same value.
class AvatarZoomControls extends StatelessWidget {
  const AvatarZoomControls({
    super.key,
    required this.zoom,
    required this.halfZoom,
    required this.onChanged,
  });
  final double zoom, halfZoom;
  final ValueChanged<double> onChanged;

  Future<void> _showSlider(BuildContext context) async {
    var value = zoom;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      barrierColor: Colors.black12,
      builder: (sheet) => StatefulBuilder(
        builder: (_, update) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('人物大小')),
                    Text(_multiplier(value)),
                    IconButton(
                      tooltip: '完成',
                      icon: const Icon(Icons.check),
                      onPressed: () => Navigator.pop(sheet),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('0.8×'),
                    Expanded(
                      child: Slider(
                        key: const Key('avatar-zoom-slider'),
                        value: value,
                        min: minAvatarZoom,
                        max: maxAvatarZoom,
                        semanticFormatterCallback: _multiplier,
                        onChanged: (next) {
                          update(() => value = next);
                          onChanged(next);
                        },
                      ),
                    ),
                    const Text('3.0×'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Tooltip(
        message: '调节人物大小',
        child: TextButton(
          key: const Key('avatar-zoom-button'),
          onPressed: () => _showSlider(context),
          child: Text(_multiplier(zoom)),
        ),
      ),
      FilledButton.tonalIcon(
        key: const Key('camera-toggle'),
        onPressed: () =>
            onChanged(zoom == fullAvatarZoom ? halfZoom : fullAvatarZoom),
        icon: const Icon(Icons.camera_alt_outlined, size: 18),
        label: Text(avatarShotLabel(zoom, halfZoom)),
      ),
    ],
  );
}
