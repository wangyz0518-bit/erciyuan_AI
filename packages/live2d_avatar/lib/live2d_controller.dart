import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Live2dParameter {
  const Live2dParameter(this.id, this.min, this.max, this.defaultValue);

  final String id;
  final double min, max, defaultValue;
}

class Live2dController extends ChangeNotifier {
  static const channel = MethodChannel('erciyuan/live2d');
  int? textureId;
  List<String> expressions = [], motions = [], lipSyncParameters = [];
  Map<String, Live2dParameter> parameters = const {};
  List<List<String>> poseParts = const [];
  bool get supportsLipSync => lipSyncParameters.isNotEmpty;
  String? error;
  bool loaded = false, busy = false, _closed = false;
  int _generation = 0;
  Future<void> create() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('本轮仅实现 Android；iOS 尚未接入');
    }
    textureId = await channel.invokeMethod<int>('create');
    if (!_closed) notifyListeners();
  }

  Future<void> load(String asset) async {
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('load', {
        'asset': asset,
      });
      if (_closed || generation != _generation) return;
      expressions = List<String>.from(result!['expressions'] as List);
      motions = List<String>.from(result['motions'] as List);
      lipSyncParameters = List<String>.from(
        result['lipSyncParameters'] as List,
      );
      parameters = {
        for (final entry in (result['parameters'] as Map).entries)
          entry.key as String: Live2dParameter(
            entry.key as String,
            (entry.value['min'] as num).toDouble(),
            (entry.value['max'] as num).toDouble(),
            (entry.value['default'] as num).toDouble(),
          ),
      };
      poseParts = (result['poseParts'] as List)
          .map((group) => List<String>.from(group as List))
          .toList();
      loaded = true;
    } catch (e) {
      if (!_closed && generation == _generation) error = e.toString();
      rethrow;
    } finally {
      if (!_closed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> unload() async {
    ++_generation;
    await channel.invokeMethod<void>('unload');
    if (_closed) return;
    loaded = false;
    busy = false;
    expressions = [];
    motions = [];
    lipSyncParameters = [];
    parameters = const {};
    poseParts = const [];
    notifyListeners();
  }

  Future<void> command(String action, {String value = '', double number = 0}) =>
      channel.invokeMethod<void>('command', {
        'action': action,
        'value': value,
        'number': number,
      });
  Future<void> setActive(bool value) =>
      channel.invokeMethod<void>('active', {'value': value});

  /// Applies changes together and returns the current native pose.
  Future<Map<String, dynamic>> setPose(
    Map<String, double> values, {
    Map<int, int> parts = const {},
  }) async => (await channel.invokeMapMethod<String, dynamic>('pose', {
    'values': values,
    'parts': parts,
  }))!;

  Future<Map<String, dynamic>> stats() async =>
      (await channel.invokeMapMethod<String, dynamic>('stats'))!;

  /// Await this before creating another controller. The base dispose stays synchronous.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_generation;
    await channel.invokeMethod<void>('dispose');
    textureId = null;
    super.dispose();
  }
}
