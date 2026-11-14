import 'dart:math' as math;
import 'dart:typed_data';

/// A continuous deformation field fitted to dragon-character-v1.png.
/// Every region shares the same mesh, so neighboring regions cannot separate.
class DragonIdleMesh {
  DragonIdleMesh({this.columns = 48, this.rows = 48})
    : positions = Float32List((columns + 1) * (rows + 1) * 2),
      indices = Uint16List(columns * rows * 6) {
    for (int row = 0; row <= rows; row++) {
      for (int col = 0; col <= columns; col++) {
        final x = col / columns, y = row / rows;
        _points.add(_WeightedPoint(x, y));
      }
    }
    int offset = 0;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < columns; col++) {
        final top = row * (columns + 1) + col;
        final bottom = top + columns + 1;
        for (final index in [
          top,
          top + 1,
          bottom,
          top + 1,
          bottom + 1,
          bottom,
        ]) {
          indices[offset++] = index;
        }
      }
    }
    update(0, 0);
  }

  final int columns, rows;
  final Float32List positions;
  final Uint16List indices;
  final List<_WeightedPoint> _points = [];

  Float32List textureCoordinates(int width, int height) =>
      Float32List.fromList([
        for (final point in _points) ...[point.x * width, point.y * height],
      ]);

  /// Positions are normalized. A fixed lower boundary keeps the heel planted.
  void update(double seconds, double intensity) {
    final strength = intensity.clamp(0.0, 1.0);
    final breath = math.sin(seconds * math.pi * 2 / 4.8);
    final sway = math.sin(seconds * math.pi * 2 / 11.3);
    final legs = math.sin(seconds * math.pi * 2 / 11.3 - .55);
    final hair = math.sin(seconds * math.pi * 2 / 7.7 - .7);
    final wing = math.sin(seconds * math.pi * 2 / 8.9 - 1.1);
    final tail = math.sin(seconds * math.pi * 2 / 10.7 - 1.5);
    final skirt = math.sin(seconds * math.pi * 2 / 8.3 - 1);
    for (int i = 0; i < _points.length; i++) {
      final p = _points[i];
      final anchor = strength * p.free;
      // Torso and shoulders rise together. Local expansion stays below 2%.
      final dx =
          .0045 * sway * (.95 - p.y) +
          .018 * breath * (p.x - .47) * p.chest +
          .0022 * legs * p.leg +
          .004 * hair * p.hair +
          .0045 * wing * p.wings * (p.x < .47 ? -1 : 1) +
          .004 * tail * p.tail +
          .0032 * skirt * p.skirt;
      final dy =
          -.0038 * breath * p.chest -
          .0011 * breath * p.upper +
          .0015 * legs * p.leg +
          .0035 * wing * p.wings +
          .0022 * tail * p.tail;
      positions[2 * i] = p.x + anchor * dx;
      positions[2 * i + 1] = p.y + anchor * dy;
    }
  }
}

double _weight(double x, double y, double cx, double cy, double sx, double sy) {
  final dx = (x - cx) / sx, dy = (y - cy) / sy;
  return math.exp(-.5 * (dx * dx + dy * dy));
}

class _WeightedPoint {
  _WeightedPoint(this.x, this.y)
    : chest = _weight(x, y, .47, .34, .095, .09),
      upper = _weight(x, y, .48, .23, .14, .19),
      leg = _weight(x, y, .47, .69, .055, .12),
      hair =
          _weight(x, y, .29, .43, .11, .18) +
          .65 * _weight(x, y, .62, .36, .065, .15),
      wings =
          _weight(x, y, .17, .43, .11, .18) + _weight(x, y, .83, .4, .11, .15),
      tail = _weight(x, y, .77, .75, .14, .11),
      skirt = _weight(x, y, .48, .84, .24, .11),
      free = _freeWeight(y);

  final double x, y, chest, upper, leg, hair, wings, tail, skirt, free;

  static double _freeWeight(double y) {
    final t = ((y - .86) / .09).clamp(0.0, 1.0);
    return 1 - t * t * (3 - 2 * t);
  }
}
