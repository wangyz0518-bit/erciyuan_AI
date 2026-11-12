import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Live2dController extends ChangeNotifier {
  static const channel = MethodChannel('erciyuan/live2d');
  int? textureId;
  List<String> expressions = [], motions = [], lipSyncParameters = [];
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
