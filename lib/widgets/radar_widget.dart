import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

class RadarWidget extends StatefulWidget {
  const RadarWidget({super.key});

  @override
  State<RadarWidget> createState() => _RadarWidgetState();
}

class _RadarWidgetState extends State<RadarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: RadarPainter(_controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class RadarPainter extends CustomPainter {
  final double progress;

  RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 20;

    // Draw concentric circles
    final circlePaint = Paint()
      ..color = AppTheme.accentColor.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, circlePaint);
    }

    // Draw cross lines
    final linePaint = Paint()
      ..color = AppTheme.accentColor.withOpacity(0.3)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      linePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      linePaint,
    );

    // Draw sweeping line (radar effect)
    final sweepAngle = progress * 2 * pi;
    final sweepPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppTheme.accentColor.withOpacity(0.8),
          AppTheme.accentColor.withOpacity(0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(
        center.dx + radius * cos(sweepAngle),
        center.dy + radius * sin(sweepAngle),
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        sweepAngle,
        pi / 6,
        false,
      )
      ..close();

    canvas.drawPath(path, sweepPaint);

    // Draw random blips (simulated stocks)
    final blipPaint = Paint()
      ..color = AppTheme.successColor
      ..style = PaintingStyle.fill;

    final random = Random(42);
    for (int i = 0; i < 15; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final distance = random.nextDouble() * radius;
      final blipX = center.dx + distance * cos(angle);
      final blipY = center.dy + distance * sin(angle);

      // Fade out blips behind the sweep
      final angleDiff = (angle - sweepAngle) % (2 * pi);
      final opacity = angleDiff < pi / 3 ? 1 - angleDiff / (pi / 3) : 0.3;

      blipPaint.color = AppTheme.successColor.withOpacity(opacity);
      canvas.drawCircle(Offset(blipX, blipY), 4, blipPaint);
    }

    // Draw center dot
    final centerPaint = Paint()
      ..color = AppTheme.accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6, centerPaint);

    // Draw outer ring
    final outerRingPaint = Paint()
      ..color = AppTheme.accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, outerRingPaint);
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
