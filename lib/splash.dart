import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core.dart';

/// Welcome animation: coffee pours into a cup, light steam rises, then [next] opens.
class SplashGate extends StatefulWidget {
  final Widget next;
  const SplashGate({super.key, required this.next});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3600))
    ..forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  bool _done = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _done
          ? KeyedSubtree(key: const ValueKey('next'), child: widget.next)
          : Scaffold(
              key: const ValueKey('splash'),
              backgroundColor: cCream,
              body: SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    SizedBox(
                      width: 220,
                      height: 260,
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (_, __) => CustomPaint(
                            painter: _CupPainter(_c.value)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedBuilder(
                      animation: _c,
                      builder: (_, __) {
                        final t = ((_c.value - 0.55) / 0.3).clamp(0.0, 1.0);
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - t)),
                            child: const Text('BONNAYA',
                                style: TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 6,
                                    color: cInk)),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    AnimatedBuilder(
                      animation: _c,
                      builder: (_, __) => Opacity(
                        opacity: ((_c.value - 0.7) / 0.25).clamp(0.0, 1.0),
                        child: const Text('أهلًا بيك في بنايه',
                            style: TextStyle(fontSize: 16, color: cMuted)),
                      ),
                    ),
                    const Spacer(flex: 4),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CupPainter extends CustomPainter {
  final double t; // 0..1 over the whole animation
  _CupPainter(this.t);

  double _seg(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2;
    // cup geometry
    final top = s.height * 0.50;
    final bottom = s.height * 0.92;
    const topHalf = 62.0, botHalf = 44.0;
    final cup = Path()
      ..moveTo(cx - topHalf, top)
      ..lineTo(cx + topHalf, top)
      ..lineTo(cx + botHalf, bottom)
      ..quadraticBezierTo(cx, bottom + 10, cx - botHalf, bottom)
      ..close();

    // saucer
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, bottom + 8), width: 170, height: 18),
        Paint()..color = cHair);

    // handle
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx + topHalf - 4, top + 44), width: 52, height: 52),
        -math.pi / 2,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..color = cBrand);

    // coffee level fills during pour (0.10 .. 0.55)
    final fill = Curves.easeOut.transform(_seg(0.10, 0.55));
    canvas.save();
    canvas.clipPath(cup);
    final level = bottom - (bottom - top - 8) * fill;
    canvas.drawRect(Rect.fromLTRB(0, level, s.width, bottom + 12),
        Paint()..color = cInk);
    // little wave on the surface
    if (fill > 0 && fill < 1) {
      final wave = Path()..moveTo(cx - topHalf, level);
      for (double x = -topHalf; x <= topHalf; x += 4) {
        wave.lineTo(cx + x, level + math.sin(x / 9 + t * 40) * 2.2);
      }
      wave.lineTo(cx + topHalf, level + 6);
      wave.lineTo(cx - topHalf, level + 6);
      wave.close();
      canvas.drawPath(wave, Paint()..color = cCopper);
    }
    canvas.restore();

    // cup body (drawn as outline + soft fill for the empty part)
    canvas.drawPath(
        cup,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.round
          ..color = cBrand);

    // pour stream from above
    final pourOn = _seg(0.05, 0.12);
    final pourOff = _seg(0.52, 0.60);
    final stream = pourOn * (1 - pourOff);
    if (stream > 0) {
      final w = 7.0 * stream;
      final startY = 0.0;
      final endY = level.clamp(top, bottom);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(cx - w / 2, startY, cx + w / 2, endY),
              Radius.circular(w)),
          Paint()..color = cInk);
      // spout
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(cx, 4), width: 34, height: 10),
              const Radius.circular(5)),
          Paint()..color = cBrand);
    }

    // steam: appears after the pour, gentle, looping wisps
    final steamIn = _seg(0.55, 0.75);
    if (steamIn > 0) {
      for (int i = 0; i < 3; i++) {
        final x0 = cx - 26 + i * 26.0;
        final phase = (t * 2.2 + i * 0.33) % 1.0;
        final y = top - 8 - phase * 78;
        final a = (math.sin(phase * math.pi)) * 0.55 * steamIn;
        final p = Path()..moveTo(x0, y);
        for (double k = 0; k <= 36; k += 3) {
          p.lineTo(x0 + math.sin((k + phase * 30) / 7 + i) * 6, y - k);
        }
        canvas.drawPath(
            p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 5
              ..color = cMuted.withOpacity(a.clamp(0.0, 1.0)));
      }
    }
  }

  @override
  bool shouldRepaint(_CupPainter old) => old.t != t;
}
