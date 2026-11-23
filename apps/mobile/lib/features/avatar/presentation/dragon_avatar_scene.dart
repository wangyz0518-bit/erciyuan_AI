import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import 'avatar_fallback_scene.dart';
import 'avatar_zoom.dart';

enum DragonAvatarClip {
  idle('待机'),
  listening('倾听'),
  thinking('思考'),
  talking('说话'),
  smile('轻笑');

  const DragonAvatarClip(this.label);

  final String label;

  static DragonAvatarClip forMotion(AvatarSceneMotion motion) =>
      switch (motion) {
        AvatarSceneMotion.idle => idle,
        AvatarSceneMotion.listening => listening,
        AvatarSceneMotion.thinking => thinking,
        AvatarSceneMotion.talking => talking,
      };

  String get asset => 'assets/dragon_avatar/$name';
}

class DragonAvatarScene extends StatelessWidget {
  const DragonAvatarScene({
    required this.clip,
    required this.active,
    this.loop = true,
    this.replay = 0,
    this.immersive = false,
    this.zoom = fullAvatarZoom,
    super.key,
  });

  final DragonAvatarClip clip;
  final bool active;
  final bool loop;
  final int replay;
  final bool immersive;
  final double zoom;

  @override
  Widget build(BuildContext context) => VideoAvatarScene(
    asset: clip.asset,
    label: '龙角形象 · ${clip.label}',
    active: active,
    loop: loop,
    replay: replay,
    zoom: zoom,
    background: immersive
        ? Image.asset(
            'assets/dragon_avatar/lake.webp',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          )
        : null,
  );
}

/// Shows the asset's still frame until its silent video is ready.
class VideoAvatarScene extends StatefulWidget {
  const VideoAvatarScene({
    required this.asset,
    required this.label,
    required this.active,
    this.loop = true,
    this.replay = 0,
    this.background,
    this.zoom = fullAvatarZoom,
    this.zoomAnchor = const FractionalOffset(.5, .16),
    this.extendToScene = false,
    super.key,
  });

  final String asset;
  final String label;
  final bool active;
  final bool loop;
  final int replay;
  final Widget? background;
  final double zoom;
  final FractionalOffset zoomAnchor;

  /// Grow the layer and its edge fade with the image, up to the scene edges.
  final bool extendToScene;

  @override
  State<VideoAvatarScene> createState() => _VideoAvatarSceneState();
}

class _VideoAvatarSceneState extends State<VideoAvatarScene>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  String? _loadedAsset;
  int _loadedReplay = 0;
  bool _foreground = true;
  bool _allowMotion = true;
  bool _pending = false;
  bool _busy = false;

  bool get _canPlay => _allowMotion && _foreground && widget.active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _allowMotion =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    _schedule();
  }

  @override
  void didUpdateWidget(VideoAvatarScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset ||
        oldWidget.active != widget.active ||
        oldWidget.loop != widget.loop ||
        oldWidget.replay != widget.replay) {
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _pending = true;
    if (!_busy) unawaited(_sync());
  }

  Future<void> _release(VideoPlayerController? video) async {
    try {
      await video?.dispose();
    } catch (error) {
      debugPrint('Avatar video decoder disposal failed: $error');
    }
  }

  Future<void> _sync() async {
    _busy = true;
    try {
      while (mounted && _pending) {
        _pending = false;
        final asset = widget.asset;
        if (_video != null && (_loadedAsset != asset || !_canPlay)) {
          final old = _video;
          setState(() {
            _video = null;
            _loadedAsset = null;
          });
          await _release(old);
        }
        if (!mounted || !_canPlay || widget.asset != asset) continue;
        final current = _video;
        if (current != null) {
          try {
            await current.setLooping(widget.loop);
            if (_loadedReplay != widget.replay && mounted && _canPlay) {
              _loadedReplay = widget.replay;
              await current.seekTo(Duration.zero);
              await current.play();
            }
          } catch (error) {
            debugPrint('Avatar video playback update failed: $error');
          }
          continue;
        }
        final candidate = VideoPlayerController.asset(
          '$asset.mp4',
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        var adopted = false;
        try {
          await candidate.initialize();
          if (!mounted || !_canPlay || widget.asset != asset) continue;
          await candidate.setVolume(0);
          await candidate.setLooping(widget.loop);
          await candidate.play();
          if (!mounted || !_canPlay || widget.asset != asset) continue;
          setState(() {
            _video = candidate;
            _loadedAsset = asset;
            _loadedReplay = widget.replay;
          });
          adopted = true;
        } catch (error) {
          debugPrint('Avatar video unavailable for $asset: $error');
        } finally {
          if (!adopted) await _release(candidate);
        }
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release(_video));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _loadedAsset == widget.asset ? _video : null;
    final portrait = Semantics(
      image: true,
      label: widget.label,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            '${widget.asset}.webp',
            fit: BoxFit.contain,
            gaplessPlayback: true,
            excludeFromSemantics: true,
          ),
          if (video != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: video,
              child: VideoPlayer(video),
              builder: (context, value, child) =>
                  value.hasError || !value.isInitialized
                  ? const SizedBox.shrink()
                  : child!,
            ),
        ],
      ),
    );
    final background = widget.background;
    if (background == null) {
      return Center(
        child: AspectRatio(aspectRatio: 5 / 6, child: portrait),
      );
    }
    final zoom = widget.zoom;
    final magnification = math.max(1.0, zoom);
    final framedPortrait = widget.extendToScene
        ? portrait
        : ClipRect(
            child: Transform.scale(
              scale: magnification,
              alignment: widget.zoomAnchor,
              child: portrait,
            ),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final baseWidth = math.min(width * .88, height * .77 * 5 / 6);
        final portraitWidth = baseWidth * math.min(zoom, 1.0);
        final portraitHeight = portraitWidth * 6 / 5;
        final layerScale = widget.extendToScene ? magnification : 1.0;
        final closeAmount = ((zoom - 1) / (maxAvatarZoom - 1)).clamp(0.0, 1.0);
        final top =
            height * (.19 - .05 * closeAmount) +
            (baseWidth - portraitWidth) * .6;
        final anchor = widget.zoomAnchor.alongSize(
          Size(portraitWidth, portraitHeight),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            background,
            Positioned(
              width: portraitWidth * layerScale,
              height: portraitHeight * layerScale,
              left: (width - portraitWidth) / 2 - anchor.dx * (layerScale - 1),
              top: top - anchor.dy * (layerScale - 1),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0, .11, .86, 1],
                ).createShader(bounds),
                child: framedPortrait,
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x8820202D),
                    Color(0x0320202D),
                    Color(0xD3181723),
                  ],
                  stops: [0, .36, 1],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> showDragonAvatarPreview(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _DragonAvatarPreview(),
);

class _DragonAvatarPreview extends StatefulWidget {
  const _DragonAvatarPreview();

  @override
  State<_DragonAvatarPreview> createState() => _DragonAvatarPreviewState();
}

class _DragonAvatarPreviewState extends State<_DragonAvatarPreview> {
  DragonAvatarClip _clip = DragonAvatarClip.idle;
  int _replay = 0;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('龙角动作预览'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 5 / 6,
              child: DragonAvatarScene(
                clip: _clip,
                active: true,
                loop: _clip != DragonAvatarClip.smile,
                replay: _replay,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final clip in DragonAvatarClip.values)
                  ChoiceChip(
                    label: Text(clip.label),
                    selected: _clip == clip,
                    onSelected: (_) => setState(() {
                      if (clip == _clip) _replay++;
                      _clip = clip;
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
