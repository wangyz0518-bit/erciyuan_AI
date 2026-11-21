import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../characters/domain/character.dart';
import 'avatar_fallback_scene.dart';
import 'dragon_avatar_scene.dart';

/// A single native texture is shared by successive pages. Order operations
/// across route transitions so teardown of the old role cannot stop a new one.
class CharacterAvatarScene extends StatefulWidget {
  const CharacterAvatarScene({
    super.key,
    required this.character,
    required this.motion,
    required this.mouth,
    this.fallback,
    this.showMenu = true,
    this.dragonImmersive = false,
    this.dragonWideShot = false,
  });
  final Character character;
  final AvatarSceneMotion motion;
  final double mouth;
  final Widget? fallback;
  final bool showMenu;
  final bool dragonImmersive;
  final bool dragonWideShot;
  @override
  State<CharacterAvatarScene> createState() => CharacterAvatarSceneState();
}

class CharacterAvatarSceneState extends State<CharacterAvatarScene>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('erciyuan/live2d');
  static Future<void> _tail = Future.value();
  static CharacterAvatarSceneState? _owner;
  static CharacterAvatarSceneState? _visible;
  int? _texture;
  bool _available = false, _busy = false, _foreground = true;
  bool _appearanceReady = false, _savingAppearance = false, _previewing = false;
  bool? _dragonChoice;
  String? _model;
  String get _binding => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            widget.character.scope.ownerId,
            widget.character.scope.characterId,
          ]),
        ),
      )
      .toString();
  bool get _current => mounted && _visible == this;
  bool get supportsDragon =>
      !kIsWeb &&
      Platform.isAndroid &&
      widget.character.scope.characterId == 'star';
  bool get showsDragon =>
      supportsDragon && _appearanceReady && (_dragonChoice ?? (_model == null));
  bool get canChooseAppearance =>
      supportsDragon && _appearanceReady && !_savingAppearance;

  Future<void> _queue(Future<void> Function() fn) {
    final next = _tail.then((_) => fn());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  void initState() {
    super.initState();
    _visible = this;
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && Platform.isAndroid) unawaited(_attach());
    if (supportsDragon) unawaited(_restoreAppearance());
  }

  Future<File> _appearanceFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/dragon-avatar-$_binding.txt');
  }

  Future<void> _restoreAppearance() async {
    bool? choice;
    try {
      final file = await _appearanceFile();
      if (await file.exists()) {
        choice = switch ((await file.readAsString()).trim()) {
          'dragon' => true,
          'original' => false,
          _ => null,
        };
      }
    } catch (error) {
      debugPrint('Could not load the avatar appearance: $error');
    }
    if (!_current) return;
    setState(() {
      _dragonChoice = choice;
      _appearanceReady = true;
    });
    unawaited(_queue(_setActive).catchError((Object _) {}));
  }

  Future<void> chooseDragonAppearance(bool enabled) async {
    if (!_current || !canChooseAppearance) return;
    setState(() => _savingAppearance = true);
    File? staged;
    try {
      final file = await _appearanceFile();
      staged = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await staged.writeAsString(enabled ? 'dragon' : 'original', flush: true);
      await staged.rename(file.path);
      staged = null;
      if (!_current) return;
      setState(() => _dragonChoice = enabled);
      unawaited(_queue(_setActive).catchError((Object _) {}));
    } catch (error) {
      debugPrint('Could not save the avatar appearance: $error');
      if (mounted && _current) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存人物外观失败，请重试')));
      }
    } finally {
      if (staged != null) {
        try {
          if (await staged.exists()) await staged.delete();
        } catch (error) {
          debugPrint('Could not remove temporary appearance setting: $error');
        }
      }
      if (mounted) setState(() => _savingAppearance = false);
    }
  }

  Future<void> previewDragon() async {
    if (!_current || !supportsDragon || _previewing) return;
    setState(() => _previewing = true);
    try {
      await showDragonAvatarPreview(context);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _attach() => _queue(() async {
    if (!_current) return;
    try {
      if (await _channel.invokeMethod<bool>('available') != true || !_current) {
        return;
      }
      if (_owner != null) {
        _owner = null;
        await _channel.invokeMethod<void>('dispose');
      }
      if (!_current) return;
      _texture = await _channel.invokeMethod<int>('create');
      _owner = this;
      if (!_current) return;
      _available = true;
      _applyPackage(
        await _channel.invokeMethod<String>('packageRestore', {
          'binding': _binding,
        }),
      );
      await _setActive();
    } on MissingPluginException {
      // Default builds and other platforms use the Flutter character.
    } on PlatformException {
      _model = null;
    } finally {
      if (_current) setState(() {});
    }
  });

  void _applyPackage(String? raw) {
    _model = raw == null
        ? null
        : (jsonDecode(raw)['manifest']['name'] as String);
  }

  Future<void> _setActive() async {
    if (_owner == this) {
      await _channel.invokeMethod<void>('active', {
        'value': _current && _foreground && _model != null && !showsDragon,
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(_queue(_setActive).catchError((Object _) {}));
  }

  @override
  void didUpdateWidget(CharacterAvatarScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion == widget.motion && oldWidget.mouth == widget.mouth) {
      return;
    }
    if (_model == null || !_foreground || showsDragon) return;
    final motion = widget.motion, amount = widget.mouth;
    unawaited(
      _queue(() async {
        if (!_current ||
            _owner != this ||
            _model == null ||
            !_foreground ||
            showsDragon) {
          return;
        }
        await _channel.invokeMethod<void>('packageMouth', {
          'amount': motion == AvatarSceneMotion.talking ? amount : 0.0,
        });
        if (oldWidget.motion != motion &&
            (motion == AvatarSceneMotion.listening ||
                motion == AvatarSceneMotion.thinking)) {
          await _channel.invokeMethod<void>('packageAction', {
            'id': motion == AvatarSceneMotion.listening
                ? 'wave'
                : 'weight_shift',
          });
        }
      }).catchError((Object _) {}),
    ); // A one-shot motion may already be playing.
  }

  Future<void> importFile(File source) => _queue(() async {
    if (!_current || !_available || _owner != this) return;
    final package = await _channel.invokeMethod<String>('packageImport', {
      'binding': _binding,
      'path': source.path,
    });
    if (!_current) return;
    _applyPackage(package);
    if (showsDragon) await chooseDragonAppearance(false);
    await _setActive();
    if (_current) setState(() {});
  });

  bool get canImport => _available && !_busy;
  bool get hasModel => _model != null;
  Future<void> choosePackage() => _select('import');
  Future<void> clearPackage() => _select('clear');

  Future<void> _select(String action) async {
    if (_busy || !_current) return;
    setState(() => _busy = true);
    Directory? staging;
    try {
      if (action == 'clear') {
        await _queue(() async {
          if (!_current || _owner != this) return;
          await _channel.invokeMethod<void>('packageClear', {
            'binding': _binding,
          });
          _model = null;
          await _setActive();
        });
        return;
      }
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (picked == null || !_current) return;
      final length = await picked.length();
      if (length != null && (length <= 0 || length > 64 * 1024 * 1024)) {
        throw const FormatException('人物包超过大小限制');
      }
      staging = await (await getTemporaryDirectory()).createTemp(
        'character-avatar-',
      );
      final file = File('${staging.path}/input.zip');
      final sink = await file.open(mode: FileMode.write);
      try {
        var total = 0;
        await for (final chunk in picked.readAsByteStream()) {
          if (!_current) return;
          total += chunk.length;
          if (total > 64 * 1024 * 1024) {
            throw const FormatException('人物包超过大小限制');
          }
          await sink.writeFrom(chunk);
        }
      } finally {
        await sink.close();
      }
      await importFile(file);
    } catch (error) {
      if (mounted && _current) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '人物包操作失败：${error is PlatformException ? error.message : error}',
            ),
          ),
        );
      }
    } finally {
      if (staging != null) await staging.delete(recursive: true);
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_visible == this) _visible = null;
    unawaited(
      _queue(() async {
        if (_owner != this) return;
        _owner = null;
        await _channel.invokeMethod<void>('dispose');
      }).catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Center(
        child: showsDragon
            ? DragonAvatarScene(
                clip: DragonAvatarClip.forMotion(widget.motion),
                active: _current && _foreground && !_previewing,
                immersive: widget.dragonImmersive,
                wideShot: widget.dragonWideShot,
              )
            : _model != null && _texture != null
            ? Semantics(
                label: '${widget.character.name} · $_model',
                child: AspectRatio(
                  aspectRatio: 720 / 1280,
                  child: Texture(textureId: _texture!),
                ),
              )
            : widget.fallback ??
                  AvatarFallbackScene(
                    characterId: widget.character.scope.characterId,
                    characterName: widget.character.name,
                    motion: widget.motion,
                    mouth: widget.mouth,
                  ),
      ),
      if ((_available || supportsDragon) && widget.showMenu)
        Positioned(
          right: 6,
          top: 0,
          child: PopupMenuButton<String>(
            tooltip: '人物形象',
            enabled: !_busy && !_savingAppearance,
            onSelected: (action) {
              switch (action) {
                case 'dragon':
                  unawaited(chooseDragonAppearance(true));
                case 'original':
                  unawaited(chooseDragonAppearance(false));
                case 'preview-dragon':
                  unawaited(previewDragon());
                default:
                  unawaited(_select(action));
              }
            },
            icon: const Icon(
              Icons.face_retouching_natural,
              color: Colors.white,
            ),
            itemBuilder: (_) => [
              if (canChooseAppearance)
                PopupMenuItem(
                  value: showsDragon ? 'original' : 'dragon',
                  child: Text(showsDragon ? '切回原形象' : '使用龙角形象'),
                ),
              if (supportsDragon)
                const PopupMenuItem(
                  value: 'preview-dragon',
                  child: Text('龙角动作预览'),
                ),
              if (_available)
                const PopupMenuItem(
                  value: 'import',
                  child: Text('为此人物导入 Live2D ZIP'),
                ),
              if (_model != null && !showsDragon)
                const PopupMenuItem(value: 'clear', child: Text('恢复内置形象')),
            ],
          ),
        ),
    ],
  );
}
