import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:companion_poc/dragon_idle_motion.dart';

void main() {
  test(
    'idle motion preserves triangle orientation, feet and texture bounds',
    () {
      final mesh = DragonIdleMesh();
      final rest = List<double>.from(mesh.positions);
      double largestMovement = 0;
      for (int sample = 0; sample <= 240; sample++) {
        mesh.update(sample / 2, 1);
        for (int i = 0; i < mesh.positions.length; i += 2) {
          final x = mesh.positions[i], y = mesh.positions[i + 1];
          expect(x.isFinite && y.isFinite, isTrue);
          expect(x, inInclusiveRange(-.02, 1.02));
          expect(y, inInclusiveRange(-.02, 1.02));
          largestMovement = math.max(
            largestMovement,
            math.sqrt(math.pow(x - rest[i], 2) + math.pow(y - rest[i + 1], 2)),
          );
          if (rest[i + 1] >= .95) {
            expect(x, rest[i]);
            expect(y, rest[i + 1]);
          }
        }
        for (int i = 0; i < mesh.indices.length; i += 3) {
          final a = mesh.indices[i] * 2;
          final b = mesh.indices[i + 1] * 2;
          final c = mesh.indices[i + 2] * 2;
          final p = mesh.positions;
          final cross =
              (p[b] - p[a]) * (p[c + 1] - p[a + 1]) -
              (p[b + 1] - p[a + 1]) * (p[c] - p[a]);
          expect(
            cross,
            greaterThan(.0003),
            reason: 'triangle flipped or collapsed',
          );
        }
      }
      expect(largestMovement, greaterThan(.004));
      expect(largestMovement, lessThan(.02));
      mesh.update(19.4, 0);
      expect(mesh.positions, rest);
    },
  );
}
