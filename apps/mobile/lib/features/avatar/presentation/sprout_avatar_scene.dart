import 'package:material_ui/material_ui.dart';

import 'avatar_fallback_scene.dart';
import 'avatar_zoom.dart';
import 'dragon_avatar_scene.dart';

const sproutAvatarDirectory = 'assets/sprout_avatar';
const sproutPortrait = '$sproutAvatarDirectory/portrait.webp';

class SproutAvatarScene extends StatelessWidget {
  const SproutAvatarScene({
    super.key,
    required this.motion,
    required this.active,
    this.immersive = false,
    this.zoom = fullAvatarZoom,
  });

  final AvatarSceneMotion motion;
  final bool active;
  final bool immersive;
  final double zoom;

  @override
  Widget build(BuildContext context) => VideoAvatarScene(
    asset: '$sproutAvatarDirectory/${motion.name}',
    label: '小芽 · ${motion.label}',
    active: active,
    zoom: zoom,
    // Hold the head in place while the skirt extends behind the chat controls.
    zoomAnchor: const FractionalOffset(.5, 52 / (576 - 216)),
    extendToScene: true,
    background: immersive
        ? const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFAADBEA), Color(0xFFD1EEF3)],
              ),
            ),
          )
        : null,
  );
}

Future<void> showSproutAvatarPreview(
  BuildContext context, {
  double zoom = sproutHalfZoom,
  ValueChanged<double>? onZoomChanged,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        _SproutPreview(initialZoom: zoom, onZoomChanged: onZoomChanged),
  ),
);

class _SproutPreview extends StatefulWidget {
  const _SproutPreview({required this.initialZoom, this.onZoomChanged});
  final double initialZoom;
  final ValueChanged<double>? onZoomChanged;

  @override
  State<_SproutPreview> createState() => _SproutPreviewState();
}

class _SproutPreviewState extends State<_SproutPreview> {
  AvatarSceneMotion motion = AvatarSceneMotion.idle;
  late double zoom = widget.initialZoom;

  void changeZoom(double next) {
    setState(() => zoom = next);
    widget.onZoomChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AvatarZoomGesture(
      zoom: zoom,
      onChanged: changeZoom,
      children: [
        SproutAvatarScene(
          motion: motion,
          active: true,
          immersive: true,
          zoom: zoom,
        ),
        SafeArea(
          minimum: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  const BackButton(),
                  const Expanded(child: Text('小芽动作预览')),
                  AvatarZoomControls(
                    zoom: zoom,
                    halfZoom: sproutHalfZoom,
                    onChanged: changeZoom,
                  ),
                ],
              ),
              const Spacer(),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (final state in AvatarSceneMotion.values)
                    ChoiceChip(
                      label: Text(state.label),
                      selected: state == motion,
                      onSelected: (_) => setState(() => motion = state),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
