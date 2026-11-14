import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:live2d_avatar/live2d_avatar.dart';

class AvatarLive2dDemo extends StatefulWidget {
  const AvatarLive2dDemo({super.key});
  @override
  State<AvatarLive2dDemo> createState() => AvatarLive2dDemoState();
}

class AvatarLive2dDemoState extends State<AvatarLive2dDemo>
    with WidgetsBindingObserver {
  final controller = Live2dController();
  String model = 'Mark', status = '正在加载模型…';
  bool busy = true, paused = false, foreground = true, leaving = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await controller.create();
      if (!mounted) {
        await controller.close();
        return;
      }
      await controller.load('assets/live2d/$model/$model.model3.json');
      await controller.setActive(foreground && !paused);
      if (mounted) {
        setState(() {
          busy = false;
          status = '官方 $model · 自动待机';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          status = '加载失败：$e';
        });
      }
    }
  }

  Future<void> perform(Future<void> Function() action, String message) async {
    if (busy || leaving) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) setState(() => status = message);
    } catch (e) {
      if (mounted) setState(() => status = '操作失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changeModel(String value) => perform(() async {
    await controller.load('assets/live2d/$value/$value.model3.json');
    model = value;
    await controller.setActive(foreground && !paused);
  }, '官方 $value · 自动待机');
  Future<void> playMotion(String id) => perform(
    () => controller.command('motion', value: id),
    '样例动作 $id；完成后自动待机',
  );
  Future<void> leave() async {
    if (leaving || busy) return;
    setState(() => leaving = true);
    await controller.close();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (controller.textureId != null && !leaving) {
      unawaited(
        controller.setActive(foreground && !paused).catchError((Object e) {
          if (mounted) setState(() => status = '暂停恢复失败：$e');
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(leave());
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('A · Live2D 预设动作')),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(status)),
          Expanded(
            child: ColoredBox(
              color: const Color(0xffeeebf7),
              child: Live2dView(controller: controller),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('官方样例技术演示。动作名称按原始资源显示，尚未验收为挥手或换重心；不代表当前龙角角色效果。'),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final name in ['Mark', 'Haru'])
                OutlinedButton(
                  onPressed: busy ? null : () => changeModel(name),
                  child: Text(name),
                ),
              OutlinedButton(
                onPressed: busy || !controller.loaded
                    ? null
                    : () => perform(() async {
                        paused = !paused;
                        await controller.setActive(foreground && !paused);
                      }, paused ? '继续播放' : '已暂停'),
                child: Text(paused ? '继续' : '暂停'),
              ),
            ],
          ),
          SizedBox(
            height: 100,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                children: [
                  for (final id in controller.motions)
                    ActionChip(
                      label: Text(id),
                      onPressed: busy || paused ? null : () => playMotion(id),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
