import 'dart:convert';
import 'dart:io';

import 'package:erciyuan_mobile/community/account_page.dart';
import 'package:erciyuan_mobile/community/community_api.dart';
import 'package:erciyuan_mobile/community/community_controller.dart';
import 'package:erciyuan_mobile/community/community_forms.dart';
import 'package:erciyuan_mobile/community/role_tools_page.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void registerAccountFlowChecks(String endpoint) {
  testWidgets(
    'bind an asset, back up a device, restore on a clean device, recover and erase the account',
    (tester) async {
      final origin = CommunityApi.parseOrigin(endpoint);
      final guest = CommunityApi(origin);
      final name = 'restore${DateTime.now().microsecondsSinceEpoch}';
      const pass = 'synthetic-password';
      final signup = await guest.request('POST', '/community/register', {
        'username': name,
        'password': pass,
      });
      final owner = signup['id'] as String;
      final api = CommunityApi(
        origin,
        owner: owner,
        username: name,
        token: signup['token'],
      );
      final dir = await Directory.systemTemp.createTemp('companion-device-');
      final first = await PersonDatabase.open(
        databasePath: '${dir.path}/first.db',
      );
      final fresh = await PersonDatabase.open(
        databasePath: '${dir.path}/fresh.db',
      );
      addTearDown(() async {
        await first.close();
        await fresh.close();
        await dir.delete(recursive: true);
      });
      final model = CommunityController(first)..api = api;
      await model.refreshLibrary();
      final scope = PersonScope(ownerId: owner, characterId: 'sprout');
      await first.appendEvent(
        scope: scope,
        eventId: 'synthetic-event',
        speaker: 'user',
        content: '新设备可恢复的文字',
      );
      final card = (await api.items('/community/characters'))
          .singleWhere((r) => r['id'] == 'sprout');
      // A tiny synthetic PNG goes through the same image normalization as a picked file.
      final portrait = await api.request(
        'PUT',
        '/community/characters/sprout/portrait',
        {
          'image': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+X1kAAAAASUVORK5CYII=',
        },
      );
      Future<void> screen(Widget page) async {
        await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: page));
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> wait(Finder f) async {
        final timer = Stopwatch()..start();
        while (f.evaluate().isEmpty &&
            timer.elapsed < const Duration(seconds: 25)) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(f, findsWidgets);
      }

      Future<void> tap(Finder f) async {
        await wait(f);
        await tester.ensureVisible(f.first);
        await wait(f.first.hitTestable());
        await tester.tap(f.first);
        await tester.pump(const Duration(milliseconds: 350));
      }

      Future<void> press(String label) async => tap(find.text(label));
      Finder inDialog(String label) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(label),
      );
      Future<void> fill(List<String> values) async {
        final fields = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(EditableText),
        );
        await wait(fields);
        for (int i = 0; i < values.length; i++) {
          await tester.enterText(fields.at(i), values[i]);
        }
      }

      await screen(
        RoleAssetsPage(api, {...card, 'portrait': portrait['portrait']}),
      );
      await wait(find.text('明快'));
      expect(
        tester.widget<RolePortrait>(find.byType(RolePortrait)).portrait,
        isNotNull,
      );
      final bright = find.widgetWithText(ListTile, '明快');
      await tap(find.descendant(of: bright, matching: find.text('绑定')));
      await wait(find.descendant(of: bright, matching: find.text('已绑定')));
      expect(
        (await api.request(
          'GET',
          '/community/characters/sprout/voice-binding',
        ))['profile_id'],
        'bright',
      );
      await screen(AccountPage(model));
      await press('备份本机数据');
      await tap(inDialog('开始备份'));
      await wait(find.text('备份成功'));
      final other = CommunityController(fresh)..api = api;
      await other.refreshLibrary();
      expect(
        (jsonDecode(await fresh.exportOwnerJson(owner))['raw_events'] as List),
        isEmpty,
      );
      await screen(AccountPage(other));
      await press('从账户恢复');
      await tap(inDialog('确认恢复'));
      await wait(find.text('恢复成功'));
      expect(
        (jsonDecode(await fresh.exportOwnerJson(owner))['raw_events'] as List)
            .single['content'],
        '新设备可恢复的文字',
      );
      await press('生成恢复码');
      await fill([pass]);
      await tap(inDialog('确认'));
      await wait(find.byType(SelectableText));
      final code = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      await press('已保存');
      await screen(
        Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => resetPassword(ctx, guest),
              child: const Text('找回账户'),
            ),
          ),
        ),
      );
      await press('找回账户');
      await fill([name, code, 'new-synthetic-password']);
      await tap(inDialog('确认'));
      await wait(find.text('密码已更新，请重新登录'));
      await expectLater(
        api.request('GET', '/community/me'),
        throwsA(isA<CommunityError>()),
      );
      final login = await guest.request('POST', '/community/login', {
        'username': name,
        'password': 'new-synthetic-password',
      });
      other.api = CommunityApi(
        origin,
        owner: owner,
        username: name,
        token: login['token'],
      );
      final signed = other.api;
      await screen(AccountPage(other));
      await press('注销账户');
      await fill(['new-synthetic-password']);
      await tap(inDialog('确认'));
      await tap(inDialog('永久注销'));
      final clock = Stopwatch()..start();
      while (other.api.signedIn &&
          clock.elapsed < const Duration(seconds: 20)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(other.api.signedIn, isFalse);
      expect(await fresh.charactersForOwner(owner), isEmpty);
      await expectLater(
        signed.request('GET', '/community/me'),
        throwsA(isA<CommunityError>()),
      );
    },
    skip: endpoint.isEmpty,
  );
}
