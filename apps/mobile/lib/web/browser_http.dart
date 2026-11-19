// Fetch transport for the same SSE and PCM readers used by the mobile app.
import 'dart:async';

import 'package:http/http.dart' as http;

export 'dart:io' show HttpHeaders, HttpStatus, SocketException;

typedef HttpException = http.ClientException;

class ContentType {
  const ContentType(this.mimeType);
  final String mimeType;
  static const json = ContentType('application/json');
}

class BrowserHeaders {
  BrowserHeaders([Map<String, String>? initial]) : values = initial ?? {};
  final Map<String, String> values;
  void set(String name, String value) => values[name.toLowerCase()] = value;
  String? value(String name) => values[name.toLowerCase()];
  set contentType(ContentType type) => set('content-type', type.mimeType);
  ContentType? get contentType {
    final value = values['content-type'];
    return value == null ? null : ContentType(value.split(';').first.trim());
  }
}

class HttpClient {
  final _client = http.Client();
  Duration? connectionTimeout;
  Future<HttpClientRequest> postUrl(Uri uri) async =>
      HttpClientRequest(_client, 'POST', uri);
  Future<HttpClientRequest> getUrl(Uri uri) async =>
      HttpClientRequest(_client, 'GET', uri);
  void close({bool force = false}) => _client.close();
}

class HttpClientRequest {
  HttpClientRequest(this._client, this._method, this._uri);
  final http.Client _client;
  final String _method;
  final Uri _uri;
  String _body = '';
  final _cancel = Completer<void>();
  final headers = BrowserHeaders();
  bool followRedirects = false;
  void write(String body) => _body = body;
  void abort() {
    if (!_cancel.isCompleted) _cancel.complete();
  }

  Future<HttpClientResponse> close() async {
    final outgoing = http.AbortableRequest(
      _method,
      _uri,
      abortTrigger: _cancel.future,
    )..followRedirects = followRedirects;
    if (_body.isNotEmpty) outgoing.body = _body;
    outgoing.headers.addAll(headers.values);
    return HttpClientResponse(await _client.send(outgoing));
  }
}

class HttpClientResponse extends StreamView<List<int>> {
  HttpClientResponse(http.StreamedResponse response)
    : statusCode = response.statusCode,
      headers = BrowserHeaders(response.headers),
      super(response.stream);
  final int statusCode;
  final BrowserHeaders headers;
}
