import 'package:erciyuan_mobile/community/community_api.dart';
import 'package:erciyuan_mobile/community/community_forms.dart';
import 'package:erciyuan_mobile/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'account_flow_checks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('COMMUNITY_GATEWAY_URL');
  const withOperator = bool.fromEnvironment('COMMUNITY_OPERATOR_E2E');
  testWidgets(
    'a guest finds and imports a shared role, chats, reports content and reads the operator replies',
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
      addTearDown(() => author.request('POST', '/community/logout'));
      final other = await author.request('POST', '/community/posts', {
        'body': '无关讨论$suffix',
      });
      addTearDown(
        () => author.request('DELETE', "/community/posts/${other['id']}"),
      );
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
      if (withOperator) {
        await author.request(
          'POST',
          "/community/posts/${post['id']}/comments",
          {'body': '供审核的测试评论'},
        );
      }
      addTearDown(() async {
        await author.request('DELETE', "/community/posts/${post['id']}");
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
        final buttons = find.ancestor(
          of: finder.first,
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        if (buttons.evaluate().isNotEmpty) {
          await waitFor(
            find.ancestor(
              of: finder.first,
              matching: find.byWidgetPredicate(
                (w) => w is ButtonStyleButton && w.onPressed != null,
              ),
            ),
          );
        }
        await waitFor(finder.first.hitTestable());
        await tester.tap(finder.first);
        await tester.pump(const Duration(milliseconds: 450));
      }

      Future<void> enterDialog(String value) async {
        final field = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(EditableText),
        );
        await waitFor(field);
        await tester.enterText(field, value);
      }

      Finder nav(String section) => find.byKey(ValueKey('nav-$section'));
      final result = find.byKey(ValueKey("community-post-${post['id']}"));
      Future<void> search(String value) async {
        final field = find.byKey(const ValueKey('community-search'));
        final ready = find.descendant(
          of: field,
          matching: find.byWidgetPredicate(
            (w) => w is EditableText && !w.readOnly,
          ),
        );
        await waitFor(ready);
        await tester.enterText(ready, value);
        expect(tester.widget<EditableText>(ready).controller.text, value);
        await tap(find.byTooltip('搜索'));
        await waitFor(find.text('清除搜索「$value」'));
        await waitFor(ready);
      }

      Future<void> previewLink() async {
        await tap(
          find.byWidgetPredicate(
            (w) =>
                w is IconButton && w.tooltip == '打开分享链接' && w.onPressed != null,
          ),
        );
        final dialog = find.widgetWithText(AlertDialog, '打开角色链接');
        final field = find.descendant(
          of: dialog,
          matching: find.byType(EditableText),
        );
        await waitFor(field);
        await tester.enterText(field, '${guest.origin}/s/${post['share']}');
        await tap(find.descendant(of: dialog, matching: find.text('预览')));
      }

      await app.main();
      await waitFor(find.byKey(const ValueKey('character-draft')));
      for (final section in ['companion', 'roles', 'community', 'profile']) {
        expect(nav(section), findsOneWidget);
      }
      await tap(nav('roles'));
      await tap(find.byKey(const ValueKey('character-moon')));
      await tap(find.byKey(const ValueKey('continue-timeline')));
      await waitFor(find.text('小月'));
      await tap(nav('profile'));
      await tap(find.text('本机数据管理'));
      await waitFor(find.text('导出全部人物数据'));
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      await tap(nav('community'));
      await waitFor(result);
      await tap(find.text('发现角色'));
      await waitFor(find.text('返回全部帖子'));
      await waitFor(result);
      expect(find.text(other['body']), findsNothing);
      await tap(find.text('返回全部帖子'));
      await waitFor(find.text(other['body']));
      await previewLink();
      await waitFor(find.text('加入我的角色 / 开始聊天'));
      await tester.pageBack();
      await search(card['name'] as String);
      await waitFor(result);
      expect(find.text(other['body']), findsNothing);
      await tap(result);
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
      await tap(find.byKey(const Key('open-menu')));
      await tap(find.text('设置'));
      await tap(find.text('角色记忆'));
      await tap(find.text('添加记忆'));
      await enterDialog('周末喜欢海边散步');
      await tap(find.text('保存'));
      await waitFor(find.text('周末喜欢海边散步'));
      await tap(find.text('纠正'));
      await enterDialog('周末喜欢海边看书');
      await tap(find.text('保存'));
      await waitFor(find.text('周末喜欢海边看书'));
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 450));
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
      await tester.enterText(
        find.byKey(const Key('message-input')),
        '切换入口后保留的草稿',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 350));
      await tap(nav('roles'));
      await waitFor(find.text(card['name']));
      await tap(find.byTooltip("管理${card['name']}"));
      await tap(find.text('记忆'));
      await waitFor(find.text('周末喜欢海边看书'));
      await tester.pageBack();
      await tap(nav('companion'));
      await waitFor(find.byKey(const Key('character-name')));
      if (find.byKey(const Key('text-mode')).evaluate().isNotEmpty) {
        await tap(find.byKey(const Key('text-mode')));
      }
      expect(find.text('切换入口后保留的草稿'), findsOneWidget);
      await tap(nav('community'));
      await search('一起听海');
      await tap(result);
      await tap(find.text('写评论'));
      await enterDialog('已导入，谢谢分享');
      await tap(find.text('发送'));
      await waitFor(find.text('已导入，谢谢分享'));
      expect(
        (await author.items("/community/posts/${post['id']}/comments"))
            .singleWhere((row) => row['body'] == '已导入，谢谢分享')['username'],
        'b$suffix',
      );
      if (withOperator) {
        final comments = await author.items(
          "/community/posts/${post['id']}/comments",
        );
        final mine = comments.singleWhere((row) => row['body'] == '已导入，谢谢分享');
        await author.request(
          'POST',
          "/community/posts/${post['id']}/comments",
          {'parent_id': mine['id'], 'body': '海盐作者的回复'},
        );
        await tester.pageBack();
        await waitFor(find.byKey(const ValueKey('community-search')));
        await tap(find.text('回复通知'));
        await tap(find.text('海盐作者的回复'));
        await waitFor(find.textContaining('通知定位'));
        await tap(find.byTooltip('举报评论'));
        await enterDialog('请审核这条评论');
        await tap(find.text('提交举报'));
      }
      await tap(find.text('举报帖子'));
      await enterDialog('请审核人设说明');
      await tap(find.text('提交举报'));
      await tap(nav('profile'));
      await tap(find.text('反馈与处理记录'));
      await waitFor(find.text('请审核人设说明'));
      await tap(find.text('提交反馈'));
      await enterDialog('建议增加角色标签');
      await tap(find.text('提交'));
      await waitFor(find.textContaining('建议增加角色标签'));
      if (withOperator) {
        final deadline = Stopwatch()..start();
        List<Json> tickets;
        do {
          tickets = await reader.items('/community/tickets');
          if (tickets.length == 3 && tickets.every((t) => t['reply'] != null)) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 350));
        } while (deadline.elapsed < const Duration(seconds: 90));
        expect(
          tickets.map((t) => t['action']),
          unorderedEquals(['hide', 'hide', 'reply']),
        );
        await tap(find.byTooltip('刷新'));
        await waitFor(find.textContaining('运营回复：已下架测试分享'));
        await waitFor(find.textContaining('运营回复：已下架测试评论'));
        await waitFor(find.textContaining('运营回复：已收到角色标签建议'));
      }
      expect((await author.items('/community/tickets')), isEmpty);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      if (withOperator) {
        await tap(nav('community'));
        await search(card['name'] as String);
        await waitFor(find.text('没有找到匹配的帖子或角色。'));
        expect(result, findsNothing);
        await tap(find.text("清除搜索「${card['name']}」"));
        await waitFor(find.text(other['body']));
        await previewLink();
        await waitFor(find.text('帖子已删除、已下架或分享已撤回。'));
        expect(find.text('加入我的角色 / 开始聊天'), findsNothing);
        await waitFor(find.text(other['body']));
        await expectLater(
          reader.request('POST', "/community/shares/${post['share']}/import"),
          throwsA(
            isA<CommunityError>().having(
              (e) => e.code,
              'code',
              'POST_NOT_FOUND',
            ),
          ),
        );
        await tap(nav('roles'));
        await waitFor(find.text(card['name']));
        expect(
          (await reader.items('/v3/conversations/$importedId')).last['prompt'],
          '新账户的第一条消息',
        );
        await tap(nav('profile'));
      }
      await tap(find.text('退出账户'));
      await waitFor(find.text('登录 / 注册'));
      await tap(nav('roles'));
      await waitFor(find.byKey(const ValueKey('character-star')));
      expect(find.text(card['name']), findsNothing);
      await tap(nav('profile'));
      await tap(find.text('登录 / 注册'));
      await tester.enterText(fields.at(0), 'a$suffix');
      await tester.enterText(fields.at(1), password);
      await tap(find.text('登录'));
      await waitFor(find.text('退出账户').hitTestable());
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'a$suffix'),
        findsOneWidget,
      );
      await tap(nav('companion'));
      await waitFor(find.byKey(const Key('character-name')));
      expect(find.text('新账户的第一条消息'), findsNothing);
      expect(find.text('切换入口后保留的草稿'), findsNothing);
      await tap(nav('profile'));
      await tap(find.text('退出账户'));
      await waitFor(find.text('登录 / 注册'));
      await reader.request('POST', '/community/logout');
    },
    skip: endpoint.isEmpty && !withOperator,
  );
  registerAccountFlowChecks(endpoint);
}
