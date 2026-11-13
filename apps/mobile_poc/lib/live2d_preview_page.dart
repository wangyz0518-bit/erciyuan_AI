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

const parameterLabels = {
  'ParamAngleX': '左右转头',
  'ParamAngleY': '抬头低头',
  'ParamAngleZ': '歪头',
  'ParamFaceForm': '脸部缩放',
  'ParamTere': '脸红',
  'ParamTear': '眼泪',
  'ParamEyeLOpen': '左眼开合',
  'ParamEyeROpen': '右眼开合',
  'ParamEyeLSmile': '左眼笑形',
  'ParamEyeRSmile': '右眼笑形',
  'ParamEyeBallX': '视线左右',
  'ParamEyeBallY': '视线上下',
  'ParamEyeForm': '眼形',
  'ParamEyeBallForm': '瞳孔收缩',
  'ParamBrowLX': '左眉左右',
  'ParamBrowRX': '右眉左右',
  'ParamBrowLY': '左眉上下',
  'ParamBrowRY': '右眉上下',
  'ParamBrowLAngle': '左眉角度',
  'ParamBrowRAngle': '右眉角度',
  'ParamBrowLForm': '左眉形状',
  'ParamBrowRForm': '右眉形状',
  'ParamMouthForm': '嘴形',
  'ParamMouthOpenY': '嘴部开合',
  'ParamBodyAngleX': '躯干左右转动',
  'ParamBodyAngleY': '躯干前后',
  'ParamBodyAngleZ': '躯干侧倾',
  'ParamBodyUpper': '上身姿态',
  'ParamBreath': '呼吸',
  'ParamBustY': '胸部摆动',
  'ParamArmL': '左臂',
  'ParamArmR': '右臂',
  'ParamArmLA': '左臂 A',
  'ParamArmRA': '右臂 A',
  'ParamArmLB': '左臂 B',
  'ParamArmRB': '右臂 B',
  'ParamHandAngleL': '左手腕',
  'ParamHandAngleR': '右手腕',
  'ParamHandChangeR': '右手型',
  'ParamHandDhangeL': '左手型',
  'ParamLeftLeg': '左腿',
  'ParamRightLeg': '右腿',
  'ParamHairFront': '前发',
  'ParamHairSide': '侧发',
  'ParamHairBack': '后发',
  'ParamScarf': '围巾',
};

String parameterGroup(String id) {
  if (id.startsWith('ParamAngle') || id == 'ParamFaceForm') return '头部';
  if (id.startsWith('ParamEye') ||
      id.startsWith('ParamBrow') ||
      id == 'ParamTere' ||
      id == 'ParamTear') {
    return '眼睛与眉毛';
  }
  if (id.startsWith('ParamMouth')) return '嘴部';
  if (id.startsWith('ParamBody') || id == 'ParamBreath' || id == 'ParamBustY') {
    return '躯干';
  }
  if (id.startsWith('ParamArm') || id.startsWith('Part01Arm')) return '手臂';
  if (id.startsWith('ParamHand')) return '手腕与手型';
  if (id.contains('Leg')) return '腿部';
  if (id.startsWith('ParamHair') || id == 'ParamScarf') return '头发与服饰';
  return '其他';
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
  bool pureAvatar = true, manualPose = false, _changingModel = false;
  String parameterSection = '头部';
  String panel = '部位';
  Map<String, double> poseValues = {};
  List<int> partSelections = [];
  int _poseRevision = 0;
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
        final revision = _poseRevision;
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
          setState(() {
            latest = s;
            if (!manualPose && revision == _poseRevision && !_changingModel) {
              poseValues = Map<String, double>.from(s['parameters'] as Map);
              partSelections = List<int>.from(s['partSelections'] as List);
            }
          });
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
    if (_changingModel) return;
    setState(() => _changingModel = true);
    ++_poseRevision;
    try {
      await stopAudio();
      if (!mounted) return;
      await controller.load('assets/live2d/$name/$name.model3.json');
      if (!mounted) return;
      setState(() {
        model = name;
        poseValues = {};
        partSelections = [];
        manualPose = false;
        if (!parameterGroups.containsKey(parameterSection)) {
          parameterSection = parameterGroups.keys.firstOrNull ?? '头部';
        }
        status = '${controller.parameters.length} 个参数';
      });
    } finally {
      if (mounted) setState(() => _changingModel = false);
    }
  }

  Future<void> playAudio() async {
    if (!canPose) return;
    if (playing) {
      await stopAudio();
      refresh();
      return;
    }
    envelope = wavEnvelope(await rootBundle.load('assets/$sound'));
    if (!canPose) return;
    try {
      await useAutomaticPose();
      await player.play(AssetSource(sound));
      playing = true;
      refresh();
    } catch (e) {
      await stopAudio();
      rethrow;
    }
  }

  bool get canPose =>
      ready && controller.loaded && !controller.busy && !_changingModel;

  Map<String, List<Live2dParameter>> get parameterGroups {
    final groups = <String, List<Live2dParameter>>{};
    for (final parameter in controller.parameters.values) {
      (groups[parameterGroup(parameter.id)] ??= []).add(parameter);
    }
    return groups;
  }

  Future<void> editPose(
    Map<String, double> changes, {
    Map<int, int> parts = const {},
  }) async {
    if (!canPose) return;
    final revision = ++_poseRevision;
    setState(() {
      manualPose = true;
      poseValues.addAll(changes);
    });
    final pending = controller.setPose(changes, parts: parts);
    final stopping = playing ? stopAudio() : Future<void>.value();
    try {
      final pose = await pending;
      if (mounted && revision == _poseRevision) {
        setState(() {
          poseValues = Map<String, double>.from(pose['parameters'] as Map);
          partSelections = List<int>.from(pose['partSelections'] as List);
        });
      }
    } finally {
      await stopping;
    }
  }

  Future<void> useAutomaticPose({
    String command = 'automaticPose',
    String value = '',
  }) async {
    final revision = ++_poseRevision;
    await controller.command(command, value: value);
    if (mounted && revision == _poseRevision) {
      setState(() => manualPose = false);
    }
  }

  Future<void> resetParameters(
    Iterable<Live2dParameter> parameters, {
    bool resetParts = false,
  }) => editPose(
    {for (final p in parameters) p.id: p.defaultValue},
    parts: {
      if (resetParts)
        for (int i = 0; i < controller.poseParts.length; ++i) i: 0,
    },
  );

  void follow(Offset position, Size size) {
    if (!canPose || !dragFollow || size.isEmpty) return;
    final changes = <String, double>{};
    void addAngle(String id, double value) {
      final p = controller.parameters[id];
      if (p == null) return;
      final bound = value < 0 ? p.min : p.max;
      changes[id] =
          p.defaultValue +
          value.abs().clamp(0.0, 1.0) * (bound - p.defaultValue);
    }

    addAngle('ParamAngleX', position.dx / size.width * 2 - 1);
    addAngle('ParamAngleY', 1 - position.dy / size.height * 2);
    if (changes.isNotEmpty) {
      unawaited(safe(() => editPose(changes), updateStatus: false));
    }
  }

  Future<void> resetPose() async {
    if (!canPose) return;
    setState(() {
      full = true;
      zoom = 1;
      x = 0;
      y = 0;
    });
    // Queue the entire reset before yielding, so a later user gesture wins.
    await Future.wait([
      resetParameters(controller.parameters.values, resetParts: true),
      controller.command('zoom', number: 1),
      controller.command('x'),
      controller.command('y'),
    ]);
  }

  Widget parameterSlider(Live2dParameter p) {
    final label = parameterLabels[p.id] ?? p.id;
    final value = (poseValues[p.id] ?? p.defaultValue).clamp(p.min, p.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value.toStringAsFixed(2)),
            IconButton(
              key: Key('reset-${p.id}'),
              tooltip: '重置$label',
              onPressed: canPose
                  ? () => unawaited(safe(() => resetParameters([p])))
                  : null,
              icon: const Icon(Icons.restart_alt, size: 18),
            ),
          ],
        ),
        Slider(
          key: Key(p.id),
          min: p.min,
          max: p.max,
          value: value,
          semanticFormatterCallback: (value) =>
              '$label ${value.toStringAsFixed(2)}',
          onChanged: canPose && p.max > p.min
              ? (value) => unawaited(
                  safe(() => editPose({p.id: value}), updateStatus: false),
                )
              : null,
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

  Widget parameterPanel() {
    final groups = parameterGroups;
    final parameters = groups[parameterSection] ?? const [];
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                key: const Key('parameter-group'),
                isExpanded: true,
                value: groups.containsKey(parameterSection)
                    ? parameterSection
                    : null,
                hint: const Text('选择部位'),
                items: [
                  for (final group in groups.keys)
                    DropdownMenuItem(value: group, child: Text(group)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => parameterSection = value);
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('reset-group'),
              onPressed: canPose && parameters.isNotEmpty
                  ? () => unawaited(
                      safe(
                        () => resetParameters(
                          parameters,
                          resetParts: parameterSection == '手臂',
                        ),
                      ),
                    )
                  : null,
              child: const Text('重置部位'),
            ),
          ],
        ),
        if (parameterSection == '手臂' || parameterSection == '手腕与手型')
          for (int group = 0; group < controller.poseParts.length; group++)
            partSelector(group),
        for (final parameter in parameters) parameterSlider(parameter),
      ],
    );
  }

  Widget partSelector(int group) {
    final parts = controller.poseParts[group];
    final side = parts.first.startsWith('Part01ArmR')
        ? '右臂'
        : parts.first.startsWith('Part01ArmL')
        ? '左臂'
        : '外形 ${group + 1}';
    return Row(
      children: [
        Expanded(child: Text('$side 外形')),
        for (int index = 0; index < parts.length; index++)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              key: Key('part-$group-$index'),
              label: Text(
                index == 0
                    ? 'A'
                    : index == 1
                    ? 'B'
                    : '${index + 1}',
              ),
              selected:
                  index ==
                  (group < partSelections.length ? partSelections[group] : 0),
              onSelected: canPose
                  ? (_) => unawaited(
                      safe(() => editPose({}, parts: {group: index})),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Widget actionPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('模型动作'),
      Wrap(
        spacing: 6,
        children: [
          for (final motion in controller.motions)
            action(
              motion,
              canPose
                  ? () => unawaited(
                      safe(
                        () =>
                            useAutomaticPose(command: 'motion', value: motion),
                      ),
                    )
                  : null,
              key: Key('motion-$motion'),
            ),
        ],
      ),
      if (controller.expressions.isNotEmpty) const Text('模型表情'),
      Wrap(
        spacing: 6,
        children: [
          for (final expression in controller.expressions)
            action(
              expression,
              canPose
                  ? () => unawaited(
                      safe(
                        () => useAutomaticPose(
                          command: 'expression',
                          value: expression,
                        ),
                      ),
                    )
                  : null,
            ),
        ],
      ),
      action(
        playing ? '停止音频' : '播放样例音频',
        canPose ? () => unawaited(safe(playAudio)) : null,
        key: const Key('audio'),
      ),
    ],
  );

  Widget framingSlider(
    String label,
    String command,
    double value,
    double min,
    double max,
  ) => Row(
    children: [
      Text(label),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          onChanged: ready
              ? (next) {
                  setState(() {
                    switch (command) {
                      case 'zoom':
                        zoom = next;
                      case 'x':
                        x = next;
                      case 'y':
                        y = next;
                    }
                  });
                  unawaited(
                    safe(
                      () => controller.command(command, number: next),
                      updateStatus: false,
                    ),
                  );
                }
              : null,
        ),
      ),
    ],
  );

  Widget framingPanel() => Column(
    children: [
      SwitchListTile(
        key: const Key('drag-follow'),
        title: const Text('拖动人物转头'),
        value: dragFollow,
        onChanged: (value) => setState(() => dragFollow = value),
      ),
      framingSlider('缩放', 'zoom', zoom, .4, 3),
      framingSlider('水平', 'x', x, -1, 1),
      framingSlider('垂直', 'y', y, -1, 1),
      Wrap(
        spacing: 6,
        children: [
          for (final name in ['Haru', 'Mark'])
            action(
              '加载 $name',
              ready && !_changingModel
                  ? () => unawaited(safe(() => loadModel(name)))
                  : null,
              key: Key('load-${name.toLowerCase()}'),
            ),
          action(
            '卸载',
            canPose
                ? () => unawaited(
                    safe(() async {
                      await stopAudio();
                      await controller.unload();
                    }),
                  )
                : null,
            key: const Key('unload'),
          ),
        ],
      ),
    ],
  );

  Widget controlsPanel() => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final tab in ['部位', '动作', '取景'])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                key: Key('panel-$tab'),
                label: Text(tab),
                selected: panel == tab,
                onSelected: (_) => setState(() => panel = tab),
              ),
            ),
          const SizedBox(width: 6),
          TextButton(
            key: const Key('pose-mode'),
            onPressed: canPose
                ? () => unawaited(
                    safe(() => manualPose ? useAutomaticPose() : editPose({})),
                  )
                : null,
            child: Text(manualPose ? '手动调姿' : '自动动作'),
          ),
        ],
      ),
      Expanded(
        child: SingleChildScrollView(
          key: ValueKey(panel),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: switch (panel) {
            '动作' => actionPanel(),
            '取景' => framingPanel(),
            _ => parameterPanel(),
          },
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: Text('Live2D · $model'),
        actions: [
          IconButton(
            key: const Key('pure-avatar'),
            tooltip: pureAvatar ? '显示测试聊天' : '纯人物',
            onPressed: () {
              FocusScope.of(context).unfocus();
              setState(() {
                pureAvatar = !pureAvatar;
                history = false;
              });
            },
            icon: Icon(
              pureAvatar ? Icons.chat_bubble_outline : Icons.person_outline,
            ),
          ),
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
              if (!pureAvatar)
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
                if (!pureAvatar)
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
                if (!pureAvatar && history)
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
            SafeArea(
              top: false,
              bottom: pureAvatar,
              child: SizedBox(
                height: (MediaQuery.sizeOf(context).height * .43).clamp(
                  160.0,
                  330.0,
                ),
                child: controlsPanel(),
              ),
            ),
          if (!pureAvatar)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
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
