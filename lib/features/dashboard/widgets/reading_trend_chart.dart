import 'package:flutter/material.dart';

import '../../../data/mock_dashboard_data.dart';

class ReadingTrendChart extends StatefulWidget {
  const ReadingTrendChart({
    super.key,
    required this.data,
  });

  final List<ReadingTrendPoint> data;

  @override
  State<ReadingTrendChart> createState() => _ReadingTrendChartState();
}

class _ReadingTrendChartState extends State<ReadingTrendChart> {
  int _selectedIndex = 5;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTapDown: (details) {
              final x = details.localPosition.dx;
              final width = constraints.maxWidth;
              final index = ((x / width) * widget.data.length).round();
              final safeIndex = index.clamp(0, widget.data.length - 1);
              setState(() => _selectedIndex = safeIndex);
            },
            child: CustomPaint(
              painter: _TrendPainter(
                data: widget.data,
                selectedIndex: _selectedIndex,
              ),
              size: Size(constraints.maxWidth, 260),
            ),
          );
        },
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.data,
    required this.selectedIndex,
  });

  final List<ReadingTrendPoint> data;
  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final chartPaint = Paint()..color = const Color(0xFFE9EEF8);
    final axisPaint = Paint()..color = const Color(0xFFD6E1F2);
    final linePaint = Paint()
      ..color = const Color(0xFF1C4E9B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x661C4E9B), Color(0x001C4E9B)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final pointPaint = Paint()..color = const Color(0xFF122C5B);
    final selectedPaint = Paint()..color = const Color(0xFFF9A900);
    final labelStyle = TextStyle(
      color: const Color(0xFF6D84A9),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    final padding = const EdgeInsets.fromLTRB(20, 18, 18, 28);
    final chartRect = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.left - padding.right,
      size.height - padding.top - padding.bottom,
    );

    for (var i = 0; i < 5; i++) {
      final y = chartRect.top + (chartRect.height / 4) * i;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        chartPaint,
      );
    }

    final minY = 35.0;
    final maxY = 75.0;
    final points = <Offset>[];

    for (var i = 0; i < data.length; i++) {
      final xRatio = i / (data.length - 1);
      final yRatio = (data[i].value - minY) / (maxY - minY);
      final x = chartRect.left + xRatio * chartRect.width;
      final y = chartRect.bottom - yRatio * chartRect.height;
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, chartRect.bottom)
      ..lineTo(points.first.dx, chartRect.bottom)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < points.length; i++) {
      final isSelected = i == selectedIndex;
      canvas.drawCircle(points[i], isSelected ? 6 : 4, isSelected ? selectedPaint : pointPaint);
    }

    for (var i = 0; i < data.length; i++) {
      final xRatio = i / (data.length - 1);
      final x = chartRect.left + xRatio * chartRect.width;
      final label = data[i].month;
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x - (textPainter.width / 2), chartRect.bottom + 8));
    }

    if (selectedIndex >= 0 && selectedIndex < points.length) {
      final selectedPoint = points[selectedIndex];
      final value = data[selectedIndex].value;
      final label = data[selectedIndex].month;
      final tooltip = TextPainter(
        text: TextSpan(
          text: '$label: ${value.toInt()}%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bubbleRect = Rect.fromCenter(
        center: Offset(selectedPoint.dx, selectedPoint.dy - 22),
        width: tooltip.width + 18,
        height: 28,
      );
      final tooltipPaint = Paint()..color = const Color(0xFF122C5B);
      canvas.drawRRect(RRect.fromRectAndRadius(bubbleRect, const Radius.circular(8)), tooltipPaint);
      tooltip.paint(canvas, Offset(bubbleRect.left + 9, bubbleRect.top + 6));
    }

    canvas.drawLine(
      Offset(chartRect.left, chartRect.bottom),
      Offset(chartRect.right, chartRect.bottom),
      axisPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
