import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

export 'dart:io' show HttpHeaders, SocketException;

class WebSocket extends StreamView<dynamic> {
  WebSocket._(this._channel) : super(_channel.stream);
  final WebSocketChannel _channel;
  static Future<WebSocket> connect(
    String address, {
    required Map<String, String> headers,
  }) async {
    final token = headers.values.single.substring('Bearer '.length);
    final channel = WebSocketChannel.connect(
      Uri.parse(address),
      protocols: ['companion.$token'],
    );
    await channel.ready;
    return WebSocket._(channel);
  }

  void add(Object message) => _channel.sink.add(message);
  Future<void> close() async => _channel.sink.close();
}
