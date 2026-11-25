import 'package:material_ui/material_ui.dart';

import '../avatar.dart';
import '../character_slices.dart';
import 'slice_figure.dart';

/// 角色舞台。
///
/// 有切片包（原画 + 局部差分）的角色走 [SliceFigure]：基座铺原画、
/// 静止时零叠加，动作时只替换切片区域。规范见
/// `docs/guides/character-slice-pipeline.md`。
///
/// 没有切片包的角色沿用整图切换，切换瞬间整幅都在变。
class CharacterScene extends StatelessWidget {
  const CharacterScene({
    super.key,
    required this.role,
    required this.replying,
    required this.foreground,
    this.zoom = 1.0,
    this.full = true,
  });
  final String role;
  final bool replying, foreground;

  /// 连续缩放倍数（#95）。1.0 是原尺寸。
  final double zoom;

  /// 取全身还是半身那一套切片包。
  ///
  /// 连续缩放（#95）之后，舞台铺的始终是全身原画 `chat-full.png`，缩放
  /// 不再换图，所以默认就是 `full`。半身那一套仍保留在资产与 manifest 里
  /// （`CharacterSlices.has('xing', 'half')` 为真），由需要半身构图的调用方
  /// 显式传 `full: false` 取用。
  final bool full;

  /// 该角色该形态是否有切片包（原画 + 差分）。
  static bool hasSlices(String role, {required bool full}) =>
      CharacterSlices.has(role, full ? 'full' : 'half');

  /// 整图角色的素材名，供测试与调试确认取了哪张差分。
  static String illustrationName({
    required bool full,
    required bool replying,
  }) => 'chat-${full ? 'full' : 'half'}${replying ? '-reply' : ''}';

  @override
  Widget build(BuildContext context) {
    final form = full ? 'full' : 'half';
    // 呼吸只在有动效的场景启用；关闭系统动画时不跑。
    final animate = foreground && !MediaQuery.disableAnimationsOf(context);

    Widget fallback() => Center(
      child: FractionallySizedBox(
        widthFactor: full ? .65 : .95,
        heightFactor: full ? .65 : .9,
        child: Avatar(
          role: role,
          emotion: '平静',
          activity: replying ? '等待' : '待机',
          animate: animate,
        ),
      ),
    );

    /// 整图：没有切片包时的保底。
    Widget stillScene() {
      final name = illustrationName(full: full, replying: replying);
      return Image.asset(
        'assets/immersive_chat/$name.png',
        key: ValueKey(name),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => fallback(),
      );
    }

    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF403448), Color(0xFF171620)],
              ),
            ),
          ),
          if (role == 'xing' && full)
            Image.asset(
              'assets/immersive_chat/chat-floor.png',
              fit: BoxFit.cover,
            ),
          if (role == 'xing')
            Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: full ? .805 : 1,
                child: Transform.scale(
                  scale: zoom,
                  alignment: const FractionalOffset(.5, .21),
                  child: hasSlices(role, full: full)
                      ? _SlicesView(
                          role: role,
                          form: form,
                          replying: replying,
                          animate: animate,
                          // 加载中或切片损坏时显示原画静止帧——
                          // 切片只是动作增强，拿不到时角色也应完整可见。
                          fallback: stillScene,
                        )
                      : stillScene(),
                ),
              ),
            )
          else
            Transform.scale(
              scale: zoom,
              alignment: const FractionalOffset(.5, .45),
              child: fallback(),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .3, .55, 1],
                colors: [
                  Color(0x70171620),
                  Color(0x00171620),
                  Color(0x20171620),
                  Color(0xF0171620),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 异步加载切片包，加载完成前显示原画静止帧。
///
/// 加载前的兜底必须是**原画**而不是占位形象——切片只是动作增强，
/// 拿不到切片时角色也应该完整可见。
class _SlicesView extends StatefulWidget {
  const _SlicesView({
    required this.role,
    required this.form,
    required this.replying,
    required this.animate,
    required this.fallback,
  });

  final String role;
  final String form;
  final bool replying;
  final bool animate;
  final Widget Function() fallback;

  @override
  State<_SlicesView> createState() => _SlicesViewState();
}

class _SlicesViewState extends State<_SlicesView> {
  CharacterSlices? _slices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_SlicesView old) {
    super.didUpdateWidget(old);
    if (old.role != widget.role || old.form != widget.form) {
      _slices = null;
      _load();
    }
  }

  Future<void> _load() async {
    final cached = CharacterSlices.of(widget.role, widget.form);
    if (cached != null) {
      if (mounted) setState(() => _slices = cached);
      return;
    }
    try {
      final s = await CharacterSlices.ensureLoaded(widget.role, widget.form);
      if (mounted) setState(() => _slices = s);
    } catch (_) {
      // 切片不可用时保持原画静止，不影响其它功能。
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _slices;
    if (s == null) return widget.fallback();
    return SliceFigure(
      slices: s,
      active: widget.replying,
      variant: 'reply',
      animate: widget.animate,
    );
  }
}
