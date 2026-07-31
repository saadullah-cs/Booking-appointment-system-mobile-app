import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../vision_analyzer_screen.dart';

/// 3D Interactive Human Skeleton Canvas Widget
class Skeleton3DViewer extends StatefulWidget {
  final VisionScenario scenario;
  final String selectedVertebra;
  final Color primaryColor;

  const Skeleton3DViewer({
    super.key,
    required this.scenario,
    required this.selectedVertebra,
    required this.primaryColor,
  });

  @override
  State<Skeleton3DViewer> createState() => _Skeleton3DViewerState();
}

class _Skeleton3DViewerState extends State<Skeleton3DViewer> {
  double _rotationY = 0.0;
  double _rotationX = 0.0;
  double _zoom = 1.0;

  void _resetCamera() {
    setState(() {
      _rotationY = 0.0;
      _rotationX = 0.0;
      _zoom = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _rotationY += details.delta.dx * 0.01;
              _rotationX += details.delta.dy * 0.01;
              _rotationX = _rotationX.clamp(-0.8, 0.8);
            });
          },
          onScaleUpdate: (details) {
            setState(() {
              _zoom = (_zoom * details.scale).clamp(0.6, 2.2);
            });
          },
          child: Container(
            width: w,
            height: h,
            color: const Color(0xFF090D16),
            child: Stack(
              children: [
                // 3D Skeleton Render Canvas
                CustomPaint(
                  size: Size(w, h),
                  painter: _Skeleton3DPainter(
                    scenario: widget.scenario,
                    selectedVertebra: widget.selectedVertebra,
                    color: widget.primaryColor,
                    rotY: _rotationY,
                    rotX: _rotationX,
                    zoom: _zoom,
                  ),
                ),

                // Top Status Badge
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: widget.primaryColor.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.threed_rotation_rounded, color: widget.primaryColor, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '3D SKELETAL MODEL (${widget.selectedVertebra})',
                          style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

                // Touch Instructions & Camera Reset
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '👆 Drag to rotate 360° • Pinch to zoom',
                          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10),
                        ),
                      ),
                      InkWell(
                        onTap: _resetCamera,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            shape: BoxShape.circle,
                            border: Border.all(color: widget.primaryColor.withOpacity(0.4)),
                          ),
                          child: const Icon(Icons.center_focus_strong_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Skeleton3DPainter extends CustomPainter {
  final VisionScenario scenario;
  final String selectedVertebra;
  final Color color;
  final double rotY;
  final double rotX;
  final double zoom;

  _Skeleton3DPainter({
    required this.scenario,
    required this.selectedVertebra,
    required this.color,
    required this.rotY,
    required this.rotX,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final paintLine = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.7)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintBone = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final paintHighlight = Paint()
      ..color = color
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(zoom);

    // Grid matrix floor
    final gridPaint = Paint()..color = color.withOpacity(0.08)..strokeWidth = 1.0;
    for (double i = -150; i <= 150; i += 30) {
      canvas.drawLine(Offset(i, 120), Offset(i * 0.5, 170), gridPaint);
      canvas.drawLine(Offset(-150, 120 + i * 0.15), Offset(150, 120 + i * 0.15), gridPaint);
    }

    // 3D Rotation Math
    Offset project(double x, double y, double z) {
      final radY = rotY;
      final radX = rotX;
      double x1 = x * math.cos(radY) + z * math.sin(radY);
      double z1 = -x * math.sin(radY) + z * math.cos(radY);
      double y2 = y * math.cos(radX) - z1 * math.sin(radX);
      return Offset(x1, y2);
    }

    // Render 3D Skull
    final headPt = project(0, -110, 0);
    canvas.drawCircle(headPt, 18, paintBone);
    canvas.drawCircle(headPt, 19, paintLine);

    // Render Spinal Column Vertebrae (C1 to L5)
    final vertebrae = [
      ('C1', -85.0), ('C2', -75.0), ('C5', -65.0),
      ('T1', -50.0), ('T6', -30.0), ('T12', -10.0),
      ('L1', 5.0), ('L3', 20.0), ('L4', 35.0), ('L5', 50.0),
    ];

    Offset? prevSpine;
    for (final v in vertebrae) {
      final pt = project(0, v.$2, 0);
      final isTarget = selectedVertebra.startsWith(v.$1);
      final p = isTarget ? paintHighlight : paintBone;

      // Draw vertebral spinous process
      canvas.drawCircle(pt, isTarget ? 6.5 : 4.0, p);
      canvas.drawLine(Offset(pt.dx - 10, pt.dy), Offset(pt.dx + 10, pt.dy), p);

      if (prevSpine != null) {
        canvas.drawLine(prevSpine, pt, paintLine);
      }
      prevSpine = pt;

      if (isTarget) {
        final ringPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(pt, 12, ringPaint);
      }
    }

    // Ribcage Arc
    for (double y = -45; y <= -15; y += 10) {
      final l = project(-28, y, 0);
      final r = project(28, y, 0);
      final m = project(0, y, 0);
      canvas.drawLine(l, m, paintLine);
      canvas.drawLine(m, r, paintLine);
    }

    // Pelvis & Hip Horizon
    final sacrumPt = project(0, 65, 0);
    final leftIlium = project(-35, 75, 0);
    final rightIlium = project(35, 75, 0);
    canvas.drawLine(leftIlium, rightIlium, paintBone);
    canvas.drawLine(sacrumPt, leftIlium, paintLine);
    canvas.drawLine(sacrumPt, rightIlium, paintLine);

    // Lower Extremities (Legs & Knees)
    final leftKnee = project(-25, 125, 0);
    final rightKnee = project(25, 125, 0);
    final leftAnkle = project(-22, 170, 0);
    final rightAnkle = project(22, 170, 0);

    canvas.drawLine(leftIlium, leftKnee, paintBone);
    canvas.drawLine(rightIlium, rightKnee, paintBone);
    canvas.drawLine(leftKnee, leftAnkle, paintLine);
    canvas.drawLine(rightKnee, rightAnkle, paintLine);

    canvas.drawCircle(leftKnee, 4, paintBone);
    canvas.drawCircle(rightKnee, 4, paintBone);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Skeleton3DPainter oldDelegate) {
    return oldDelegate.rotY != rotY ||
        oldDelegate.rotX != rotX ||
        oldDelegate.zoom != zoom ||
        oldDelegate.selectedVertebra != selectedVertebra ||
        oldDelegate.scenario != scenario;
  }
}
