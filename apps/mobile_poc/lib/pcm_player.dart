import 'dart:async';

import 'package:flutter/services.dart';

class PcmPlayer {
  static const channel = MethodChannel('dev.erciyuan/pcm');
  void Function(Map<String, Object?>)? onEvent;
  String? active;
  PcmPlayer() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'event') {
        final value = Map<String, Object?>.from(call.arguments as Map);
        if (value['id'] == active) onEvent?.call(value);
      }
    });
  }
  Future<void> start(
    String id, {
    int bufferMs = 400,
    bool communication = false,
  }) async {
    active = id;
    await channel.invokeMethod<void>('start', {
      'id': id,
      'bufferMs': bufferMs,
      'communication': communication,
    });
  }

  Future<void> append(String id, Uint8List bytes) async {
    if (active != id) return;
    await channel.invokeMethod<void>('append', {'id': id, 'bytes': bytes});
  }

  Future<Map<String, Object?>> end(String id) async {
    if (active != id) return {};
    final result = await channel.invokeMapMethod<String, Object?>('end', {
      'id': id,
    });
    return result ?? {};
  }

  Future<int> progress(String id) async {
    if (active != id) return 0;
    return await channel.invokeMethod<int>('progress', {'id': id}) ?? 0;
  }

  Future<void> stop() async {
    active = null;
    try {
      await channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      /* non-Android */
    }
  }
}
