import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class Avatar extends StatefulWidget {
  const Avatar({
    super.key,
    required this.role,
    required this.emotion,
    required this.activity,
    required this.animate,
  });
  final String role;
  final String emotion;
  final String activity;
  final bool animate;
  @override
  State<Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<Avatar> with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  @override
  void initState() {
    super.initState();
    if (widget.animate) pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Avatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !pulse.isAnimating) pulse.repeat(reverse: true);
    if (!widget.animate) pulse.stop();
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${widget.role == 'xing' ? '小星' : '小月'}，${widget.emotion}，${widget.activity}，占位形象',
    child: AnimatedBuilder(
      animation: pulse,
      builder: (_, _) => Transform.translate(
        offset: Offset(
          0,
          widget.animate ? math.sin(pulse.value * math.pi) * 3 : 0,
        ),
        child: CustomPaint(
          painter: FacePainter(widget.role, widget.emotion, widget.activity),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class FacePainter extends CustomPainter {
  FacePainter(this.role, this.emotion, this.activity);
  final String role, emotion, activity;
  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s / 160);
    final purple = role == 'xing'
        ? const Color(0xFF7865B9)
        : const Color(0xFF367F7B);
    canvas.drawCircle(
      const Offset(80, 80),
      69,
      Paint()..color = purple.withValues(alpha: .12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(43, 104, 74, 48),
        const Radius.circular(24),
      ),
      Paint()..color = purple,
    );
    canvas.drawOval(
      const Rect.fromLTWH(32, 18, 96, 107),
      Paint()..color = purple,
    );
    canvas.drawOval(
      const Rect.fromLTWH(43, 39, 74, 73),
      Paint()..color = const Color(0xFFFFE5D7),
    );
    final hair = Path()
      ..moveTo(36, 56)
      ..quadraticBezierTo(50, 1, 108, 34)
      ..lineTo(121, 63)
      ..lineTo(95, 46)
      ..lineTo(77, 60)
      ..lineTo(72, 43)
      ..close();
    canvas.drawPath(hair, Paint()..color = purple);
    final line = Paint()
      ..color = const Color(0xFF393044)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final x in [64.0, 96.0]) {
      if (emotion == '开心') {
        canvas.drawArc(
          Rect.fromCenter(center: Offset(x, 73), width: 13, height: 10),
          math.pi,
          math.pi,
          false,
          line,
        );
      } else {
        canvas.drawLine(Offset(x, 71), Offset(x, 77), line);
      }
    }
    if (activity == '说话') {
      canvas.drawOval(
        const Rect.fromLTWH(75, 88, 10, 12),
        Paint()..color = const Color(0xFFAD6174),
      );
    } else if (emotion == '难过') {
      canvas.drawArc(
        const Rect.fromLTWH(72, 92, 16, 10),
        math.pi,
        math.pi,
        false,
        line,
      );
    } else if (emotion == '疑惑') {
      canvas.drawLine(const Offset(75, 94), const Offset(85, 92), line);
    } else {
      canvas.drawArc(
        const Rect.fromLTWH(71, 85, 18, 12),
        0,
        math.pi,
        false,
        line,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FacePainter old) =>
      role != old.role || emotion != old.emotion || activity != old.activity;
}
