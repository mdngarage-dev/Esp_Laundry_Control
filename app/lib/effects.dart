import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Drum animasi. Mesin cuci: air + gelembung naik. Dryer: gelombang panas + bara saat gas menyala.
/// active=false atau efek dimatikan di pengaturan -> hanya gambar drum diam.
class RunEffect extends StatefulWidget {
  const RunEffect({super.key, required this.washer, required this.active, this.fill = 0, this.hot = false, this.rpm = 0, this.size = 240, this.child});
  final bool washer, active, hot;
  final double fill, rpm, size; // fill 0..1 (tinggi air)
  final Widget? child;
  @override
  State<RunEffect> createState() => _RunEffectState();
}

class _RunEffectState extends State<RunEffect> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  double _lvl = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => _lvl += (widget.fill - _lvl) * 0.04);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _Painter(_c, p, widget.washer, widget.active, appSettings.effects, () => _lvl, widget.hot, widget.rpm),
          ),
          if (widget.child != null) widget.child!,
        ]),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.t, this.p, this.washer, this.active, this.eff, this.level, this.hot, this.rpm) : super(repaint: t);
  final Animation<double> t;
  final Pal p;
  final bool washer, active, eff, hot;
  final double Function() level;
  final double rpm;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 10;
    final tv = t.value;
    canvas.drawCircle(c, r, Paint()..color = alpha(p.lo, 0.35));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r - 4)));
    if (active && eff) {
      if (washer) {
        _water(canvas, c, r, tv);
      } else if (hot) {
        _heat(canvas, c, r, tv);
      }
      _clothes(canvas, c, r, tv);
    }
    canvas.restore();
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = alpha(p.sub, 0.55));
    canvas.drawCircle(c, r - 8, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = alpha(p.hi, 0.8));
  }

  void _water(Canvas canvas, Offset c, double r, double tv) {
    final lv = level().clamp(0.0, 1.0);
    if (lv < 0.02) return;
    final top = c.dy + r - 2 * r * lv;
    for (int k = 0; k < 2; k++) {
      final path = Path()..moveTo(c.dx - r, c.dy + r);
      for (double x = c.dx - r; x <= c.dx + r; x += 4) {
        path.lineTo(x, top + math.sin(x * 0.05 + tv * 2 * math.pi * (k == 0 ? 2 : 3) + k) * (k == 0 ? 6 : 4));
      }
      path.lineTo(c.dx + r, c.dy + r);
      path.close();
      canvas.drawPath(path, Paint()..color = (k == 0 ? const Color(0xFF3FA9F5) : const Color(0xFF7FD0FF)).withAlpha(k == 0 ? 150 : 90));
    }
    for (int i = 0; i < 16; i++) {
      final ph = (i * 0.618034) % 1.0;
      final x = c.dx - r * 0.8 + 1.6 * r * ((i * 0.37 + 0.11) % 1.0) + math.sin(tv * 2 * math.pi * 3 + i) * 5;
      final span = (c.dy + r - top).clamp(1.0, 2 * r);
      final y = c.dy + r - ((tv * (1 + (i % 3)) + ph) % 1.0) * span;
      canvas.drawCircle(Offset(x, y), 2.5 + (i % 4) * 1.8, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = alpha(Colors.white, 0.7));
    }
  }

  void _heat(Canvas canvas, Offset c, double r, double tv) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
        colors: [const Color(0xAAFF6B1A), const Color(0x00FF6B1A)]).createShader(rect));
    for (int i = 0; i < 6; i++) {
      final x0 = c.dx - r * 0.7 + i * r * 0.28;
      final path = Path();
      for (double y = c.dy + r; y >= c.dy - r; y -= 6) {
        final x = x0 + math.sin(y * 0.05 + tv * 2 * math.pi * 3 + i) * 7;
        if (y == c.dy + r) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = alpha(const Color(0xFFFFB347), 0.35));
    }
    for (int i = 0; i < 12; i++) {
      final y = c.dy + r - ((tv * 2 + i * 0.173) % 1.0) * 2 * r;
      final x = c.dx - r * 0.7 + 1.4 * r * ((i * 0.41 + 0.07) % 1.0) + math.sin(tv * 6 + i) * 6;
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = alpha(const Color(0xFFFFD27A), 0.9));
    }
  }

  void _clothes(Canvas canvas, Offset c, double r, double tv) {
    final turns = 1 + (rpm / 150).round().clamp(0, 6);
    final a = tv * 2 * math.pi * turns;
    for (int i = 0; i < 5; i++) {
      final ang = a + i * 2 * math.pi / 5;
      final rr = r * (0.45 + 0.08 * (i % 2));
      canvas.drawCircle(c + Offset(math.cos(ang) * rr, math.sin(ang) * rr), 9 - (i % 3) * 2, Paint()..color = alpha(p.text, 0.22));
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) => old.active != active || old.eff != eff || old.hot != hot || old.washer != washer || old.rpm != rpm || old.p != p;
}
