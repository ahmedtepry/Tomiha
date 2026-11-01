import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'core.dart';

/// The cups the owner can pick for the welcome screen.
const welcomeCups = <String, String>{
  'finjan': 'الفنجان المصري',
  'coffee': 'قهوة بالرغوة',
  'tea': 'شاي أحمر بالنعناع',
  'latte': 'لاتيه بالطبقات',
  'iced': 'آيس لاتيه',
};

const defaultQuotes = <String>[
  'القهوة مش مجرد مشروب، دي لحظة هدوء في نص الزحمة.',
  'أول رشفة بتظبّط اليوم كله.',
  'يوم من غير قهوة زي حكاية من غير نهاية.',
  'الصباح الحلو بيبدأ بريحة بن.',
  'على مهلك، القهوة بتحب اللي بيستنّاها.',
  'فنجان قهوة وكلمة طيبة، والدنيا تتعدل.',
];

class WelcomeConfig {
  final String cup;
  final bool showQuote;
  final List<String> quotes;
  const WelcomeConfig(this.cup, this.showQuote, this.quotes);

  static WelcomeConfig fromJson(dynamic v) {
    var cup = 'finjan';
    var show = true;
    var quotes = List<String>.of(defaultQuotes);
    if (v is Map) {
      final c = v['cup'];
      if (c is String && welcomeCups.containsKey(c)) cup = c;
      show = v['show_quote'] != false;
      final q = v['quotes'];
      if (q is List) {
        final l = q.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
        if (l.isNotEmpty) quotes = l;
      }
    }
    return WelcomeConfig(cup, show, quotes);
  }

  static Future<WelcomeConfig> load() async {
    try {
      final row = await sb
          .from('app_settings')
          .select('value')
          .eq('key', 'welcome')
          .maybeSingle()
          .timeout(const Duration(milliseconds: 1500));
      return fromJson(row?['value']);
    } catch (_) {
      return fromJson(null); // offline or slow: use the default look
    }
  }
}

// ---------------------------------------------------------------- screen

/// Plays the cup animation, then calls [onDone]. Tapping skips it.
class WelcomeScreen extends StatefulWidget {
  final String cup;
  final String? quote;
  final VoidCallback onDone;
  const WelcomeScreen(
      {super.key, required this.cup, this.quote, required this.onDone});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  static const _total = 4.3;
  bool _fired = false;
  late final AnimationController _c = AnimationController(
      vsync: this, duration: Duration(milliseconds: (_total * 1000).round()))
    ..forward().whenComplete(_finish);

  void _finish() {
    if (_fired) return;
    _fired = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Scaffold(
        backgroundColor: cCream,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 0.35),
              radius: 0.95,
              colors: [Color(0xFF3D281B), cCream],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 28),
                const Text('BONNAYA',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                        color: cBrand)),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: AspectRatio(
                        aspectRatio: 0.8,
                        child: AnimatedBuilder(
                          animation: _c,
                          builder: (_, __) => CustomPaint(
                              painter: CupPainter(widget.cup, _c.value * _total)),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 76,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, __) {
                        final o = widget.quote == null
                            ? 0.0
                            : _sm((_c.value * _total - 0.7) / 0.8);
                        return Opacity(
                          opacity: o,
                          child: Text(widget.quote ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(
                                  fontSize: 14, height: 1.7, color: cMuted)),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Loads the owner's settings, plays the welcome screen once, then shows [next].
class SplashGate extends StatefulWidget {
  final Widget next;
  const SplashGate({super.key, required this.next});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  WelcomeConfig? _cfg;
  String? _quote;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WelcomeConfig.load().then((c) {
      if (!mounted) return;
      setState(() {
        _cfg = c;
        _quote = c.showQuote ? c.quotes[math.Random().nextInt(c.quotes.length)] : null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_done) {
      child = KeyedSubtree(key: const ValueKey('next'), child: widget.next);
    } else if (_cfg == null) {
      child = const Scaffold(key: ValueKey('wait'), backgroundColor: cCream);
    } else {
      child = WelcomeScreen(
        key: const ValueKey('welcome'),
        cup: _cfg!.cup,
        quote: _quote,
        onDone: () {
          if (mounted) setState(() => _done = true);
        },
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      transitionBuilder: (w, a) {
        if (w.key == const ValueKey('next')) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
                .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: FadeTransition(opacity: a, child: w),
          );
        }
        return FadeTransition(opacity: a, child: w);
      },
      child: child,
    );
  }
}

// ---------------------------------------------------------------- painter

double _sm(double x) {
  x = x < 0 ? 0 : (x > 1 ? 1 : x);
  return x * x * (3 - 2 * x);
}

double _clamp(double x, double a, double b) => x < a ? a : (x > b ? b : x);

double _fr(num i) {
  final v = math.sin(i * 127.1 + 311.7) * 43758.5453;
  return v - v.floorToDouble();
}

Color _k(int r, int g, int b, [double a = 1]) => Color.fromRGBO(r, g, b, a);

class _Cup {
  final double cx, top, bot, tw, bw;
  const _Cup(this.cx, this.top, this.bot, this.tw, this.bw);
}

/// Draws a cup that fills by itself, then steams. [t] is seconds from the start.
class CupPainter extends CustomPainter {
  final String variant;
  final double t;
  const CupPainter(this.variant, this.t);

  static const _w = 400.0, _h = 500.0;
  static const _f0 = 0.4, _f1 = 2.3, _steamAt = 2.15;

  @override
  bool shouldRepaint(CupPainter old) => old.t != t || old.variant != variant;

  @override
  void paint(Canvas c, Size size) {
    final s = math.min(size.width / _w, size.height / _h);
    c.save();
    c.translate((size.width - _w * s) / 2, (size.height - _h * s) / 2);
    c.scale(s);
    final p = _sm((t - _f0) / (_f1 - _f0));
    switch (variant) {
      case 'coffee':
        _coffee(c, p);
        break;
      case 'tea':
        _tea(c, p);
        break;
      case 'latte':
        _latte(c, p);
        break;
      case 'iced':
        _iced(c, p);
        break;
      default:
        _finjan(c, p);
    }
    c.restore();
  }

  // ---- shared helpers
  double _wobble(double p) {
    final settle = t > _f1 ? math.exp(-(t - _f1) * 2.6) : 1.0;
    return (0.7 + 1.9 * settle) * (p > 0.02 ? 1.0 : 0.0);
  }

  double _wv(double x, double amp) =>
      math.sin(x * 0.075 + t * 7.5) * amp + math.sin(x * 0.14 - t * 5.2) * amp * 0.5;

  double _half(_Cup k, double y) {
    final f = _clamp((k.bot - y) / (k.bot - k.top), 0, 1);
    return (k.bw + (k.tw - k.bw) * f) / 2;
  }

  Path _trap(_Cup k, double r) {
    final p = Path()
      ..moveTo(k.cx - k.tw / 2, k.top)
      ..lineTo(k.cx + k.tw / 2, k.top)
      ..lineTo(k.cx + k.bw / 2, k.bot - r)
      ..quadraticBezierTo(k.cx + k.bw / 2 - 1, k.bot, k.cx + k.bw / 2 - r, k.bot)
      ..lineTo(k.cx - k.bw / 2 + r, k.bot)
      ..quadraticBezierTo(k.cx - k.bw / 2 + 1, k.bot, k.cx - k.bw / 2, k.bot - r)
      ..close();
    return p;
  }

  Path _surface(_Cup k, double ly, double amp) {
    final hw = _half(k, ly) + 8;
    var x = k.cx - hw;
    final p = Path()..moveTo(x, ly + _wv(x, amp));
    for (; x <= k.cx + hw; x += 4) {
      p.lineTo(x, ly + _wv(x, amp));
    }
    p
      ..lineTo(k.cx + hw, k.bot + 20)
      ..lineTo(k.cx - hw, k.bot + 20)
      ..close();
    return p;
  }

  void _surfaceLine(Canvas c, _Cup k, double ly, double amp, Color col, double w) {
    final hw = _half(k, ly);
    var x = k.cx - hw;
    final p = Path()..moveTo(x, ly + _wv(x, amp));
    for (; x <= k.cx + hw; x += 4) {
      p.lineTo(x, ly + _wv(x, amp));
    }
    c.drawPath(
        p,
        Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeJoin = StrokeJoin.round);
  }

  Paint _lin(double x0, double y0, double x1, double y1, List<Color> cols,
      [List<double>? stops]) {
    return Paint()
      ..shader = ui.Gradient.linear(Offset(x0, y0), Offset(x1, y1), cols, stops);
  }

  Paint _stroke(Color col, double w) => Paint()
    ..color = col
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _ground(Canvas c, double cx, double bot, double rx) {
    c.save();
    c.translate(cx, bot + 10);
    c.scale(1, 0.16);
    c.drawCircle(
        Offset.zero,
        rx,
        Paint()
          ..shader = ui.Gradient.radial(
              Offset.zero, rx, [_k(20, 8, 0, .6), _k(20, 8, 0, 0)]));
    c.restore();
  }

  void _light(Canvas c, _Cup k, double ly, double s, int r, int g, int b) {
    c.drawRect(
        Rect.fromLTWH(0, ly - 10, _w, 260),
        _lin(k.cx - k.tw / 2, 0, k.cx + k.tw / 2, 0,
            [_k(r, g, b, s), _k(r, g, b, 0), _k(r, g, b, 0), _k(r, g, b, s * .5)],
            [0, .35, .85, 1]));
  }

  void _bubbles(Canvas c, _Cup k, double ly, int n, Color col) {
    final p = Paint()..color = col;
    for (var i = 0; i < n; i++) {
      final sp = 18 + _fr(i) * 26, off = _fr(i + 50) * 200;
      final y0 = k.bot - 14 - ((t * sp + off) % (k.bot - ly));
      if (y0 < ly + 4) continue;
      final x = k.cx + (_fr(i + 9) - 0.5) * (_half(k, y0) * 1.5) + math.sin(t * 3 + i) * 2;
      c.drawCircle(Offset(x, y0), 0.8 + _fr(i + 2) * 1.5, p);
    }
  }

  void _foamBubbles(Canvas c, _Cup k, double ly, int n, int seed, double a,
      Color edge, Color fill) {
    for (var i = 0; i < n; i++) {
      final bx = k.cx + (_fr(i + seed) - 0.5) * _half(k, ly) * 1.8;
      final by = ly + 1.5 + _fr(i + seed + 6) * 3;
      final r = 1 + _fr(i + 4) * 2.4;
      final rect = Rect.fromCircle(center: Offset(bx, by), radius: r);
      c.drawArc(rect, math.pi, math.pi, true, Paint()..color = fill.withOpacity(fill.opacity * a));
      c.drawArc(rect, math.pi, math.pi, false, _stroke(edge.withOpacity(edge.opacity * a), 1));
    }
  }

  void _steam(Canvas c, _Cup k, double ly) {
    if (t < _steamAt) return;
    for (var i = 0; i < 8; i++) {
      var age = t - (_steamAt + i * 0.2);
      if (age < 0) continue;
      const life = 2.5;
      age = age % life;
      final u = age / life;
      final hw = _half(k, ly) * 0.7;
      final x = k.cx + (_fr(i + 3) - 0.5) * hw * 1.5 + math.sin(age * 2.2 + i * 1.7) * (8 + 10 * u);
      final y = ly - 8 - u * 92;
      final r = 15 + u * 20;
      final a = math.sin(math.min(1.0, u) * math.pi) * 0.5 * _sm((t - _steamAt) / 0.5);
      c.drawCircle(
          Offset(x, y),
          r,
          Paint()
            ..shader = ui.Gradient.radial(Offset(x, y), r, [
              _k(255, 255, 255, a),
              _k(255, 255, 255, a * .5),
              _k(255, 255, 255, 0)
            ], [0, .5, 1]));
    }
  }

  void _glassFront(Canvas c, _Cup k, Color col) {
    c.save();
    c.clipPath(_trap(k, 10));
    c.drawRect(Rect.fromLTWH(0, k.bot - 12, _w, 24), Paint()..color = _k(255, 255, 255, .2));
    c.drawLine(Offset(0, k.bot - 12), Offset(_w, k.bot - 12), _stroke(_k(255, 255, 255, .28), 1.5));
    c.restore();
    c.drawPath(_trap(k, 10), _stroke(col, 4));
    c.drawLine(Offset(k.cx - k.tw / 2 + 11, k.top + 14),
        Offset(k.cx - k.bw / 2 + 10, k.bot - 22), _stroke(_k(255, 255, 255, .45), 3.2));
    c.drawLine(Offset(k.cx + k.tw / 2 - 12, k.top + 30),
        Offset(k.cx + k.bw / 2 - 10, k.bot - 40), _stroke(_k(255, 255, 255, .18), 2));
    c.drawLine(Offset(k.cx - k.tw / 2 - 3, k.top), Offset(k.cx + k.tw / 2 + 3, k.top),
        _stroke(const Color(0xFFD9A04A), 3.4));
  }

  // ---- 1) coffee with foam
  void _coffee(Canvas c, double p) {
    const k = _Cup(200, 170, 400, 158, 116);
    final ly = k.bot - 8 - p * (k.bot - k.top - 16), amp = _wobble(p);
    _ground(c, k.cx, k.bot, 150);
    c.drawPath(_trap(k, 10), Paint()..color = _k(255, 255, 255, .1));
    c.save();
    c.clipPath(_trap(k, 10));
    c.drawPath(_surface(k, ly, amp),
        _lin(0, ly, 0, k.bot, const [Color(0xFF6A3D22), Color(0xFF3A1E0F), Color(0xFF1E0F07)], [0, .5, 1]));
    _light(c, k, ly, .22, 255, 160, 90);
    _bubbles(c, k, ly, 18, _k(255, 230, 190, .35));
    final cr = _sm((p - 0.82) / 0.18) * 13;
    if (cr > 0.5) {
      c.save();
      c.clipPath(_surface(k, ly, amp));
      c.drawRect(Rect.fromLTWH(0, ly - 6, _w, cr + 10),
          _lin(0, ly, 0, ly + cr, [const Color(0xFFD9A06A), const Color(0xFFB27442), _k(120, 70, 36, 0)], [0, .5, 1]));
      c.restore();
      _foamBubbles(c, k, ly, 26, 0, 1, _k(255, 236, 200, .7), _k(255, 236, 200, .25));
    }
    _surfaceLine(c, k, ly, amp, _k(255, 215, 170, .8), 2.2);
    c.restore();
    _glassFront(c, k, const Color(0xFF8E7762));
    _steam(c, k, ly);
  }

  // ---- 2) red tea with mint
  void _tea(Canvas c, double p) {
    const k = _Cup(200, 200, 400, 140, 104);
    final ly = k.bot - 8 - p * (k.bot - k.top - 16), amp = _wobble(p);
    _ground(c, k.cx, k.bot, 140);
    c.drawPath(_trap(k, 10), Paint()..color = _k(255, 255, 255, .1));
    c.save();
    c.clipPath(_trap(k, 10));
    c.drawPath(_surface(k, ly, amp),
        _lin(0, ly, 0, k.bot, const [Color(0xFFB4501B), Color(0xFF8C3A12), Color(0xFF4A1A06)], [0, .55, 1]));
    _light(c, k, ly, .42, 255, 150, 80);
    c.drawRect(
        Rect.fromLTWH(k.cx - 130, k.bot - 90, 260, 100),
        Paint()
          ..shader = ui.Gradient.radial(Offset(k.cx, k.bot - 6), 80,
              [_k(255, 150, 70, .5), _k(255, 150, 70, 0)]));
    _bubbles(c, k, ly, 10, _k(255, 205, 150, .3));
    _surfaceLine(c, k, ly, amp, _k(240, 160, 100, .85), 2.6);
    if (p > 0.55) {
      final m = _sm((p - 0.55) / 0.3);
      const leaves = [
        [-26.0, 0.0, -.4],
        [-6.0, -4.0, .2],
        [16.0, 0.0, .7]
      ];
      for (var i = 0; i < leaves.length; i++) {
        final l = leaves[i];
        c.save();
        c.translate(k.cx + l[0], ly + l[1] - 2 + math.sin(t * 2 + i) * 1.2);
        c.rotate(l[2]);
        c.drawOval(Rect.fromCenter(center: Offset.zero, width: 30, height: 16),
            _lin(0, -9, 0, 9, [_k(127, 176, 90, m), _k(63, 108, 46, m)]));
        c.drawLine(const Offset(-12, 0), const Offset(12, 0), _stroke(_k(255, 255, 255, .35 * m), 1.2));
        c.restore();
      }
    }
    c.restore();
    _glassFront(c, k, const Color(0xFF8E7762));
    _steam(c, k, ly);
  }

  // ---- 3) layered latte
  void _latte(Canvas c, double p) {
    const k = _Cup(200, 150, 410, 130, 100);
    final full = k.bot - 8 - (k.top + 14);
    final ly = k.bot - 8 - p * full, amp = _wobble(p) * 0.8;
    _ground(c, k.cx, k.bot, 130);
    c.drawPath(_trap(k, 10), Paint()..color = _k(255, 255, 255, .12));
    c.save();
    c.clipPath(_trap(k, 10));
    final yM = k.bot - 8 - full * 0.40, yC = k.bot - 8 - full * 0.76;
    c.save();
    c.clipPath(_surface(k, ly, amp));
    c.drawRect(Rect.fromLTWH(0, yM - 20, _w, 500), Paint()..color = const Color(0xFFFFF6E6));
    c.drawRect(Rect.fromLTWH(0, yM - 34, _w, 40),
        _lin(0, yM - 34, 0, yM + 6, const [Color(0xFF5A3219), Color(0xFFFFF6E6)]));
    c.drawRect(Rect.fromLTWH(0, yC, _w, yM - 34 - yC),
        _lin(0, yC, 0, yM - 34, const [Color(0xFF7A4528), Color(0xFF4A2A15)]));
    c.drawRect(Rect.fromLTWH(0, yC - 26, _w, 34),
        _lin(0, yC - 22, 0, yC + 4, const [Color(0xFFF4E1BF), Color(0xFF7A4528)]));
    c.drawRect(Rect.fromLTWH(0, 0, _w, yC - 12), Paint()..color = const Color(0xFFF4E1BF));
    _light(c, k, ly, .18, 255, 200, 140);
    c.restore();
    _surfaceLine(c, k, ly, amp, _k(255, 246, 225, .9), 2.4);
    if (p > 0.88) {
      final fb = _sm((p - 0.88) / 0.12);
      _foamBubbles(c, k, ly, 22, 11, fb, _k(190, 150, 100, .7), _k(255, 255, 255, .4));
    }
    c.restore();
    final dome = _sm((p - 0.94) / 0.06) * 9;
    if (dome > 0.5) {
      c.drawArc(Rect.fromCenter(center: Offset(k.cx, k.top), width: k.tw - 8, height: dome * 2),
          math.pi, math.pi, true,
          _lin(0, k.top - dome, 0, k.top + 4, const [Color(0xFFFFF8EA), Color(0xFFF4E1BF)]));
    }
    _glassFront(c, k, const Color(0xFF8E7762));
    _steam(c, k, math.min(ly, k.top) - dome);
  }

  // ---- 4) Egyptian finjan (cut open so the coffee shows)
  void _finjan(Canvas c, double p) {
    const k = _Cup(200, 230, 380, 150, 90);
    const wall = 11.0;
    const cav = _Cup(200, 236, 366, 150 - 2 * wall, 90 - 2 * wall);
    final full = cav.bot - cav.top - 10;
    final ly = cav.bot - p * full, amp = _wobble(p) * 0.8;
    _ground(c, k.cx, k.bot + 18, 150);
    // saucer
    final saucer = Rect.fromCenter(center: Offset(k.cx, k.bot + 14), width: 236, height: 34);
    c.drawOval(saucer, _lin(0, k.bot + 4, 0, k.bot + 26, const [Color(0xFFFFFFFF), Color(0xFFCFC7BA)]));
    c.drawOval(saucer, _stroke(const Color(0xFFD9A04A), 3));
    c.drawOval(Rect.fromCenter(center: Offset(k.cx, k.bot + 12), width: 132, height: 16),
        Paint()..color = _k(60, 40, 20, .18));
    // handle
    final hx = k.cx + k.tw / 2;
    Path handle(double dy) => Path()
      ..moveTo(hx - 12, k.top + 40 + dy)
      ..cubicTo(hx + 48, k.top + 30 + dy, hx + 40, k.top + 110 + dy, k.cx + k.bw / 2 + 2, k.top + 112 + dy);
    c.drawPath(handle(0), _stroke(const Color(0xFFE9E3D8), 16));
    c.drawPath(handle(-7), _stroke(const Color(0xFFD9A04A), 3));
    // porcelain body
    final body = _trap(k, 26);
    c.drawPath(
        body,
        _lin(k.cx - k.tw / 2, 0, k.cx + k.tw / 2, 0,
            const [Color(0xFFD8D0C3), Color(0xFFFFFFFF), Color(0xFFECE6DA), Color(0xFFBDB4A5)],
            [0, .2, .7, 1]));
    c.save();
    c.clipPath(body);
    c.drawRect(Rect.fromLTWH(0, k.top + 6, _w, 12), Paint()..color = const Color(0xFF1F4E8C));
    c.drawRect(Rect.fromLTWH(0, k.bot - 30, _w, 8), Paint()..color = const Color(0xFF1F4E8C));
    c.drawRect(Rect.fromLTWH(0, k.top + 19, _w, 2.5), Paint()..color = const Color(0xFFD9A04A));
    c.drawRect(Rect.fromLTWH(0, k.bot - 33, _w, 2.5), Paint()..color = const Color(0xFFD9A04A));
    for (var i = 0; i < 9; i++) {
      final px = k.cx - k.tw / 2 + 14 + i * ((k.tw - 28) / 8);
      c.drawPath(
          Path()
            ..moveTo(px, k.top + 60)
            ..lineTo(px + 6, k.top + 70)
            ..lineTo(px, k.top + 80)
            ..lineTo(px - 6, k.top + 70)
            ..close(),
          Paint()..color = const Color(0xFFD9A04A));
    }
    c.restore();
    // cavity with the coffee
    c.save();
    final cavPath = _trap(cav, 16);
    c.drawPath(cavPath, Paint()..color = const Color(0xFFF4EFE6));
    c.clipPath(cavPath);
    c.drawRect(
        Rect.fromLTWH(0, 0, _w, 500),
        _lin(cav.cx - cav.tw / 2, 0, cav.cx + cav.tw / 2, 0,
            [_k(0, 0, 0, .14), _k(0, 0, 0, 0), _k(0, 0, 0, .18)], [0, .25, 1]));
    c.drawPath(_surface(cav, ly, amp),
        _lin(0, ly, 0, cav.bot, const [Color(0xFF5A311B), Color(0xFF1E0F07)]));
    _bubbles(c, cav, ly, 10, _k(255, 230, 190, .35));
    final fm = _sm((p - 0.8) / 0.2) * 9;
    if (fm > 0.5) {
      c.save();
      c.clipPath(_surface(cav, ly, amp));
      c.drawRect(Rect.fromLTWH(0, ly - 4, _w, fm + 8),
          _lin(0, ly, 0, ly + fm, [const Color(0xFFC98E58), _k(150, 95, 52, 0)]));
      c.restore();
      for (var j = 0; j < 22; j++) {
        final bx = cav.cx + (_fr(j + 30) - 0.5) * _half(cav, ly) * 1.8;
        final by = ly + 1 + _fr(j + 31) * 3;
        c.drawArc(Rect.fromCircle(center: Offset(bx, by), radius: 1 + _fr(j + 32) * 2),
            math.pi, math.pi, false, _stroke(_k(255, 230, 190, .75), 1));
      }
    }
    if (p > 0.6) {
      final m = _sm((p - 0.6) / 0.2);
      c.save();
      c.translate(cav.cx + 34, ly - 1 + math.sin(t * 2));
      c.rotate(.5);
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: 20, height: 10.4),
          _lin(0, -5, 0, 5, [_k(182, 200, 138, m), _k(111, 138, 74, m)]));
      c.drawLine(const Offset(-9, 0), const Offset(9, 0), _stroke(_k(60, 80, 30, .5 * m), 1));
      c.restore();
    }
    c.restore();
    // rim
    c.drawLine(Offset(k.cx - k.tw / 2 - 1, k.top), Offset(k.cx + k.tw / 2 + 1, k.top),
        _stroke(const Color(0xFFD9A04A), 4));
    c.drawPath(body, _stroke(_k(60, 40, 20, .35), 1.6));
    _steam(c, cav, ly);
  }

  // ---- 5) iced latte
  void _iced(Canvas c, double p) {
    const k = _Cup(200, 130, 410, 136, 106);
    final full = k.bot - 8 - (k.top + 16);
    final ly = k.bot - 8 - p * full, amp = _wobble(p) * 0.7;
    _ground(c, k.cx, k.bot, 130);
    c.drawPath(_trap(k, 10), Paint()..color = _k(255, 255, 255, .14));
    c.save();
    c.clipPath(_trap(k, 10));
    c.save();
    c.clipPath(_surface(k, ly, amp));
    c.drawRect(Rect.fromLTWH(0, 0, _w, 500),
        _lin(0, ly, 0, k.bot, const [Color(0xFFC9A27A), Color(0xFF8A5F3C)]));
    for (var i = 0; i < 7; i++) {
      final yy = k.bot - ((t * 38 + i * 46) % 300);
      final xo = math.sin(t * 1.6 + i * 1.4) * 24;
      c.save();
      c.translate(k.cx + xo, yy);
      c.rotate(math.sin(t + i) * .4);
      c.drawOval(
          Rect.fromCenter(
              center: Offset.zero,
              width: 2 * (50 + 10 * math.sin(i)),
              height: 2 * (13 + 4 * math.cos(i))),
          Paint()..color = i % 2 == 1 ? _k(70, 36, 18, .38) : _k(255, 240, 215, .34));
      c.restore();
    }
    _light(c, k, ly, .2, 255, 200, 140);
    c.restore();
    if (p > 0.18) {
      final m = _sm((p - 0.18) / 0.5);
      const cubes = [
        [-30.0, 34.0, .3, 36.0],
        [8.0, 52.0, -.2, 40.0],
        [34.0, 26.0, .5, 34.0],
        [-6.0, 100.0, -.5, 38.0]
      ];
      for (var i = 0; i < cubes.length; i++) {
        final q = cubes[i];
        final by = ly + q[1] + math.sin(t * 1.7 + i * 1.3) * 2.4 - (1 - m) * 40;
        final bx = k.cx + q[0] + math.sin(t * 1.1 + i) * 2;
        final s = q[3], a = 0.9 * m + .1;
        c.save();
        c.translate(bx, by);
        c.rotate(q[2] + math.sin(t * 1.3 + i) * .06);
        final rr = RRect.fromRectAndRadius(
            Rect.fromLTWH(-s / 2, -s / 2, s, s), const Radius.circular(7));
        c.drawRRect(
            rr,
            _lin(-s / 2, -s / 2, s / 2, s / 2, [
              _k(255, 255, 255, .85 * a),
              _k(215, 235, 245, .55 * a),
              _k(180, 210, 230, .5 * a)
            ], [0, .5, 1]));
        c.drawRRect(rr, _stroke(_k(255, 255, 255, .8 * a), 1.6));
        c.drawLine(Offset(-s / 2 + 6, -s / 2 + 5), Offset(-s / 2 + 6, s / 2 - 9),
            _stroke(_k(255, 255, 255, .7 * a), 2));
        c.restore();
      }
    }
    c.restore();
    // straw
    final a0 = Offset(k.cx + 32, k.bot - 24), a1 = Offset(k.cx + 58, k.top - 58);
    c.drawLine(a0, a1, _stroke(const Color(0xFFD9894A), 11));
    for (var i = 0; i < 12; i++) {
      final u0 = i / 12 + 0.02, u1 = u0 + 0.04;
      c.drawLine(Offset.lerp(a0, a1, u0)!, Offset.lerp(a0, a1, u1)!,
          _stroke(const Color(0xFFFFE0BC), 11)..strokeCap = StrokeCap.butt);
    }
    c.drawLine(a0.translate(-2, 0), a1.translate(-2, 0), _stroke(_k(255, 255, 255, .4), 3));
    _glassFront(c, k, const Color(0xFF9FB0BA));
    // condensation
    final cd = _sm((p - 0.5) / 0.5);
    for (var i = 0; i < 22; i++) {
      final dx = k.cx - k.tw / 2 + 8 + _fr(i + 60) * (k.tw - 16);
      final dy = k.top + 20 + _fr(i + 61) * (k.bot - k.top - 50);
      if (dy < ly) continue;
      final off = (t * 3 * _fr(i)) % 6;
      c.drawOval(
          Rect.fromCenter(
              center: Offset(dx, dy + off),
              width: 2 * (1.6 + _fr(i + 62) * 1.4),
              height: 2 * (2.2 + _fr(i + 63) * 1.8)),
          Paint()..color = _k(235, 245, 255, .55 * .85 * cd));
      c.drawCircle(Offset(dx - .6, dy - .6 + off), .7, Paint()..color = _k(255, 255, 255, .8 * .85 * cd));
    }
    // cold vapour, low and slow
    if (t > _steamAt) {
      for (var i = 0; i < 6; i++) {
        final age = t - _steamAt - i * 0.25;
        if (age < 0) continue;
        const life = 2.8;
        final u = (age % life) / life;
        final x = k.cx + (_fr(i + 80) - 0.5) * 100 + math.sin(age * 1.8 + i) * 12;
        final y = k.top - 6 - u * 44;
        final r = 18 + u * 20;
        final a = math.sin(u * math.pi) * 0.32 * _sm((t - _steamAt) / .6);
        c.drawCircle(
            Offset(x, y),
            r,
            Paint()
              ..shader = ui.Gradient.radial(Offset(x, y), r,
                  [_k(235, 245, 255, a), _k(235, 245, 255, 0)]));
      }
    }
  }
}
