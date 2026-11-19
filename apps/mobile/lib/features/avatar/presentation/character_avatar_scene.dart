import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../characters/domain/character.dart';
import 'avatar_fallback_scene.dart';

/// A single native texture is shared by successive pages. Order operations
/// across route transitions so teardown of the old role cannot stop a new one.
class CharacterAvatarScene extends StatefulWidget {
  const CharacterAvatarScene({
    super.key,
    required this.character,
    required this.motion,
    required this.mouth,
  });
  final Character character;
  final AvatarSceneMotion motion;
  final double mouth;
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
    if (Platform.isAndroid) unawaited(_attach());
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
        'value': _current && _foreground && _model != null,
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
    if (_model == null || !_foreground) return;
    final motion = widget.motion, amount = widget.mouth;
    unawaited(
      _queue(() async {
        if (!_current || _owner != this || _model == null || !_foreground) {
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
    await _setActive();
    if (_current) setState(() {});
  });

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
        child: _model != null && _texture != null
            ? Semantics(
                label: '${widget.character.name} · $_model',
                child: AspectRatio(
                  aspectRatio: 720 / 1280,
                  child: Texture(textureId: _texture!),
                ),
              )
            : AvatarFallbackScene(
                characterId: widget.character.scope.characterId,
                characterName: widget.character.name,
                motion: widget.motion,
                mouth: widget.mouth,
              ),
      ),
      if (_available)
        Positioned(
          right: 6,
          top: 0,
          child: PopupMenuButton<String>(
            tooltip: '人物形象',
            enabled: !_busy,
            onSelected: (action) => unawaited(_select(action)),
            icon: const Icon(
              Icons.face_retouching_natural,
              color: Colors.white,
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'import',
                child: Text('为此人物导入 Live2D ZIP'),
              ),
              if (_model != null)
                const PopupMenuItem(value: 'clear', child: Text('恢复内置形象')),
            ],
          ),
        ),
    ],
  );
}
