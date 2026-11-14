import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

const videoActions = {'idle': '待机', 'wave': '挥手', 'weight_shift': '换重心'};

class AvatarVideoDemo extends StatefulWidget {
  const AvatarVideoDemo({super.key, this.useTestStorage = false});
  final bool useTestStorage;
  @override
  State<AvatarVideoDemo> createState() => AvatarVideoDemoState();
}

class AvatarVideoDemoState extends State<AvatarVideoDemo>
    with WidgetsBindingObserver {
  final players = <String, VideoPlayerController>{};
  String current = 'idle', status = '请导入真实动作视频。当前没有内置 AI 视频。';
  String? pending;
  bool busy = true, paused = false, foreground = true, switching = false;
  Directory? directory;
  VideoPlayerController? get active => players[current];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restore());
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    try {
      final root = await getApplicationDocumentsDirectory();
      final folder = widget.useTestStorage
          ? 'avatar_video_demo_test'
          : 'avatar_video_demo';
      directory = await Directory('${root.path}/$folder')
          .create(recursive: true);
      for (final id in videoActions.keys) {
        final file = File('${directory!.path}/$id.mp4');
        if (await file.exists()) {
          try {
            final player = await _prepare(file);
            if (!mounted) {
              await player.dispose();
              return;
            }
            players[id] = player;
          } catch (_) {
            status = '有视频无法恢复，请重新导入。';
          }
        }
      }
      if (!mounted) return;
      busy = false;
      if (players.containsKey('idle')) await switchTo('idle');
    } catch (e) {
      status = '初始化失败：$e';
    } finally {
      busy = false;
      refresh();
      _tick();
    }
  }

  Future<VideoPlayerController> _prepare(File file) async {
    final n = await file.length();
    if (n <= 0 || n > 64 * 1024 * 1024) {
      throw const FormatException('单段视频需为 1 字节至 64 MiB');
    }
    final player = VideoPlayerController.file(file);
    try {
      await player.initialize().timeout(const Duration(seconds: 20));
      if (player.value.duration <= Duration.zero ||
          player.value.duration > const Duration(seconds: 30)) {
        throw const FormatException('片段时长需大于 0 且不超过 30 秒');
      }
      await player.setVolume(0);
      await player.setLooping(false);
      return player;
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  Future<void> pick(String id) async {
    if (busy || switching || directory == null) return;
    busy = true;
    refresh();
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['mp4'],
      );
      if (file == null || !mounted) return;
      final length = await file.length();
      if (length == null || length <= 0 || length > 64 * 1024 * 1024) {
        throw const FormatException('请选择小于 64 MiB 的 MP4');
      }
      final staging = File('${directory!.path}/$id-pending.mp4');
      final sink = staging.openWrite();
      try {
        await sink.addStream(file.readAsByteStream());
      } finally {
        await sink.close();
      }
      await importFile(id, staging);
      if (await staging.exists()) await staging.delete();
    } catch (e) {
      status = '导入失败：$e';
    } finally {
      busy = false;
      refresh();
      _tick();
    }
  }

  /// Session demo import; not the proposed standardized ZIP contract.
  Future<void> importFile(String id, File source) async {
    if (!videoActions.containsKey(id) || directory == null) {
      throw const FormatException('未知动作');
    }
    final candidate = await _prepare(source);
    await candidate.dispose(); // Validate before replacing the persistent clip.
    if (!mounted) return;
    final wasActive = current == id;
    final target = File('${directory!.path}/$id.mp4');
    final backup = File('${directory!.path}/$id-backup.mp4');
    final hadPrevious = await target.exists();
    if (hadPrevious) await target.copy(backup.path);
    final previous = players.remove(id);
    previous?.removeListener(_tick);
    await previous?.dispose();
    VideoPlayerController replacement;
    try {
      await source.copy(target.path);
      replacement = await _prepare(target);
    } catch (_) {
      if (hadPrevious) {
        await backup.copy(target.path);
        final restored = await _prepare(target);
        if (mounted) {
          players[id] = restored;
          if (wasActive) await switchTo(id);
        } else {
          await restored.dispose();
        }
      }
      rethrow;
    } finally {
      if (await backup.exists()) await backup.delete();
    }
    if (!mounted) {
      await replacement.dispose();
      return;
    }
    players[id] = replacement;
    status = '已导入${videoActions[id]}；请检查动作和首尾衔接';
    if (wasActive || (active == null && id == 'idle')) await switchTo(id);
    refresh();
  }

  Future<void> switchTo(String id) async {
    final next = players[id];
    if (next == null || switching || !mounted) return;
    switching = true;
    try {
      active?.removeListener(_tick);
      await active?.pause();
      current = id;
      await next.seekTo(Duration.zero);
      next.addListener(_tick);
      if (!paused && foreground) await next.play();
      status = '播放：${videoActions[id]}';
    } catch (e) {
      status = '播放失败：$e';
      paused = true;
    } finally {
      switching = false;
      refresh();
    }
  }

  void requestAction(String id) {
    if (!players.containsKey(id) || busy || switching) return;
    if (active == null) {
      unawaited(switchTo(id));
      return;
    }
    pending = id;
    status = '已选择${videoActions[id]}，当前片段结束后切换';
    refresh();
  }

  void _tick() {
    final player = active;
    if (player == null ||
        switching ||
        busy ||
        paused ||
        !foreground ||
        !mounted) {
      return;
    }
    if (player.value.hasError) {
      paused = true;
      status = '视频解码失败，请重新导入';
      refresh();
      return;
    }
    if (player.value.isCompleted) {
      final next = pending ?? 'idle';
      pending = null;
      if (players.containsKey(next)) {
        unawaited(switchTo(next));
      } else {
        status = '片段结束，请导入待机视频';
        refresh();
      }
    }
  }

  Future<void> togglePause() async {
    if (switching || busy) return;
    paused = !paused;
    try {
      if (paused || !foreground) {
        await active?.pause();
      } else {
        await active?.play();
      }
    } catch (e) {
      status = '暂停恢复失败：$e';
    }
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    final player = active;
    if (player == null) return;
    unawaited(
      (foreground && !paused ? player.play() : player.pause()).catchError((
        Object e,
      ) {
        status = '后台恢复失败：$e';
        refresh();
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final player in players.values) {
      player.removeListener(_tick);
      unawaited(player.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('B · 视频动作播放器')),
    body: Column(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(status)),
        Expanded(
          child: Center(
            child: active == null
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '等待导入角色视频\n需要待机、挥手和腿部换重心三个片段。\n播放器可运行；AI 角色效果尚未验证。',
                      textAlign: TextAlign.center,
                    ),
                  )
                : AspectRatio(
                    aspectRatio: active!.value.aspectRatio,
                    child: VideoPlayer(active!),
                  ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('先导入 MP4，再触发动作。片段结束时切换，最新点击替换排队动作；衔接自然程度取决于素材。'),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in videoActions.entries)
              OutlinedButton(
                onPressed: busy || switching ? null : () => pick(entry.key),
                child: Text(
                  '${players.containsKey(entry.key) ? "替换" : "导入"}${entry.value}',
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in videoActions.entries)
              FilledButton(
                onPressed: busy || switching || !players.containsKey(entry.key)
                    ? null
                    : () => requestAction(entry.key),
                child: Text(entry.value),
              ),
            OutlinedButton(
              onPressed: active == null || busy || switching
                  ? null
                  : togglePause,
              child: Text(paused ? '继续' : '暂停'),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}
