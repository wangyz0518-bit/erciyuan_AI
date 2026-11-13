import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:live2d_avatar/live2d_avatar.dart';

/// Fixed PCM WAV envelope, indexed by the actual player's position (not a fake timer).
List<double> wavEnvelope(ByteData data) {
  if (data.lengthInBytes < 44 ||
      data.getUint32(0, Endian.big) != 0x52494646 ||
      data.getUint32(8, Endian.big) != 0x57415645) {
    throw const FormatException('Not WAV');
  }
  int channels = 0, rate = 0, bits = 0, format = 0, start = 0, length = 0;
  for (int p = 12; p + 8 <= data.lengthInBytes;) {
    final id = data.getUint32(p, Endian.big),
        n = data.getUint32(p + 4, Endian.little);
    if (p + 8 + n > data.lengthInBytes) {
      throw const FormatException('Truncated WAV');
    }
    if (id == 0x666d7420 && n >= 16) {
      format = data.getUint16(p + 8, Endian.little);
      channels = data.getUint16(p + 10, Endian.little);
      rate = data.getUint32(p + 12, Endian.little);
      bits = data.getUint16(p + 22, Endian.little);
    }
    if (id == 0x64617461) {
      start = p + 8;
      length = n;
    }
    p += 8 + n + (n.isOdd ? 1 : 0);
  }
  if (format != 1 || bits != 16 || channels < 1 || rate < 1 || start == 0) {
    throw const FormatException('Expected 16-bit PCM WAV');
  }
  final step = math.max(1, (rate * channels / 20).round());
  final values = <double>[];
  for (int s = 0; s < length ~/ 2; s += step) {
    double sum = 0;
    final end = math.min(s + step, length ~/ 2);
    for (int i = s; i < end; i++) {
      final v = data.getInt16(start + i * 2, Endian.little) / 32768;
      sum += v * v;
    }
    values.add(math.sqrt(sum / (end - s)));
  }
  final peak = values.fold<double>(0, math.max);
  return values
      .map((v) => peak == 0 ? 0.0 : (v / peak).clamp(0.0, 1.0))
      .toList();
}

class Live2dPreviewPage extends StatefulWidget {
  const Live2dPreviewPage({super.key});
  @override
  State<Live2dPreviewPage> createState() => Live2dPreviewPageState();
}

class Live2dPreviewPageState extends State<Live2dPreviewPage>
    with WidgetsBindingObserver {
  final controller = Live2dController();
  final player = AudioPlayer();
  final input = TextEditingController();
  final subscriptions = <StreamSubscription<dynamic>>[];
  final messages = <String>['你好，我是 Haru。这里在验证人物展示。', '这是本地测试消息。'];
  bool ready = false,
      history = false,
      controls = true,
      full = true,
      playing = false;
  String model = 'Haru', status = '准备渲染器…';
  double mouth = 0, zoom = 1, x = 0, y = 0;
  final head = <String, double>{'headX': 0, 'headY': 0, 'headZ': 0};
  bool dragFollow = true;
  List<double> envelope = [];
  Timer? statistics;
  Map<String, dynamic> latest = {};
  int _lastFrames = 0;
  DateTime _lastSample = DateTime.now();
  double fps = 0;
  static const sound = 'live2d/Haru/sounds/haru_talk_13.wav';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(refresh);
    subscriptions.add(
      player.onPositionChanged.listen((position) {
        if (!playing || envelope.isEmpty) return;
        final index = position.inMilliseconds ~/ 50;
        mouth = index < envelope.length ? envelope[index] : 0;
        unawaited(
          safe(
            () => controller.command('mouth', number: mouth),
            updateStatus: false,
          ),
        );
      }),
    );
    subscriptions.add(
      player.onPlayerComplete.listen((_) {
        playing = false;
        mouth = 0;
        unawaited(safe(() => controller.command('mouth'), updateStatus: false));
        refresh();
      }),
    );
    unawaited(initialize());
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> safe(
    Future<void> Function() operation, {
    bool updateStatus = true,
  }) async {
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => status = '失败：$e');
      return;
    }
    if (updateStatus && mounted) setState(() => status = '操作完成');
  }

  Future<void> initialize() async {
    try {
      await controller.create();
      if (!mounted) {
        await controller.close();
        return;
      }
      ready = true;
      await loadModel('Haru');
      statistics = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!ready) return;
        try {
          final s = await controller.stats();
          if (!mounted) return;
          final now = DateTime.now();
          final frames = (s['frames'] as num).toInt();
          fps =
              (frames - _lastFrames) *
              1000 /
              now.difference(_lastSample).inMilliseconds;
          _lastFrames = frames;
          _lastSample = now;
          setState(() => latest = s);
          if (s['error'] != null) setState(() => status = '渲染失败：${s['error']}');
        } catch (e) {
          if (mounted) setState(() => status = '统计失败：$e');
        }
      });
    } catch (e) {
      if (mounted) setState(() => status = '初始化失败：$e');
    }
  }

  Future<void> stopAudio() async {
    playing = false;
    mouth = 0;
    await player.stop();
    if (ready) await controller.command('mouth');
  }

  Future<void> loadModel(String name) async {
    await stopAudio();
    await controller.load('assets/live2d/$name/$name.model3.json');
    if (!mounted) return;
    setState(() {
      model = name;
      head.updateAll((_, value) => 0);
      status =
          '$name 已加载 · 表情 ${controller.expressions.length} · 动作 ${controller.motions.length}${controller.supportsLipSync ? '' : ' · 无嘴部映射'}';
    });
  }

  Future<void> playAudio() async {
    if (!controller.loaded) return;
    if (playing) {
      await stopAudio();
      refresh();
      return;
    }
    envelope = wavEnvelope(await rootBundle.load('assets/$sound'));
    try {
      await player.play(AssetSource(sound));
      playing = true;
      refresh();
    } catch (e) {
      await stopAudio();
      rethrow;
    }
  }

  bool get canPose => ready && controller.loaded && !controller.busy;

  Future<void> setHead(String axis, double value) async {
    if (!canPose || !controller.headParameters.containsKey(axis)) return;
    final next = value.clamp(-1.0, 1.0);
    setState(() => head[axis] = next);
    await controller.command(axis, number: next);
  }

  void follow(Offset position, Size size) {
    if (!canPose || !dragFollow || size.isEmpty) return;
    unawaited(
      safe(() async {
        await setHead('headX', position.dx / size.width * 2 - 1);
        await setHead('headY', 1 - position.dy / size.height * 2);
      }, updateStatus: false),
    );
  }

  Future<void> resetPose() async {
    if (!canPose) return;
    await stopAudio();
    for (final axis in head.keys) {
      await setHead(axis, 0);
    }
    await controller.command('zoom', number: 1);
    await controller.command('x');
    await controller.command('y');
    if (mounted) {
      setState(() {
        full = true;
        zoom = 1;
        x = 0;
        y = 0;
      });
    }
  }

  Widget headSlider(String axis, String label) {
    final info = controller.headParameters[axis];
    final normalized = head[axis]!;
    final center = (info?['default'] as num?)?.toDouble() ?? 0;
    final bound =
        (info?[normalized < 0 ? 'min' : 'max'] as num?)?.toDouble() ?? 0;
    final value = center + normalized.abs() * (bound - center);
    return Row(
      children: [
        SizedBox(width: 82, child: Text(label)),
        Expanded(
          child: Slider(
            key: Key(axis),
            value: normalized,
            min: -1,
            max: 1,
            semanticFormatterCallback: (_) =>
                '$label ${value.toStringAsFixed(0)}',
            onChanged: canPose && info != null
                ? (v) => unawaited(
                    safe(() => setHead(axis, v), updateStatus: false),
                  )
                : null,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(info == null ? '不支持' : value.toStringAsFixed(0)),
        ),
      ],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ready) return;
    unawaited(
      safe(() async {
        if (state != AppLifecycleState.resumed) await stopAudio();
        await controller.setActive(state == AppLifecycleState.resumed);
      }, updateStatus: false),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    statistics?.cancel();
    ready = false;
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(player.dispose());
    controller.removeListener(refresh);
    unawaited(controller.close());
    input.dispose();
    super.dispose();
  }

  Widget action(String text, VoidCallback? callback, {Key? key}) =>
      OutlinedButton(key: key, onPressed: callback, child: Text(text));
  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live2D · 本地接入验证'),
        actions: [
          IconButton(
            key: const Key('reset-pose'),
            tooltip: '重置姿态与取景',
            onPressed: canPose ? () => unawaited(safe(resetPose)) : null,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            key: const Key('controls'),
            onPressed: () => setState(() => controls = !controls),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      drawer: Drawer(
        width: 220,
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('展示试验 · 无账号数据')),
              ListTile(
                title: const Text('Haru'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(safe(() => loadModel('Haru')));
                },
              ),
              ListTile(
                title: const Text('Mark'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(safe(() => loadModel('Mark')));
                },
              ),
              ListTile(
                title: const Text('历史面板'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => history = true);
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDED5F3), Color(0xFF5B668A)],
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    return GestureDetector(
                      key: const Key('head-drag'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: canPose && dragFollow
                          ? (d) => follow(d.localPosition, size)
                          : null,
                      onPanUpdate: canPose && dragFollow
                          ? (d) => follow(d.localPosition, size)
                          : null,
                      child: Live2dView(controller: controller),
                    );
                  },
                ),
                if (!controller.loaded)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 96,
                          color: Colors.white70,
                        ),
                        Text(
                          '静态占位 · 模型未加载',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: Text(
                    '$model · ${fps.toStringAsFixed(1)} FPS · 加载 ${latest['loadMs'] ?? '—'} ms\n$status',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      backgroundColor: Color(0x88413155),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 68,
                  child: action(
                    full ? '半身' : '全身',
                    ready
                        ? () {
                            setState(() {
                              full = !full;
                              zoom = full ? 1 : 1.65;
                              y = full ? 0 : -.55;
                            });
                            unawaited(
                              safe(() async {
                                await controller.command('zoom', number: zoom);
                                await controller.command('y', number: y);
                              }),
                            );
                          }
                        : null,
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 8,
                  child: GestureDetector(
                    onVerticalDragEnd: (_) => setState(() => history = true),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: messages.reversed
                          .take(keyboard ? 1 : 2)
                          .toList()
                          .reversed
                          .map(
                            (m) => Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 5),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .76),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                m,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                if (history)
                  Positioned.fill(
                    child: Material(
                      color: Colors.black.withValues(alpha: .15),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: IconButton(
                              key: const Key('close-history'),
                              onPressed: () => setState(() => history = false),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              children: messages
                                  .map(
                                    (m) => ListTile(
                                      tileColor: Colors.white.withValues(
                                        alpha: .55,
                                      ),
                                      title: Text(m),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (controls && !keyboard)
            SizedBox(
              height: 260,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('拖动跟随'),
                        Switch(
                          key: const Key('drag-follow'),
                          value: dragFollow,
                          onChanged: (value) =>
                              setState(() => dragFollow = value),
                        ),
                        const Expanded(
                          child: Text(
                            '拖动人物转头，松手保持',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    headSlider('headX', '左右转头'),
                    headSlider('headY', '抬头低头'),
                    headSlider('headZ', '歪头'),
                    Wrap(
                      spacing: 6,
                      children: [
                        action(
                          '加载 Haru',
                          ready && !controller.busy
                              ? () => unawaited(safe(() => loadModel('Haru')))
                              : null,
                          key: const Key('load-haru'),
                        ),
                        action(
                          '加载 Mark',
                          ready && !controller.busy
                              ? () => unawaited(safe(() => loadModel('Mark')))
                              : null,
                          key: const Key('load-mark'),
                        ),
                        action(
                          '卸载',
                          ready
                              ? () => unawaited(
                                  safe(() async {
                                    await stopAudio();
                                    await controller.unload();
                                  }),
                                )
                              : null,
                          key: const Key('unload'),
                        ),
                        action(
                          playing ? '停止音频' : '播放样例',
                          ready && controller.loaded
                              ? () => unawaited(safe(playAudio))
                              : null,
                          key: const Key('audio'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('嘴部'),
                        Expanded(
                          child: Slider(
                            key: const Key('mouth'),
                            value: mouth.clamp(0, 1),
                            onChanged: ready && controller.supportsLipSync
                                ? (v) {
                                    setState(() => mouth = v);
                                    unawaited(
                                      safe(
                                        () => controller.command(
                                          'mouth',
                                          number: v,
                                        ),
                                        updateStatus: false,
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('缩放'),
                        Expanded(
                          child: Slider(
                            value: zoom,
                            min: .4,
                            max: 3,
                            onChanged: ready
                                ? (v) {
                                    setState(() => zoom = v);
                                    unawaited(
                                      safe(
                                        () => controller.command(
                                          'zoom',
                                          number: v,
                                        ),
                                        updateStatus: false,
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('水平'),
                        Expanded(
                          child: Slider(
                            value: x,
                            min: -1,
                            max: 1,
                            onChanged: ready
                                ? (v) {
                                    setState(() => x = v);
                                    unawaited(
                                      safe(
                                        () =>
                                            controller.command('x', number: v),
                                        updateStatus: false,
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('垂直'),
                        Expanded(
                          child: Slider(
                            value: y,
                            min: -1,
                            max: 1,
                            onChanged: ready
                                ? (v) {
                                    setState(() => y = v);
                                    unawaited(
                                      safe(
                                        () =>
                                            controller.command('y', number: v),
                                        updateStatus: false,
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 5,
                      children: controller.expressions
                          .map(
                            (e) => action(
                              e,
                              () => unawaited(
                                safe(
                                  () => controller.command(
                                    'expression',
                                    value: e,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    Wrap(
                      spacing: 5,
                      children: controller.motions
                          .map(
                            (m) => action(
                              m,
                              () => unawaited(
                                safe(
                                  () => controller.command('motion', value: m),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('history'),
                    onPressed: () => setState(() => history = !history),
                    icon: const Icon(Icons.history),
                  ),
                  Expanded(
                    child: TextField(
                      key: const Key('live2d-input'),
                      controller: input,
                      decoration: const InputDecoration(
                        hintText: '输入测试文字，检查键盘叠层',
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ),
                  IconButton(
                    key: const Key('send'),
                    onPressed: () {
                      if (input.text.trim().isEmpty) return;
                      setState(() => messages.add(input.text));
                      input.clear();
                    },
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
