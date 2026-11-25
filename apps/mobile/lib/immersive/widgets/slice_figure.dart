import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../character_slices.dart';

/// 切片播放器：把「基座 + 局部贴图」组装成一个会动的角色。
///
/// 规格见 `docs/guides/character-slice-pipeline.md` §4。
///
/// 三条铁律（对应规范 P1–P3）：
/// 1. **基座永远是原画本身**，静止时零叠加 → 画风不可能被削弱。
/// 2. **动作只做整块像素替换**，不做位移/缩放/网格变形 → 光影不会错位。
/// 3. **调色与内容分两个通道推进**（§4.3）→ 氛围和动作各司其职。
class SliceFigure extends StatefulWidget {
  const SliceFigure({
    super.key,
    required this.slices,
    required this.active,
    required this.variant,
    required this.animate,
  });

  final CharacterSlices slices;

  /// 是否处于动作状态（如回复中）。
  final bool active;

  /// 目标变体 key，通常是 `reply`。
  final String variant;

  /// 是否启用待机呼吸。为 false 时完全静止，便于截图比对。
  final bool animate;

  @override
  State<SliceFigure> createState() => _SliceFigureState();
}

class _SliceFigureState extends State<SliceFigure>
    with TickerProviderStateMixin {
  /// 动作进度：0 = 纯基座，1 = 完全切到变体。
  late final AnimationController _act = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 320),
  );

  /// 待机呼吸：只驱动亮度，绝不驱动位移（规范 §4.4）。
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _act.value = 1;
    if (widget.animate) _breath.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(SliceFigure old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      // 进入快、回落慢：进入像"响应"，回落像"放松"（规范 §4.5）。
      if (widget.active) {
        _act.forward();
      } else {
        _act.reverse();
      }
    }
    if (old.animate != widget.animate) {
      if (widget.animate) {
        _breath.repeat(reverse: true);
      } else {
        _breath.stop();
      }
    }
  }

  @override
  void dispose() {
    _act.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slices;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 基座层：原画原样。动作时同步施加整体调色（调色通道）。
        AnimatedBuilder(
          animation: Listenable.merge([_act, _breath]),
          builder: (context, child) {
            final t = Curves.easeOut.transform(_act.value);
            final grade = s.grade;
            Widget plate = child!;
            if (grade != null && !grade.isIdentity && t > 0) {
              plate = ColorFiltered(
                colorFilter: ColorFilter.matrix(grade.matrixAt(t)),
                child: plate,
              );
            }
            // 呼吸：整幅亮度微调，幅度 ≤ 3%（规范 §4.4）。
            if (widget.animate) {
              final k = 1 + math.sin(_breath.value * math.pi * 2) * 0.022;
              plate = ColorFiltered(
                colorFilter: ColorFilter.matrix(<double>[
                  k, 0, 0, 0, 0, //
                  0, k, 0, 0, 0, //
                  0, 0, k, 0, 0, //
                  0, 0, 0, 1, 0,
                ]),
                child: plate,
              );
            }
            return plate;
          },
          child: Image.asset(
            s.plateAsset,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.high,
          ),
        ),
        // 动作贴图层：只覆盖切片矩形，区域内 alpha 混合。
        if (s.slots.isNotEmpty)
          AnimatedBuilder(
            animation: _act,
            builder: (context, _) {
              final t = Curves.easeOut.transform(_act.value);
              if (t <= 0.001) return const SizedBox.shrink();
              return Stack(
                fit: StackFit.expand,
                children: [
                  for (final slot in s.slots)
                    if (slot.patches[widget.variant] != null)
                      _SlotPatch(
                        asset: slot.patches[widget.variant]!,
                        rect: slot.rect,
                        plateSize: s.size,
                        opacity: t,
                      ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// 把一格贴图精确贴回基座的对应位置。
///
/// 坐标换算必须与基座的 `BoxFit.cover` + `topCenter` 完全一致，
/// 否则贴图会整体偏移——这是这类实现最容易出错的地方。
class _SlotPatch extends StatelessWidget {
  const _SlotPatch({
    required this.asset,
    required this.rect,
    required this.plateSize,
    required this.opacity,
  });

  final String asset;
  final Rect rect;
  final Size plateSize;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dst = coverRect(
          plateSize,
          constraints.biggest,
          Alignment.topCenter,
        );
        final scale = dst.width / plateSize.width;
        final target = Rect.fromLTWH(
          dst.left + rect.left * scale,
          dst.top + rect.top * scale,
          rect.width * scale,
          rect.height * scale,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: target,
              child: Opacity(
                opacity: opacity.clamp(0, 1),
                child: Image.asset(
                  asset,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                  // 贴图自带羽化 alpha，不能再加圆角或裁剪。
                  gaplessPlayback: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 计算 `BoxFit.cover` 在给定容器里的实际绘制矩形。
///
/// 与 Flutter 的 cover 语义一致：等比放大到铺满，再按对齐方式裁切。
Rect coverRect(Size src, Size dst, Alignment align) {
  if (src.width <= 0 || src.height <= 0) return Rect.zero;
  final scale = math.max(dst.width / src.width, dst.height / src.height);
  final w = src.width * scale;
  final h = src.height * scale;
  final dx = (dst.width - w) * (align.x + 1) / 2;
  final dy = (dst.height - h) * (align.y + 1) / 2;
  return Rect.fromLTWH(dx, dy, w, h);
}
