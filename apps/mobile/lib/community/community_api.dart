import 'dart:convert';
import 'dart:io';

import '../immersive/conversation_transport.dart';

typedef Json = Map<String, dynamic>;

class CommunityError implements Exception {
  CommunityError(this.code, [this.cause]);
  final String code;
  final Object? cause;
  @override
  String toString() => switch (code) {
    'INVALID_CREDENTIALS' => '用户名或密码不正确。',
    'USERNAME_TAKEN' => '该用户名已被使用。',
    'INVALID_USERNAME' => '用户名可使用汉字、字母、数字、下划线、点和短横线。',
    'LOGIN_REQUIRED' => '登录已过期，请重新登录。',
    'POST_NOT_FOUND' => '帖子已删除或分享已撤回。',
    'TRY_LATER' => '操作过于频繁，请稍后再试。',
    'INVALID_REQUEST' => '请检查填写的内容和长度。',
    'INVALID_LINK' => '请使用本社区的角色分享链接。',
    'SERVER_REQUIRED' => '请先连接社区服务。',
    'INVALID_SERVER' => '请输入 HTTPS 服务地址，本机开发可用回环地址。',
    'NETWORK' => '无法连接社区，请检查网络后重试。',
    _ => '操作未完成（$code）。',
  };
}

class CommunityApi {
  CommunityApi(this.origin, {this.token, this.owner, this.username});
  final Uri? origin;
  final String? token, owner, username;
  bool get signedIn => token != null;
  static Uri parseOrigin(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !(uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                [
                  'localhost',
                  '127.0.0.1',
                  '10.0.2.2',
                  '::1',
                ].contains(uri.host)))) {
      throw CommunityError('INVALID_SERVER');
    }
    return Uri.parse(uri.origin);
  }

  String shareId(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri != null &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.userInfo.isEmpty) {
      final parts = uri.pathSegments;
      final app =
          uri.scheme == 'erciyuan' &&
          uri.host == 'share' &&
          !uri.hasPort &&
          parts.length == 1;
      final web =
          ['https', 'http'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          origin != null &&
          uri.origin == origin!.origin &&
          parts.length == 2 &&
          parts.first == 's';
      if ((app || web) && RegExp(r'^[a-f0-9]{32}$').hasMatch(parts.last)) {
        return parts.last;
      }
    }
    throw CommunityError('INVALID_LINK');
  }

  Future<Json> request(String method, String path, [Json? data]) async {
    if (origin == null) throw CommunityError('SERVER_REQUIRED');
    final client = HttpClient(context: ConversationTransport.localTrust())
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.openUrl(method, origin!.resolve(path));
      req.followRedirects = false;
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (data != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(data));
      }
      final res = await req.close().timeout(const Duration(seconds: 12));
      final raw = await utf8.decoder
          .bind(res)
          .join()
          .timeout(const Duration(seconds: 12));
      final output = jsonDecode(raw) as Json;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw CommunityError(
          output['error']?['code'] as String? ?? 'HTTP_${res.statusCode}',
        );
      }
      return output;
    } on CommunityError {
      rethrow;
    } catch (error) {
      throw CommunityError('NETWORK', error);
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Json>> items(String path) async =>
      ((await request('GET', path))['items'] as List).cast<Json>();
}

String localRole(String id) => switch (id) {
  'xing' => 'star',
  'yue' => 'moon',
  _ => id,
};
