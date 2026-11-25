import 'dart:ui' as ui;

import 'package:erciyuan_mobile/immersive/character_slices.dart';
import 'package:erciyuan_mobile/immersive/widgets/character_scene.dart';
import 'package:erciyuan_mobile/immersive/widgets/slice_figure.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 渲染取证：把切片场景放进真实帧管线画出来，逐像素比对。
///
/// 不做 golden 基线比对（基线随字体与引擎版本漂移会假失败），
/// 只验证两条在任何环境都能复现的硬约束：
/// 1. 静止帧与基座原画**逐像素相同**（规范 P2）。
/// 2. 动作帧的改动**全部落在切片矩形内**（规范 P1/P3）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 把 widget 按 1:1 渲染成 RGBA 字节。
  ///
  /// 两处必须走 `runAsync`，否则测试环境里拿不到真实像素：
  /// 1. `Image.asset` 的异步解码——不等它完成，`toImage()` 得到的是空白；
  /// 2. `toImage()` 自身的栅格化。
  Future<Uint8List> render(
    WidgetTester tester,
    Widget child,
    Size size, {
    List<String> precache = const [],
  }) async {
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    );
    await tester.pump();

    if (precache.isNotEmpty) {
      final context = key.currentContext!;
      await tester.runAsync(() async {
        for (final asset in precache) {
          await precacheImage(AssetImage(asset), context);
        }
      });
      // 解码结果要在下一帧才会画上去。
      await tester.pump();
      await tester.pump();
    }

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    Uint8List? result;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        result = bytes!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    });
    return result!;
  }

  /// 把 assets 里的 PNG 按目标尺寸解码成 RGBA。
  Future<Uint8List> decodeAsset(
    WidgetTester tester,
    String asset, {
    required int width,
    required int height,
  }) async {
    final data = await rootBundle.load(asset);
    Uint8List? result;
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: width,
        targetHeight: height,
      );
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();
      result = bytes!.buffer.asUint8List();
    });
    return result!;
  }

  /// 逐像素差异统计（通道最大差 > threshold 记为改动）。
  ({double mean, int changed, int total}) diff(
    Uint8List a,
    Uint8List b,
    int width,
    int height, {
    int threshold = 12,
  }) {
    var sum = 0.0;
    var changed = 0;
    final pixels = width * height;
    for (var i = 0; i < pixels; i++) {
      final o = i * 4;
      final dr = (a[o] - b[o]).abs();
      final dg = (a[o + 1] - b[o + 1]).abs();
      final db = (a[o + 2] - b[o + 2]).abs();
      sum += (dr + dg + db) / 3;
      final d = dr > dg ? (dr > db ? dr : db) : (dg > db ? dg : db);
      if (d > threshold) changed++;
    }
    return (mean: sum / pixels, changed: changed, total: pixels);
  }

  /// 统计某个矩形内的改动像素数。
  int changedInRect(
    Uint8List a,
    Uint8List b,
    int width,
    int height,
    Rect rect, {
    int threshold = 12,
  }) {
    var changed = 0;
    final top = rect.top.floor().clamp(0, height - 1);
    final bottom = rect.bottom.ceil().clamp(0, height);
    final left = rect.left.floor().clamp(0, width - 1);
    final right = rect.right.ceil().clamp(0, width);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final o = (y * width + x) * 4;
        final dr = (a[o] - b[o]).abs();
        final dg = (a[o + 1] - b[o + 1]).abs();
        final db = (a[o + 2] - b[o + 2]).abs();
        if (dr > threshold || dg > threshold || db > threshold) changed++;
      }
    }
    return changed;
  }

  /// 按基座原始像素尺寸渲染一帧。
  Future<Uint8List> renderFigure(
    WidgetTester tester,
    CharacterSlices s, {
    required bool active,
  }) {
    final size = Size(s.size.width, s.size.height);
    // 动作帧要等基座与所有贴图都解码完，否则会采到半透明的中间态。
    final assets = <String>{
      s.plateAsset,
      for (final slot in s.slots)
        if (slot.patches['reply'] != null) slot.patches['reply']!,
    }.toList();
    return render(
      tester,
      SliceFigure(slices: s, active: active, variant: 'reply', animate: false),
      size,
      precache: assets,
    );
  }

  /// 对整幅图施加切片包记录的整体调色。
  ///
  /// `SliceFigure` 在动作时会同时推进两个通道：内容替换与整体调色。
  /// 要单独验证「内容只落在矩形内」，必须先把静止帧按同一调色变换一遍，
  /// 否则全图都会因调色而不同——那是 §4.3 的设计，不是越界。
  Uint8List applyGrade(Uint8List src, List<double> m) {
    final out = Uint8List.fromList(src);
    for (var i = 0; i < out.length; i += 4) {
      final r = src[i].toDouble();
      final g = src[i + 1].toDouble();
      final b = src[i + 2].toDouble();
      double ch(int row) =>
          m[row * 5] * r +
          m[row * 5 + 1] * g +
          m[row * 5 + 2] * b +
          m[row * 5 + 3] * src[i + 3] +
          m[row * 5 + 4];
      out[i] = ch(0).round().clamp(0, 255);
      out[i + 1] = ch(1).round().clamp(0, 255);
      out[i + 2] = ch(2).round().clamp(0, 255);
      // alpha 通道保持不变（调色矩阵第四行是单位行）。
    }
    return out;
  }

  group('渲染取证', () {
    testWidgets('静止帧与基座原画逐像素相同', (tester) async {
      final s = await CharacterSlices.ensureLoaded('xing', 'half');
      final w = s.size.width.round();
      final h = s.size.height.round();

      final shot = await renderFigure(tester, s, active: false);
      final plate = await decodeAsset(
        tester,
        s.plateAsset,
        width: w,
        height: h,
      );

      final d = diff(shot, plate, w, h);
      // 允许极小的合成舍入，但不允许有任何一块区域被改动。
      expect(
        d.mean,
        lessThan(0.5),
        reason: '静止帧平均差异 ${d.mean.toStringAsFixed(2)}，应接近 0',
      );
      expect(
        d.changed / d.total,
        lessThan(0.001),
        reason:
            '静止帧有 ${(d.changed / d.total * 100).toStringAsFixed(2)}% '
            '像素不同，静止时不应有任何叠加',
      );
    });

    testWidgets('动作帧的改动全部落在切片矩形内', (tester) async {
      final s = await CharacterSlices.ensureLoaded('xing', 'half');
      final w = s.size.width.round();
      final h = s.size.height.round();

      final still = await renderFigure(tester, s, active: false);
      final moving = await renderFigure(tester, s, active: true);

      final total = diff(still, moving, w, h);
      expect(total.changed, greaterThan(0), reason: '动作帧应与静止帧有可见差异，否则动作等于没做');

      // 把调色通道补偿掉，只留内容通道。
      final grade = s.grade;
      final graded = (grade != null && !grade.isIdentity)
          ? applyGrade(still, grade.matrixAt(1))
          : still;
      final content = diff(graded, moving, w, h, threshold: 24);

      // 所有切片矩形并集之外不允许有内容改动。
      var inside = 0;
      for (final slot in s.slots) {
        inside += changedInRect(graded, moving, w, h, slot.rect, threshold: 24);
      }
      expect(
        content.changed - inside,
        lessThanOrEqualTo(0),
        reason:
            '剥掉整体调色后，切片矩形外仍有 ${content.changed - inside} '
            '个像素被改动，动作必须是整块像素替换，不能波及周围',
      );

      // ignore: avoid_print
      print(
        '[取证] 半身：全图差异 '
        '${(total.changed / total.total * 100).toStringAsFixed(2)}%，'
        '剥调色后内容差异 '
        '${(content.changed / content.total * 100).toStringAsFixed(2)}%，'
        '全部落在 ${s.slots.length} 个切片矩形内；'
        '平均差 ${total.mean.toStringAsFixed(2)}',
      );
    });

    testWidgets('全身包同样满足静止无损', (tester) async {
      final s = await CharacterSlices.ensureLoaded('xing', 'full');
      final w = s.size.width.round();
      final h = s.size.height.round();

      final shot = await renderFigure(tester, s, active: false);
      final plate = await decodeAsset(
        tester,
        s.plateAsset,
        width: w,
        height: h,
      );

      final d = diff(shot, plate, w, h);
      expect(d.changed / d.total, lessThan(0.001));
    });
  });

  group('素材完整性', () {
    testWidgets('贴图尺寸等于插槽矩形，贴回基座不会被拉伸', (tester) async {
      for (final form in ['half', 'full']) {
        final s = await CharacterSlices.ensureLoaded('xing', form);
        for (final slot in s.slots) {
          final asset = slot.patches['reply'];
          expect(asset, isNotNull, reason: '$form/${slot.id} 缺 reply 贴图');
          final data = await rootBundle.load(asset!);
          expect(data.lengthInBytes, greaterThan(0));

          // 解码同样要走真实异步，否则会卡在加载阶段。
          ({int width, int height})? size;
          await tester.runAsync(() async {
            final codec = await ui.instantiateImageCodec(
              data.buffer.asUint8List(),
            );
            final frame = await codec.getNextFrame();
            size = (width: frame.image.width, height: frame.image.height);
            frame.image.dispose();
          });
          expect(size, isNotNull);
          expect(
            size!.width,
            slot.rect.width.round(),
            reason: '$form/${slot.id} 贴图宽度与矩形不符，会被拉伸',
          );
          expect(
            size!.height,
            slot.rect.height.round(),
            reason: '$form/${slot.id} 贴图高度与矩形不符，会被拉伸',
          );
        }
      }
    });

    testWidgets('无切片包的角色不误用切片分支', (tester) async {
      expect(CharacterScene.hasSlices('xing', full: false), isTrue);
      expect(CharacterScene.hasSlices('xing', full: true), isTrue);
      expect(CharacterScene.hasSlices('yue', full: false), isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 402,
              height: 874,
              child: CharacterScene(
                role: 'yue',
                full: false,
                replying: false,
                foreground: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
