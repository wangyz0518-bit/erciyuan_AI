import 'dart:convert';

/// Only metadata validation, NOT an installer, SDK compatibility check or
/// actual Live2D renderer. The ZIP importer must still validate duplicates,
/// CRC, symlinks, size limits and the native Cubism model.
final class AvatarManifestPreflight {
  const AvatarManifestPreflight._();

  static final _packageId = RegExp(r'^[a-z][a-z0-9_-]{2,63}$');
  static final _version = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$');
  static final _actionId = RegExp(r'^[a-z][a-z0-9_]*$');
  static final _segment = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.-]*$');
  static const _manifestKeys = {
    'format',
    'formatVersion',
    'id',
    'version',
    'name',
    'renderer',
    'runtimeProfile',
    'entry',
    'preview',
    'actions',
    'expressions',
  };

  static bool _path(String value) =>
      value.isNotEmpty &&
      value.length <= 255 &&
      !value.contains('..') &&
      !value.contains(':') &&
      !value.contains('\\') &&
      value.split('/').every((part) => part != '.' && _segment.hasMatch(part));

  static Map<String, Object?> inspect(String source) {
    if (source.length > 1048576) {
      throw const FormatException('Manifest too large');
    }
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic> ||
        json.keys.toSet().difference(_manifestKeys).isNotEmpty ||
        json['format'] != 'erciyuan-avatar' ||
        json['formatVersion'] != '0.1' ||
        json['renderer'] != 'live2d-cubism' ||
        json['runtimeProfile'] != 'native-r5-basic-v1') {
      throw const FormatException('Unsupported v0.1 avatar manifest');
    }
    final id = json['id'];
    final version = json['version'];
    final name = json['name'];
    if (id is! String ||
        !_packageId.hasMatch(id) ||
        version is! String ||
        !_version.hasMatch(version) ||
        name is! String ||
        name.isEmpty ||
        name.runes.length > 64) {
      throw const FormatException('Invalid avatar identity');
    }
    final entry = json['entry'];
    final preview = json['preview'];
    if (entry is! String ||
        !_path(entry) ||
        !entry.endsWith('.model3.json') ||
        preview is! String ||
        !_path(preview) ||
        !preview.endsWith('.png')) {
      throw const FormatException('Invalid relative resource path');
    }

    final actions = json['actions'];
    if (actions is! Map<String, dynamic> ||
        actions.length < 3 ||
        actions.length > 24 ||
        !actions.keys.toSet().containsAll(const {
          'idle',
          'wave',
          'weight_shift',
        })) {
      throw const FormatException('Missing required avatar actions');
    }
    final targets = <String, String>{};
    for (final action in actions.entries) {
      final value = action.value;
      if (!_actionId.hasMatch(action.key) || value is! Map<String, dynamic>) {
        throw const FormatException('Invalid avatar action');
      }
      final allowed = action.key == 'idle'
          ? const {'label', 'group', 'index', 'playback'}
          : const {'label', 'group', 'index', 'playback', 'returnTo'};
      final label = value['label'];
      final group = value['group'];
      final index = value['index'];
      if (value.keys.toSet().difference(allowed).isNotEmpty ||
          !value.keys.toSet().containsAll(allowed) ||
          label is! String ||
          label.isEmpty ||
          group is! String ||
          group.isEmpty ||
          index is! int ||
          index < 0 ||
          index > 256) {
        throw const FormatException('Invalid avatar action fields');
      }
      if (action.key == 'idle') {
        if (group != 'Idle' || index != 0 || value['playback'] != 'loop') {
          throw const FormatException('Idle must loop');
        }
      } else if (group == 'Idle' ||
          value['playback'] != 'once' ||
          value['returnTo'] != 'idle') {
        throw const FormatException('Action must return to idle');
      }
      targets[action.key] = '$group/$index';
    }
    if (targets['wave'] == targets['weight_shift']) {
      throw const FormatException('Required actions must be distinct');
    }

    final expressions = json['expressions'] ?? <String, Object?>{};
    if (expressions is! Map<String, dynamic> || expressions.length > 16) {
      throw const FormatException('Too many expressions');
    }
    final names = <String>{};
    for (final expression in expressions.entries) {
      final data = expression.value;
      if (!_actionId.hasMatch(expression.key) ||
          data is! Map<String, dynamic> ||
          data.keys.toSet().difference(const {'name', 'label'}).isNotEmpty ||
          data['name'] is! String ||
          data['label'] is! String ||
          (data['label'] as String).isEmpty ||
          !names.add(data['name'] as String)) {
        throw const FormatException('Invalid or duplicate expression');
      }
    }
    return {
      'id': id,
      'version': version,
      'name': name,
      'entry': entry,
      'preview': preview,
      'actions': Map<String, String>.unmodifiable(targets),
    };
  }
}
