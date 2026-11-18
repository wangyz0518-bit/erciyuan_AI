import 'dart:convert';

import 'package:erciyuan_mobile/features/avatar/domain/avatar_manifest_preflight.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> example() => {
  'format': 'erciyuan-avatar',
  'formatVersion': '0.1',
  'id': 'dragon-demo',
  'version': '1.0.0',
  'name': '白发龙角',
  'renderer': 'live2d-cubism',
  'runtimeProfile': 'native-r5-basic-v1',
  'entry': 'model/character.model3.json',
  'preview': 'preview.png',
  'actions': {
    'idle': {'label': '待机', 'group': 'Idle', 'index': 0, 'playback': 'loop'},
    'wave': {'label': '挥手', 'group': 'Actions', 'index': 0, 'playback': 'once', 'returnTo': 'idle'},
    'weight_shift': {'label': '换重心', 'group': 'Actions', 'index': 1, 'playback': 'once', 'returnTo': 'idle'},
  },
};

void main() {
  test('accepts valid v0.1 metadata, not a runnable model', () {
    expect(
      AvatarManifestPreflight.inspect(jsonEncode(example()))['id'],
      'dragon-demo',
    );
  });

  test('rejects paths escaping ZIP root and missing local resources', () {
    for (final invalid in [
      '../secret.model3.json',
      '/abs.model3.json',
      'https://example.org/model.model3.json',
      'model\\part.model3.json',
      'model//part.model3.json',
      'model/../part.model3.json',
    ]) {
      final doc = example()..['entry'] = invalid;
      expect(
        () => AvatarManifestPreflight.inspect(jsonEncode(doc)),
        throwsFormatException,
      );
    }
  });

  test('rejects unsupported version and unexpected fields', () {
    final old = example()..['formatVersion'] = '0.0';
    final extra = example()..['url'] = 'http://external.example';
    expect(
      () => AvatarManifestPreflight.inspect(jsonEncode(old)),
      throwsFormatException,
    );
    expect(
      () => AvatarManifestPreflight.inspect(jsonEncode(extra)),
      throwsFormatException,
    );
  });

  test('rejects invalid/missing motions and oversized manifest', () {
    final missing = example();
    (missing['actions'] as Map<String, Object?>).remove('wave');
    final same = example();
    final actions = same['actions'] as Map<String, Object?>;
    (actions['weight_shift'] as Map<String, Object?>)['index'] = 0;
    for (final invalid in [missing, same]) {
      expect(
        () => AvatarManifestPreflight.inspect(jsonEncode(invalid)),
        throwsFormatException,
      );
    }
    expect(
      () => AvatarManifestPreflight.inspect(' ' * 1048577),
      throwsFormatException,
    );
  });

  test('rejects duplicate expression targets and malformed JSON', () {
    final invalid = example();
    invalid['expressions'] = {
      'happy': {'label': '开心', 'name': 'Joy'},
      'calm': {'label': '平静', 'name': 'Joy'},
    };
    expect(
      () => AvatarManifestPreflight.inspect(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect(
      () => AvatarManifestPreflight.inspect('{'),
      throwsFormatException,
    );
  });
}
