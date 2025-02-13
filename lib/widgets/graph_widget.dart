import 'package:flutter/material.dart';
import 'dart:math';

class GraphWidget extends StatelessWidget {
  final List<double> data;
  const GraphWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 200),
      painter: _GraphPainter(data),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<double> data;
  _GraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (data.isEmpty) return;
    double maxData = data.reduce(max);
    double minData = data.reduce(min);
    double range = maxData - minData;
    if (range == 0) range = 1;

    final path = Path();
    final dx = size.width / (data.length - 1);
    for (int i = 0; i < data.length; i++) {
      double x = i * dx;
      double y = size.height - ((data[i] - minData) / range * size.height);
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) => oldDelegate.data != data;
}
