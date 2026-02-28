import 'package:flutter/material.dart';

class HelpSpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final double glowProgress;
  static const double _padding = 6.0;
  static const double _radius = 12.0;
  static const double _glowWidth = 2.5;

  HelpSpotlightPainter({
    required this.targetRect,
    required this.glowProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final inflated = targetRect.inflate(_padding);
    final cutoutRRect =
        RRect.fromRectAndRadius(inflated, const Radius.circular(_radius));

    final scrimPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final scrimPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(cutoutRRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrimPath, scrimPaint);

    final glowOpacity = 0.3 + 0.3 * glowProgress;
    final glowPaint = Paint()
      ..color = const Color(0xFF2F6F6D).withValues(alpha: glowOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _glowWidth;
    canvas.drawRRect(cutoutRRect.inflate(_glowWidth / 2), glowPaint);
  }

  @override
  bool shouldRepaint(HelpSpotlightPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect ||
      oldDelegate.glowProgress != glowProgress;
}
