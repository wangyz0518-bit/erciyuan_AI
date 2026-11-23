import 'package:erciyuan_mobile/community/community_api.dart';
import 'package:erciyuan_mobile/community/community_forms.dart';
import 'package:erciyuan_mobile/main.dart' as app;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('COMMUNITY_GATEWAY_URL');
  testWidgets(
    'guest previews a shared role, registers, imports, chats and comments',
    (tester) async {
      final guest = CommunityApi(CommunityApi.parseOrigin(endpoint));
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      const password = 'synthetic-test-password';
      final a = await guest
          .request('POST', '/community/register', {
            'username': 'a$suffix',
            'password': password,
          })
          .catchError((Object error) {
            throw error is CommunityError ? error.cause ?? error : error;
          });
      final author = CommunityApi(guest.origin, token: a['token']);
      final card = await author.request('POST', '/community/characters', {
        'name': '海盐$suffix',
        'description': '来自海边',
        'persona': '喜欢听海浪',
        'avatar': 'moon',
        'voice': 'default',
      });
      final post = await author.request('POST', '/community/posts', {
        'body': '一起听海',
        'character_id': card['id'],
      });
      addTearDown(() async {
        await author.request('DELETE', "/community/posts/${post['id']}");
        await author.request('POST', '/community/logout');
      });
      Future<void> waitFor(Finder finder) async {
        final clock = Stopwatch()..start();
        while (finder.evaluate().isEmpty &&
            clock.elapsed < const Duration(seconds: 25)) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(
          finder,
          findsWidgets,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .whereType<String>()
              .take(35)
              .join(' / '),
        );
      }

      Future<void> tap(Finder finder) async {
        await tester.pump(const Duration(milliseconds: 150));
        await waitFor(finder);
        await tester.ensureVisible(finder.first);
        await tester.tap(finder.first);
        await tester.pump(const Duration(milliseconds: 450));
      }

      await app.main();
      await tap(find.byTooltip('社区'));
      await tap(find.byTooltip('打开分享链接'));
      await tester.enterText(
        find.byType(EditableText).last,
        '${guest.origin}/s/${post['share']}',
      );
      await tap(find.text('预览'));
      await tap(find.text('加入我的角色 / 开始聊天'));
      await tap(find.text('创建新账户'));
      final fields = find.descendant(
        of: find.byType(LoginDialog),
        matching: find.byType(EditableText),
      );
      await tester.enterText(fields.at(0), 'b$suffix');
      await tester.enterText(fields.at(1), password);
      await tap(find.text('注册'));
      await waitFor(find.byKey(const Key('character-name')));
      expect(find.text(card['name']), findsOneWidget);
      await tap(find.byKey(const Key('text-mode')));
      await tester.enterText(
        find.byKey(const Key('message-input')),
        '新账户的第一条消息',
      );
      await tap(find.byKey(const Key('send')));
      final b = await guest.request('POST', '/community/login', {
        'username': 'b$suffix',
        'password': password,
      });
      final reader = CommunityApi(guest.origin, token: b['token']);
      final imported = (await reader.items('/community/characters'))
          .singleWhere((r) => r['name'] == card['name']);
      final importedId = imported['id'];
      final clock = Stopwatch()..start();
      List<Json> turns = [];
      while (clock.elapsed < const Duration(seconds: 15)) {
        turns = await reader.items('/v3/conversations/$importedId');
        if (turns.isNotEmpty && turns.last['state'] == 'complete') break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(turns.last['prompt'], '新账户的第一条消息');
      expect(turns.last['state'], 'complete');
      await tap(find.byKey(const Key('open-menu')));
      await tap(find.byKey(const Key('menu-community')));
      await tap(find.text(card['name']));
      await tap(find.text('写评论'));
      await tester.enterText(find.byType(EditableText).last, '已导入，谢谢分享');
      await tap(find.text('发送'));
      await waitFor(find.text('已导入，谢谢分享'));
      expect(
        (await author.items("/community/posts/${post['id']}/comments"))
            .single['username'],
        'b$suffix',
      );
      await tap(find.text('账户'));
      await tap(find.text('退出账户'));
      await waitFor(find.text('登录 / 注册'));
      await reader.request('POST', '/community/logout');
    },
    skip: endpoint.isEmpty,
  );
}
