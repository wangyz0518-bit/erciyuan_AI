import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'dragon_idle_motion.dart';

class DragonIdlePreviewApp extends StatelessWidget {
  const DragonIdlePreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '星伴 · 角色待机预览',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF71678D)),
      scaffoldBackgroundColor: const Color(0xFFE9E5EF),
    ),
    home: const DragonIdlePage(),
  );
}

class DragonIdlePage extends StatefulWidget {
  const DragonIdlePage({super.key});

  @override
  State<DragonIdlePage> createState() => DragonIdlePageState();
}

class DragonIdlePageState extends State<DragonIdlePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const asset = 'assets/characters/dragon-character-v1.png';
  final time = ValueNotifier<double>(0);
  final appearance = ValueNotifier<(double, bool)>((.75, false));
  late final Ticker _ticker;
  _DragonPainter? _painter;
  Duration? _previous;
  bool playing = true, closeView = false, foreground = true;
  bool _reduceMotion = false, loading = false;
  String? error;
  double intensity = .75;
  bool get loaded => _painter != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((elapsed) {
      final previous = _previous;
      _previous = elapsed;
      if (previous != null) {
        time.value += ((elapsed - previous).inMicroseconds / 1e6).clamp(
          0.0,
          .1,
        );
      }
    });
    loadCharacter();
  }

  Future<void> loadCharacter() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final bytes = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      late final ui.FrameInfo frame;
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _painter = _DragonPainter(frame.image, time, appearance));
      _syncTicker();
    } catch (_) {
      if (mounted) setState(() => error = '角色图片加载失败');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _syncTicker() {
    final active =
        loaded && playing && foreground && !_reduceMotion && intensity > 0;
    if (active == _ticker.isActive) return;
    _previous = null;
    if (active) {
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  void resetPreview() {
    setState(() {
      intensity = .75;
      closeView = false;
      playing = true;
      time.value = 0;
    });
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    time.dispose();
    appearance.dispose();
    _painter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _painter;
    appearance.value = (intensity, closeView);
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色待机预览'),
        backgroundColor: const Color(0xFFE9E5EF),
        actions: [
          IconButton(
            key: const Key('idle-reset'),
            tooltip: '恢复默认',
            onPressed: loaded ? resetPreview : null,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.2),
                  radius: 1,
                  colors: [Color(0xFFF5F1F8), Color(0xFFC1B8D0)],
                ),
              ),
              child: SizedBox.expand(
                child: painter != null
                    ? Semantics(
                        label: '白发龙角角色，轻微呼吸与自然待机',
                        child: RepaintBoundary(
                          key: const Key('idle-avatar'),
                          child: CustomPaint(painter: painter),
                        ),
                      )
                    : Center(
                        child: error == null
                            ? const CircularProgressIndicator()
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(error!),
                                  TextButton(
                                    onPressed: loadCharacter,
                                    child: const Text('重新加载'),
                                  ),
                                ],
                              ),
                      ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const Key('idle-play'),
                        onPressed: loaded
                            ? () {
                                setState(() => playing = !playing);
                                _syncTicker();
                              }
                            : null,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        label: Text(playing ? '暂停动作' : '继续动作'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        key: const Key('idle-framing'),
                        onPressed: loaded
                            ? () => setState(() => closeView = !closeView)
                            : null,
                        child: Text(closeView ? '完整人物' : '近景观察'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('动作幅度'),
                      Expanded(
                        child: Slider(
                          key: const Key('idle-intensity'),
                          value: intensity,
                          semanticFormatterCallback: (value) =>
                              '${(value * 100).round()}%',
                          onChanged: loaded
                              ? (value) {
                                  setState(() => intensity = value);
                                  _syncTicker();
                                }
                              : null,
                        ),
                      ),
                      Text('${(intensity * 100).round()}%'),
                    ],
                  ),
                  if (_reduceMotion) const Text('已遵循系统减少动画设置'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DragonPainter extends CustomPainter {
  _DragonPainter(this.image, this.time, this.appearance)
    : super(repaint: Listenable.merge([time, appearance])) {
    texture = mesh.textureCoordinates(image.width, image.height);
    shader = ui.ImageShader(
      image,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
      filterQuality: FilterQuality.medium,
    );
    paintImage.shader = shader;
  }

  final ui.Image image;
  final ValueNotifier<double> time;
  final ValueNotifier<(double, bool)> appearance;
  final DragonIdleMesh mesh = DragonIdleMesh();
  final Paint paintImage = Paint()..isAntiAlias = true;
  late final Float32List texture;
  late final ui.ImageShader shader;

  @override
  void paint(Canvas canvas, Size size) {
    final (intensity, closeView) = appearance.value;
    mesh.update(time.value, intensity);
    final scale =
        math.min(size.width / image.width, size.height / image.height) * .92;
    final width = image.width * scale * (closeView ? 1.55 : 1);
    final height = image.height * scale * (closeView ? 1.55 : 1);
    final left = size.width / 2 - width * .5;
    final top = closeView
        ? size.height * .48 - height * .38
        : (size.height - height) / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(left, top);
    canvas.scale(width, height);
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      mesh.positions,
      textureCoordinates: texture,
      indices: mesh.indices,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, paintImage);
    vertices.dispose();
    canvas.restore();
  }

  void dispose() {
    shader.dispose();
    image.dispose();
  }

  @override
  bool shouldRepaint(covariant _DragonPainter oldDelegate) => true;
}
