import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// 角色切片包：基座 + 若干局部动作贴图。
///
/// 规格见 `docs/guides/character-slice-pipeline.md`。
/// 核心约定（规范 P2）：**基座就是原画本身**，静止时零叠加，
/// 因此不存在"画风被削弱"的可能。
///
/// 数据来自 `manifest.json`，由 `tools/slice/build.py` 生成。
/// 新增角色只需在 [sliceRegistry] 加一条，渲染逻辑不用改。
class CharacterSlices {
  CharacterSlices._({
    required this.character,
    required this.form,
    required this.plateAsset,
    required this.size,
    required this.slots,
    required this.grade,
  });

  final String character;

  /// 取景形态：`half` / `full`。
  final String form;

  /// 基座资源路径。通常直接引用原画，避免重复占包体。
  final String plateAsset;

  /// 基座像素尺寸，用于把切片矩形映射到屏幕坐标。
  final ui.Size size;

  final List<SliceSlot> slots;

  /// 变体自带的整体调色。与内容改动分开播（规范 §4.3）。
  final SliceGrade? grade;

  static final Map<String, CharacterSlices> _loaded = {};
  static final Map<String, Future<CharacterSlices>> _loading = {};

  static const String _manifestPath = 'manifest.json';

  /// 已加载的切片包，未完成时为 null。
  static CharacterSlices? of(String character, String form) =>
      _loaded['$character/$form'];

  /// 该角色该形态是否配了切片包。
  static bool has(String character, String form) =>
      sliceRegistry.containsKey('$character/$form');

  /// 加载切片清单。同一份清单只解析一次。
  static Future<CharacterSlices> ensureLoaded(String character, String form) {
    final key = '$character/$form';
    final cached = _loaded[key];
    if (cached != null) return Future.value(cached);
    return _loading.putIfAbsent(key, () async {
      final root = sliceRegistry[key];
      if (root == null) {
        throw StateError('角色 $character 的 $form 形态没有切片包');
      }
      final raw = await rootBundle.loadString('$root/$_manifestPath');
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final sizeList = (json['size'] as List).cast<num>();
      final slots = <SliceSlot>[];
      for (final s in (json['slots'] as List).cast<Map<String, dynamic>>()) {
        final r = (s['rect'] as List).cast<num>();
        final patches = (s['patches'] as Map).cast<String, String>();
        for (final rel in patches.values) {
          // 贴图缺失会让动作静默消失，这里提前暴露。
          await rootBundle.load('$root/$rel');
        }
        slots.add(
          SliceSlot(
            id: s['id'] as String,
            rect: ui.Rect.fromLTWH(
              r[0].toDouble(),
              r[1].toDouble(),
              r[2].toDouble(),
              r[3].toDouble(),
            ),
            feather: (s['feather'] as num?)?.toDouble() ?? 0,
            patches: {
              for (final e in patches.entries) e.key: '$root/${e.value}',
            },
          ),
        );
      }

      SliceGrade? grade;
      final g = json['grade'] as Map<String, dynamic>?;
      if (g != null) {
        final gains = (g['gains'] as List)
            .cast<num>()
            .map((v) => v.toDouble())
            .toList();
        final offsets = (g['offsets'] as List)
            .cast<num>()
            .map((v) => v.toDouble())
            .toList();
        grade = SliceGrade(
          key: g['key'] as String,
          gains: gains,
          offsets: offsets,
        );
      }

      final slices = CharacterSlices._(
        character: character,
        form: form,
        // 基座可能引用包内已有的原画（plateExternal=true），
        // 此时清单里存的就是完整资源路径，不能再拼目录。
        plateAsset: (json['plateExternal'] as bool? ?? false)
            ? json['plate'] as String
            : '$root/${json['plate']}',
        size: ui.Size(sizeList[0].toDouble(), sizeList[1].toDouble()),
        slots: slots,
        grade: grade,
      );
      _loaded[key] = slices;
      return slices;
    });
  }
}

/// 一个动作插槽：固定像素区域 + 该区域的变体贴图。
class SliceSlot {
  const SliceSlot({
    required this.id,
    required this.rect,
    required this.feather,
    required this.patches,
  });

  final String id;

  /// 在基座坐标系中的区域（含外扩）。
  final ui.Rect rect;

  /// 羽化宽度，仅用于说明；实际已烘焙进贴图 alpha。
  final double feather;

  /// 变体 key → 贴图资源路径。
  final Map<String, String> patches;
}

/// 整体调色参数（规范 §4.3 的"调色通道"）。
class SliceGrade {
  const SliceGrade({
    required this.key,
    required this.gains,
    required this.offsets,
  });

  final String key;
  final List<double> gains;
  final List<double> offsets;

  bool get isIdentity =>
      gains.every((g) => (g - 1).abs() < 0.02) &&
      offsets.every((o) => o.abs() < 0.02);

  /// 按进度插值出一组乘数，交给 ColorFilter 使用。
  ///
  /// 做成 4×5 颜色矩阵：对角放大 gain，末列加 offset。
  /// `t=0` 是单位矩阵（完全不动），`t=1` 是完全应用调色。
  List<double> matrixAt(double t) {
    double g(int i) => 1 + (gains[i] - 1) * t;
    double o(int i) => offsets[i] * t;
    // 矩阵作用在 0..255 的通道值上，offset 要同尺度。
    return <double>[
      g(0), 0, 0, 0, o(0) * 1.0, //
      0, g(1), 0, 0, o(1) * 1.0, //
      0, 0, g(2), 0, o(2) * 1.0, //
      0, 0, 0, 1, 0,
    ];
  }
}

/// 角色 → 形态 → 资源根目录。
///
/// **新增有差分的角色加在这里。** 值必须是 `manifest.json` 所在目录。
const Map<String, String> sliceRegistry = {
  'xing/half': 'assets/xing/half',
  'xing/full': 'assets/xing/full',
};
