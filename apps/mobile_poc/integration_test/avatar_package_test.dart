import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:companion_poc/avatar_package_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'v0.1 external ZIP, native playback, rollback and persistent restore',
    (tester) async {
      Future<void> waitFor(
        bool Function() done,
        String why, {
        int seconds = 35,
      }) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(done(), isTrue, reason: why);
      }

      Future<void> elapse(int milliseconds) async {
        for (var i = 0; i < milliseconds; i += 100) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      final report = <String, dynamic>{
        'runtime': 'Cubism Native 5-r.5 / native-r5-basic-v1',
        'device': 'Android API36 emulator x86_64',
        'visual': 'separate manual review',
        'started': DateTime.now().toIso8601String(),
      };
      final dir = await getApplicationDocumentsDirectory();
      await tester.pumpWidget(const AvatarPackageApp());
      var state = tester.state<AvatarPackagePageState>(
        find.byType(AvatarPackagePage),
      );
      await waitFor(() => !state.busy, 'initialize');
      await state.importFile(
        File('/data/local/tmp/avatar-packages/mark-demo-1.0.1.zip'),
      );
      expect(state.manifest['id'], 'mark-demo');
      expect(state.actions.keys, containsAll(['idle', 'wave', 'weight_shift']));
      report['package'] = state.package;
      final before = await state.controller.stats();
      final samples = <Map<String, dynamic>>[];
      for (var i = 0; i < 60; i++) {
        await elapse(500);
        samples.add(await state.controller.stats());
      }
      final breaths =
          samples
              .map((s) => (s['parameters']['ParamBreath'] as num).toDouble())
              .toList()
            ..sort();
      final eyes =
          samples
              .map((s) => (s['parameters']['ParamEyeLOpen'] as num).toDouble())
              .toList()
            ..sort();
      expect(breaths.last - breaths.first, greaterThan(0.3));
      expect(eyes.first, lessThan(0.7));
      expect(samples.last['frames'], greaterThan(before['frames'] as num));
      expect(samples.last['error'], isNull);
      report['idle30s'] = {
        'breathRange': [breaths.first, breaths.last],
        'eyeRange': [eyes.first, eyes.last],
        'frames': samples.last['frames'],
      };
      final actionRuns = <dynamic>[];
      for (final id in ['wave', 'weight_shift']) {
        for (var repeat = 0; repeat < 3; repeat++) {
          await state.play(id);
          await expectLater(
            state.play(id == 'wave' ? 'weight_shift' : 'wave'),
            throwsA(isA<PlatformException>()),
          );
          await elapse(id == 'wave' ? 1000 : 1500);
          final peak = await state.controller.stats();
          expect(peak['playingMotion'], isNotEmpty);
          if (id == 'wave') {
            expect(peak['parameters']['ParamArmR'], greaterThan(10));
          } else {
            expect(
              (peak['parameters']['ParamRightLeg'] as num).abs(),
              greaterThan(3),
            );
          }
          if (repeat == 0) {
            await state.togglePause();
            final frozen = await state.controller.stats();
            await elapse(800);
            final frozenAfter = await state.controller.stats();
            expect(frozenAfter['parameters'], frozen['parameters']);
            expect(frozenAfter['frames'], frozen['frames']);
            await expectLater(
              state.play(id),
              throwsA(isA<PlatformException>()),
            );
            final capture = await AvatarPackagePageState.channel
                .invokeMethod<String>('capture');
            await File(capture!).copy('${dir.path}/package-$id.png');
            await state.togglePause();
          }
          await waitFor(
            () => state.playing.isEmpty,
            '$id returns to idle',
            seconds: 15,
          );
          await elapse(400);
          final after = await state.controller.stats();
          expect(
            (after['parameters']['ParamRightLeg'] as num).abs(),
            lessThan(0.2),
          );
          expect(
            (after['parameters']['ParamArmR'] as num).abs(),
            lessThan(0.2),
          );
          actionRuns.add({
            'id': id,
            'repeat': repeat + 1,
            'peak': peak['parameters'],
            'returnedToIdle': true,
          });
        }
      }
      report['actions'] = actionRuns;
      await state.play('wave');
      await elapse(600);
      await state.reset();
      await elapse(300);
      expect((await state.controller.stats())['playingMotion'], '');
      expect(state.paused, isFalse);
      await state.play('weight_shift');
      await elapse(400);
      await state.togglePause();
      await state.reset();
      await elapse(200);
      expect(state.playing, '');
      expect(state.paused, isFalse);
      await expectLater(
        state.play('invented_action'),
        throwsA(isA<PlatformException>()),
      );
      final rejected = <String, String>{};
      for (final bad in [
        'missing-texture',
        'bad-index',
        'bad-moc',
        'corrupt-moc',
        'illegal-path',
        'duplicate-json',
        'unknown-parameter',
        'bad-motion',
        'case-collision',
        'version-conflict',
        'broken-texture',
        'large-cover',
        'unknown-field',
        'string-index',
        'symlink',
        'declared-size',
        'actual-size',
        'encrypted',
      ]) {
        try {
          await state.importFile(
            File('/data/local/tmp/avatar-packages/invalid-$bad.zip'),
          );
          fail('$bad unexpectedly accepted');
        } on PlatformException catch (e) {
          rejected[bad] = e.message ?? e.code;
        }
        expect(state.manifest['id'], 'mark-demo');
        expect(
          (await state.controller.stats())['packageKey'],
          'mark-demo@1.0.1',
        );
        await state.play('wave');
        await elapse(100);
        await state.reset();
      }
      report['rejections'] = rejected;
      for (final bad in [
        'bad-moc',
        'corrupt-moc',
        'unknown-parameter',
        'broken-texture',
      ]) {
        expect(rejected[bad], contains('SDK 校验失败'));
      }
      expect(rejected['case-collision'], contains('重复或大小写冲突'));
      expect(rejected['actual-size'], contains('实际解压大小超限'));
      await state.importFile(
        File('/data/local/tmp/avatar-packages/mark-switch-fixture.zip'),
      );
      expect(state.manifest['id'], 'mark-switch-fixture');
      await state.openPackage('mark-demo@1.0.1');
      expect((await state.controller.stats())['models'], 1);
      await state.play('wave');
      await elapse(600);
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      await elapse(400);
      final background = await state.controller.stats();
      await elapse(400);
      expect((await state.controller.stats())['frames'], background['frames']);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await waitFor(() => state.playing.isEmpty, 'foreground resume');
      await state.controller.close();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(const AvatarPackageApp());
      state = tester.state<AvatarPackagePageState>(
        find.byType(AvatarPackagePage),
      );
      await waitFor(() => !state.busy, 'persistent restore');
      expect(state.manifest['id'], 'mark-demo');
      await state.play('weight_shift');
      await elapse(200);
      await state.reset();
      report['app'] = {
        'busyRejected': true,
        'pauseResume': true,
        'resetDuringAction': true,
        'switchPackagesSameRig': true,
        'recreateRestore': true,
        'backgroundResume': true,
      };
      report['finalStats'] = await state.controller.stats();
      await File('${dir.path}/avatar-package-acceptance.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      await state.controller.close();
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
