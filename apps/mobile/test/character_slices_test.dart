import 'dart:convert';
import 'dart:io';

import 'package:erciyuan_mobile/immersive/character_slices.dart';
import 'package:erciyuan_mobile/immersive/widgets/slice_figure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 切片管线的契约测试。
///
/// 这里只验证**清单与渲染契约**，不做像素比对：像素级验收在
/// `tools/slice/verify.py` 与端到端截图里完成（见
/// `docs/guides/character-slice-pipeline.md` §6）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('切片清单', () {
    test('登记的半身与全身包都在 assets 里，且贴图齐全', () async {
      expect(sliceRegistry.containsKey('xing/half'), isTrue);
      expect(sliceRegistry.containsKey('xing/full'), isTrue);

      for (final form in ['half', 'full']) {
        final root = sliceRegistry['xing/$form']!;
        final manifestFile = File('$root/manifest.json');
        expect(
          manifestFile.existsSync(),
          isTrue,
          reason: '$form 缺少 manifest.json',
        );

        final json = jsonDecode(
          await manifestFile.readAsString(),
        ) as Map<String, dynamic>;
        expect(json['character'], 'xing');
        expect(json['size'], hasLength(2));

        // 基座若声明为外部引用，那条路径必须是包内已有的原画。
        if (json['plateExternal'] == true) {
          expect(File(json['plate'] as String).existsSync(), isTrue);
        }

        final slots = (json['slots'] as List).cast<Map<String, dynamic>>();
        expect(slots, isNotEmpty, reason: '$form 没有任何动作插槽');

        for (final slot in slots) {
          final rect = slot['rect'] as List;
          expect(rect, hasLength(4));
          // 插槽必须落在基座画布内，否则运行时会被画到不可见区域。
          expect(rect[2] as num, greaterThan(0));
          expect(rect[3] as num, greaterThan(0));

          final patches = (slot['patches'] as Map).cast<String, String>();
          expect(patches, isNotEmpty, reason: '${slot['id']} 没有贴图');
          for (final rel in patches.values) {
            expect(
              File('$root/$rel').existsSync(),
              isTrue,
              reason: '${slot['id']} 的贴图 $rel 缺失',
            );
          }
        }
      }
    });

    test('清单尺寸与基座原画一致，且调色参数可逆', () async {
      final s = await CharacterSlices.ensureLoaded('xing', 'half');
      expect(s.character, 'xing');
      expect(s.form, 'half');
      expect(s.size.width, greaterThan(0));
      expect(s.size.height, greaterThan(0));
      expect(s.plateAsset, contains('chat-half'));

      final grade = s.grade;
      if (grade != null) {
        // t=0 必须是单位矩阵：静止帧等于原画，这是规范 P2 的硬约束。
        final identity = grade.matrixAt(0);
        expect(identity[0], 1);
        expect(identity[6], 1);
        expect(identity[12], 1);
        expect(identity[4], 0);
        expect(identity[9], 0);
        expect(identity[14], 0);
        // t=1 时通道增益应回到清单里记录的原值。
        final full = grade.matrixAt(1);
        expect(full[0], closeTo(grade.gains[0], 1e-9));
        expect(full[4], closeTo(grade.offsets[0], 1e-9));
      }
    });

    test('未登记的形态不会伪造切片包', () {
      expect(CharacterSlices.has('xing', 'half'), isTrue);
      expect(CharacterSlices.has('xing', 'full'), isTrue);
      expect(CharacterSlices.has('yue', 'half'), isFalse);
    });

    test('加载失败不会把错误永久缓存，修好后可再次加载', () async {
      // 先正常加载一次，确认基线可用。
      final ok = await CharacterSlices.ensureLoaded('xing', 'half');
      expect(ok.slots, isNotEmpty);

      // 未登记的形态：必须抛错，且不能留下失败缓存——否则真实的资源
      // 缺失会被同一个错误长期掩盖，测试里表现为断言超时而非「资源缺失」。
      await expectLater(
        CharacterSlices.ensureLoaded('yue', 'half'),
        throwsA(isA<StateError>()),
      );
      expect(CharacterSlices.of('yue', 'half'), isNull);

      // 再来一次仍应走完整流程并抛同样的错，而不是拿到上次的残留。
      await expectLater(
        CharacterSlices.ensureLoaded('yue', 'half'),
        throwsA(isA<StateError>()),
      );

      // 已成功的结果仍然命中缓存，不会重复解析。
      expect(await CharacterSlices.ensureLoaded('xing', 'half'), same(ok));
    });
  });

  group('切片播放器', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 390, height: 844, child: child)),
    );

    testWidgets('静止时只有基座，没有动作贴图', (tester) async {
      final s = await CharacterSlices.ensureLoaded('xing', 'half');
      await tester.pumpWidget(
        host(
          SliceFigure(
            slices: s,
            active: false,
            variant: 'reply',
            animate: false,
          ),
        ),
      );
      await tester.pump();

      // 基座 = 原画本身。贴图层在 t<=0.001 时返回空组件。
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(Opacity), findsNothing);
      expect(tester.widget<Image>(find.byType(Image)).image, isA<AssetImage>());
    });

    testWidgets('动作开启后贴图淡入，关闭后完全退场', (tester) async {
      final s = await CharacterSlices.ensureLoaded('xing', 'half');
      await tester.pumpWidget(
        host(
          SliceFigure(
            slices: s,
            active: false,
            variant: 'reply',
            animate: false,
          ),
        ),
      );
      await tester.pump();

      // 进入动作。
      await tester.pumpWidget(
        host(
          SliceFigure(
            slices: s,
            active: true,
            variant: 'reply',
            animate: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final mid = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((w) => w.opacity)
          .toList();
      expect(mid, isNotEmpty, reason: '动作中应出现贴图层');
      expect(
        mid.every((o) => o > 0 && o < 1),
        isTrue,
        reason: '中途应处于淡入状态，实际 $mid',
      );

      await tester.pump(const Duration(milliseconds: 200));
      final full = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((w) => w.opacity)
          .toList();
      expect(full.every((o) => o == 1), isTrue, reason: '淡入应完成，实际 $full');

      // 回落到静止。
      await tester.pumpWidget(
        host(
          SliceFigure(
            slices: s,
            active: false,
            variant: 'reply',
            animate: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('缺少变体贴图时不崩，只显示基座', (tester) async {
      final s = await CharacterSlices.ensureLoaded('xing', 'half');
      await tester.pumpWidget(
        host(
          SliceFigure(
            slices: s,
            active: true,
            variant: 'no-such-variant',
            animate: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Opacity), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('关闭系统动画时切片完全静止', (tester) async {
      final s = await CharacterSlices.ensureLoaded('xing', 'half');
      Widget stage({required bool disableAnimations}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: SizedBox(
              width: 390,
              height: 844,
              // 与 CharacterScene 一致：系统动画关闭时不传 animate。
              child: SliceFigure(
                slices: s,
                active: false,
                variant: 'reply',
                animate: !disableAnimations,
              ),
            ),
          ),
        ),
      );

      // 关闭动画：不叠加任何滤镜，静止帧逐像素等于原画。
      await tester.pumpWidget(stage(disableAnimations: true));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ColorFiltered), findsNothing);
      expect(tester.takeException(), isNull);

      // 开启动画：出现亮度呼吸滤镜。
      await tester.pumpWidget(stage(disableAnimations: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ColorFiltered), findsWidgets);
    });
  });

  group('坐标换算', () {
    test('等比目标铺满且不裁切', () {
      // 780×1688 正是 390×844 的整 2 倍：原画按该比例制作，
      // 任何 DPR 下都应是精确铺满，不产生裁切偏移。
      final r1 = coverRect(
        const Size(780, 1688),
        const Size(390, 844),
        Alignment.topCenter,
      );
      expect(r1.left, closeTo(0, 0.001));
      expect(r1.top, closeTo(0, 0.001));
      expect(r1.width, closeTo(390, 0.001));
      expect(r1.height, closeTo(844, 0.001));
    });

    test('比例不符时按 cover 裁切，不留边', () {
      // 目标比原画更宽：按宽度铺满，纵向溢出。
      final r = coverRect(
        const Size(780, 1688),
        const Size(402, 874),
        Alignment.topCenter,
      );
      expect(r.width, greaterThan(402));
      expect(r.height, closeTo(874, 0.001));
      expect(r.top, closeTo(0, 0.001), reason: 'topCenter 不应产生纵向偏移');
      expect(r.left, lessThan(0), reason: '横向溢出应居中，左边界为负');
    });

    test('空尺寸不产生无效矩形', () {
      expect(
        coverRect(Size.zero, const Size(10, 10), Alignment.topCenter),
        Rect.zero,
      );
    });
  });
}
