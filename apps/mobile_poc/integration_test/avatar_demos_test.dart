import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:companion_poc/avatar_live2d_demo.dart';
import 'package:companion_poc/avatar_video_demo.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Live2D sample and video decoder smoke checks', (
    tester,
  ) async {
    Future<void> until(bool Function() done, String reason) async {
      final limit = DateTime.now().add(const Duration(seconds: 35));
      while (!done() && DateTime.now().isBefore(limit)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue, reason: reason);
    }

    await tester.pumpWidget(const MaterialApp(home: AvatarLive2dDemo()));
    final model = tester.state<AvatarLive2dDemoState>(
      find.byType(AvatarLive2dDemo),
    );
    await until(() => !model.busy, 'Live2D initializes');
    expect(model.controller.loaded, isTrue, reason: model.status);
    final firstStats = await model.controller.stats();
    await model.playMotion(model.controller.motions.last);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final afterStats = await model.controller.stats();
    expect(afterStats['frames'], greaterThan(firstStats['frames'] as num));
    await model.changeModel('Haru');
    expect(model.controller.loaded, isTrue, reason: model.status);
    await model.controller.close();
    await tester.pumpWidget(
      const MaterialApp(home: AvatarVideoDemo(useTestStorage: true)),
    );
    final video = tester.state<AvatarVideoDemoState>(
      find.byType(AvatarVideoDemo),
    );
    await until(() => !video.busy, 'video store initializes');
    final fixture = File('/data/local/tmp/avatar-playback-fixture.mp4');
    expect(
      await fixture.exists(),
      isTrue,
      reason: 'Push the local playback fixture before testing',
    );
    // The fixture is an existing app screen recording, NOT an AI action asset.
    await video.importFile('wave', fixture);
    video.requestAction('wave');
    await until(
      () => video.current == 'wave' && !video.switching,
      'first imported action can play without idle',
    );
    for (final id in videoActions.keys) {
      await video.importFile(id, fixture);
    }
    await until(
      () => video.active!.value.position.inMilliseconds > 300,
      'real decoder advances',
    );
    await video.togglePause();
    await tester.pump(const Duration(milliseconds: 300));
    final frozen = video.active!.value.position;
    await tester.pump(const Duration(milliseconds: 400));
    expect(video.active!.value.position, frozen);
    await video.togglePause();
    video.requestAction('wave');
    video.requestAction('weight_shift');
    expect(video.pending, 'weight_shift');
    await video.active!.seekTo(
      video.active!.value.duration - const Duration(milliseconds: 150),
    );
    await until(
      () => video.current == 'weight_shift' && !video.switching,
      'latest queued action starts',
    );
    await video.active!.seekTo(
      video.active!.value.duration - const Duration(milliseconds: 150),
    );
    await until(
      () => video.current == 'idle' && !video.switching,
      'completed action returns to idle',
    );
    video.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 400));
    expect(video.active!.value.isPlaying, isFalse);
    video.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await until(
      () => video.active!.value.isPlaying,
      'resumes after foreground',
    );
    final original = video.players['idle'];
    final bad = await File('${video.directory!.path}/bad.mp4')
        .writeAsString('not a video');
    await expectLater(video.importFile('idle', bad), throwsA(anything));
    expect(video.players['idle'], same(original));
    await bad.delete();
    final directory = video.directory!;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    // Remove synthetic slot imports; the user must see an honest empty state.
    for (final id in videoActions.keys) {
      final file = File('${directory.path}/$id.mp4');
      if (await file.exists()) await file.delete();
    }
    final result = {
      'live2d': 'Mark action, Haru load and render frame progression passed',
      'video': 'real decode, pause, latest request, completion return, lifecycle, invalid replacement passed',
      'fixture':
          'existing app screen recording reused for transport testing only',
      'aiCharacterClips': 'missing, visual quality not tested',
      'externalZip': 'not implemented',
      'realDevicesAndIos': 'not tested',
    };
    final docs = await getApplicationDocumentsDirectory();
    await File('${docs.path}/avatar-demos-smoke.json')
        .writeAsString(jsonEncode(result));
    binding.reportData = result;
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
