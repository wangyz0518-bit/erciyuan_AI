import 'package:erciyuan_mobile/bootstrap.dart';
import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Uses the real local FastAPI ledger with demo text and synthetic PCM.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('VOICE_TEST_URL');
  const token = String.fromEnvironment('VOICE_TEST_TOKEN');
  testWidgets(
    'two characters read saved replies and keep independent histories',
    (tester) async {
      final dbPath = path.join(
        await getDatabasesPath(),
        'voice-smoke-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final database = await PersonDatabase.open(databasePath: dbPath);
      final app = await bootstrapCompanionApp(
        database: database,
        gatewayUri: Uri.parse(url),
        gatewayToken: token,
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('character-star')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('continue-timeline')));
      await tester.pumpAndSettle();

      Future<void> sendAndHear(String role) async {
        expect(find.byTooltip('开启角色朗读'), findsOneWidget);
        await tester.tap(find.byTooltip('开启角色朗读'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '开启角色朗读'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('character-draft')),
          '测试 $role',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('send-message')));
        final timer = Stopwatch()..start();
        while (timer.elapsed < const Duration(seconds: 35)) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.text('正在播放离线测试音').evaluate().isNotEmpty ||
              find.text('测试音播放结束').evaluate().isNotEmpty) {
            break;
          }
        }
        expect(find.textContaining('测试音'), findsOneWidget);
        final events = await database.rawEventsFor(
          scope: PersonScope(ownerId: localOwnerId, characterId: role),
        );
        expect(events.map((e) => e.speaker), ['user', 'assistant']);
        expect(events.first.content, '测试 $role');
        expect(events.last.content, contains('模拟回复'));
      }

      await sendAndHear('star');
      await tester.tap(find.byKey(const ValueKey('chat-switch-character')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小月').last);
      await tester.pumpAndSettle();
      expect(find.text('测试 star'), findsNothing);
      await sendAndHear('moon');
      await tester.tap(find.byTooltip('关闭角色朗读'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('开启角色朗读'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await deleteDatabase(dbPath);
    },
    skip: url.isEmpty || token.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
