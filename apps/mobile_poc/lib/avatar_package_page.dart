import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:live2d_avatar/live2d_avatar.dart';
import 'package:path_provider/path_provider.dart';

class AvatarPackageApp extends StatelessWidget {
  const AvatarPackageApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '星伴 · 人物包体验',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF7962BA)),
    home: const AvatarPackagePage(),
  );
}

class AvatarPackagePage extends StatefulWidget {
  const AvatarPackagePage({super.key});
  @override
  State<AvatarPackagePage> createState() => AvatarPackagePageState();
}

class AvatarPackagePageState extends State<AvatarPackagePage>
    with WidgetsBindingObserver {
  final controller = Live2dController();
  static const channel = Live2dController.channel;
  Map<String, dynamic>? package;
  List<dynamic> packages = [];
  bool busy = true, paused = false, foreground = true, polling = false;
  String playing = '', status = '正在初始化体验器…';
  Timer? timer;
  Map<String, dynamic> get manifest => package?['manifest'] ?? {};
  Map<String, dynamic> get actions => manifest['actions'] ?? {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(initialize());
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  String explain(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : '$e';

  Future<void> initialize() async {
    try {
      await controller.create();
      final value = await channel.invokeMethod<String>('packageRestore');
      if (value != null) package = jsonDecode(value) as Map<String, dynamic>;
      status = package == null ? '导入一个 v0.1 人物 ZIP，开始体验' : '已恢复本地人物包';
      await listPackages();
      timer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => unawaited(poll()),
      );
    } catch (e) {
      status = explain(e);
    } finally {
      busy = false;
      refresh();
    }
  }

  Future<void> listPackages() async {
    packages = jsonDecode((await channel.invokeMethod<String>('packageList'))!);
  }

  Future<void> poll() async {
    if (!mounted || busy || polling || !foreground) return;
    polling = true;
    try {
      final stats = await controller.stats();
      final wasPlaying = playing.isNotEmpty;
      playing = stats['playingMotion'] as String;
      if (wasPlaying && playing.isEmpty && status.startsWith('正在')) {
        status = '动作已完成 · 自然待机';
      }
      if (stats['error'] != null) status = '渲染失败：${stats['error']}';
      refresh();
    } catch (e) {
      status = explain(e);
      refresh();
    } finally {
      polling = false;
    }
  }

  /// Both the document picker and device acceptance tests use this same importer.
  Future<void> importFile(File file) async {
    busy = true;
    status = '正在校验 ZIP、资源引用与 SDK 兼容性…';
    refresh();
    try {
      final value = await channel.invokeMethod<String>('packageImport', {
        'path': file.path,
      });
      package = jsonDecode(value!) as Map<String, dynamic>;
      playing = '';
      paused = false;
      await controller.setActive(foreground);
      await listPackages();
      status = '结构与 SDK 校验通过 · 请观察动作效果';
    } catch (e) {
      status = explain(e);
      rethrow;
    } finally {
      busy = false;
      refresh();
    }
  }

  Future<void> pick() async {
    if (busy) return;
    busy = true;
    refresh();
    File? temporary;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (file == null || !mounted) return;
      final length = await file.length();
      if (length != null && (length <= 0 || length > 64 * 1024 * 1024)) {
        throw const FormatException('ZIP 必须小于 64 MiB');
      }
      temporary = File(
        '${(await getTemporaryDirectory()).path}/avatar-import.zip',
      );
      final out = await temporary.open(mode: FileMode.write);
      try {
        var count = 0;
        await for (final chunk in file.readAsByteStream()) {
          count += chunk.length;
          if (count > 64 * 1024 * 1024) {
            throw const FormatException('ZIP 实际大小超过 64 MiB');
          }
          await out.writeFrom(chunk);
        }
      } finally {
        await out.close();
      }
      await importFile(temporary);
    } catch (e) {
      status = explain(e);
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      busy = false;
      refresh();
    }
  }

  Future<void> openPackage(String key) async {
    busy = true;
    refresh();
    try {
      package = jsonDecode(
        (await channel.invokeMethod<String>('packageOpen', {'key': key}))!,
      );
      playing = '';
      paused = false;
      await controller.setActive(foreground);
      status = '已切换到本地人物包';
    } catch (e) {
      status = explain(e);
      rethrow;
    } finally {
      busy = false;
      refresh();
    }
  }

  Future<void> play(String id) async {
    await channel.invokeMethod<void>('packageAction', {'id': id});
    final a = actions[id];
    playing = '${a['group']}:${a['index']}';
    status = '正在${a['label']}，完成后自动待机';
    refresh();
  }

  Future<void> togglePause() async {
    paused = !paused;
    await controller.setActive(foreground && !paused);
    refresh();
  }

  Future<void> reset() async {
    await controller.command('reset');
    paused = false;
    playing = '';
    await controller.setActive(foreground);
    status = '已重置，回到自然待机';
    refresh();
  }

  Future<void> safely(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      status = explain(e);
      refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (controller.textureId != null) {
      unawaited(safely(() => controller.setActive(foreground && !paused)));
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = package != null && !busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('人物包体验'),
        actions: [
          TextButton.icon(
            key: const Key('import-zip'),
            onPressed: busy ? null : pick,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('导入 ZIP'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (packages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: package?['key'],
                  hint: const Text('选择已导入人物'),
                  items: [
                    for (final p in packages)
                      DropdownMenuItem(
                        value: p['key'] as String,
                        child: Text(
                          '${p['name']} · ${p['version']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (key) {
                          if (key != null) {
                            unawaited(safely(() => openPackage(key)));
                          }
                        },
                ),
              ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF4EFFF), Color(0xFFE3F0F7)],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(child: Live2dView(controller: controller)),
                    if (package == null && !busy)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          '把制作方交付的 ZIP 导入这里\n\n校验通过后，即可体验完整预设动作',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (busy) const CircularProgressIndicator(),
                    if (package != null)
                      Positioned(
                        top: 12,
                        left: 16,
                        child: Chip(
                          label: Text(
                            paused
                                ? '已暂停'
                                : playing.isEmpty
                                ? '自然待机'
                                : '动作播放中',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                status,
                key: const Key('package-status'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final entry in actions.entries)
                    if (entry.key != 'idle')
                      FilledButton.tonal(
                        key: Key('action-${entry.key}'),
                        onPressed: enabled && !paused && playing.isEmpty
                            ? () => safely(() => play(entry.key))
                            : null,
                        child: Text(entry.value['label'] as String),
                      ),
                  for (final entry
                      in ((manifest['expressions'] ?? {}) as Map).entries)
                    OutlinedButton(
                      onPressed: enabled && !paused && playing.isEmpty
                          ? () => safely(
                              () => channel.invokeMethod<void>(
                                'packageExpression',
                                {'id': entry.key},
                              ),
                            )
                          : null,
                      child: Text(entry.value['label'] as String),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  key: const Key('pause'),
                  onPressed: enabled ? () => safely(togglePause) : null,
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                  label: Text(paused ? '继续' : '暂停'),
                ),
                TextButton.icon(
                  key: const Key('reset'),
                  onPressed: enabled ? () => safely(reset) : null,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重置'),
                ),
                TextButton(
                  onPressed: package == null
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('人物包信息'),
                            content: SingleChildScrollView(
                              child: SelectableText(
                                '${manifest['id']} · ${manifest['version']}\nv${manifest['formatVersion']} / ${manifest['runtimeProfile']}\n\n结构：通过\nSDK：通过\n画面：请人工验收\n\nZIP SHA-256\n${package!['sha256']}',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        ),
                  child: const Text('包信息'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
