import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core.dart';

/// One saying per day. The list is rotated by the day number, so the
/// same day shows the same text and tomorrow shows the next one.
const amanaSayings = <(String, String)>[
  ('إِنَّ اللَّهَ يَأْمُرُكُمْ أَن تُؤَدُّوا الْأَمَانَاتِ إِلَىٰ أَهْلِهَا', 'سورة النساء • ٥٨'),
  ('التَّاجِرُ الصَّدُوقُ الْأَمِينُ مَعَ النَّبِيِّينَ وَالصِّدِّيقِينَ وَالشُّهَدَاءِ', 'حديث شريف • رواه الترمذي'),
  ('وَأَوْفُوا بِالْعَهْدِ ۖ إِنَّ الْعَهْدَ كَانَ مَسْئُولًا', 'سورة الإسراء • ٣٤'),
  ('وَأَوْفُوا الْكَيْلَ إِذَا كِلْتُمْ وَزِنُوا بِالْقِسْطَاسِ الْمُسْتَقِيمِ', 'سورة الإسراء • ٣٥'),
  ('أَدِّ الْأَمَانَةَ إِلَىٰ مَنِ ائْتَمَنَكَ، وَلَا تَخُنْ مَنْ خَانَكَ', 'حديث شريف • رواه أبو داود والترمذي'),
  ('وَالَّذِينَ هُمْ لِأَمَانَاتِهِمْ وَعَهْدِهِمْ رَاعُونَ', 'سورة المؤمنون • ٨'),
  ('مَنْ غَشَّنَا فَلَيْسَ مِنَّا', 'حديث شريف • رواه مسلم'),
  ('إِنَّ خَيْرَ مَنِ اسْتَأْجَرْتَ الْقَوِيُّ الْأَمِينُ', 'سورة القصص • ٢٦'),
  ('رَحِمَ اللَّهُ رَجُلًا سَمْحًا إِذَا بَاعَ، وَإِذَا اشْتَرَى، وَإِذَا اقْتَضَى', 'حديث شريف • رواه البخاري'),
  ('وَلَا تَبْخَسُوا النَّاسَ أَشْيَاءَهُمْ', 'سورة هود • ٨٥'),
  ('وَمَن يَتَّقِ اللَّهَ يَجْعَل لَّهُ مَخْرَجًا ۝ وَيَرْزُقْهُ مِنْ حَيْثُ لَا يَحْتَسِبُ', 'سورة الطلاق • ٢ و٣'),
  ('الْبَيِّعَانِ بِالْخِيَارِ مَا لَمْ يَتَفَرَّقَا، فَإِنْ صَدَقَا وَبَيَّنَا بُورِكَ لَهُمَا فِي بَيْعِهِمَا', 'حديث شريف • متفق عليه'),
  ('يَا أَيُّهَا الَّذِينَ آمَنُوا اتَّقُوا اللَّهَ وَكُونُوا مَعَ الصَّادِقِينَ', 'سورة التوبة • ١١٩'),
  ('إِنَّ اللَّهَ يُحِبُّ إِذَا عَمِلَ أَحَدُكُمْ عَمَلًا أَنْ يُتْقِنَهُ', 'حديث شريف • رواه البيهقي'),
  ('وَقُولُوا لِلنَّاسِ حُسْنًا', 'سورة البقرة • ٨٣'),
  ('وَاصْبِرْ فَإِنَّ اللَّهَ لَا يُضِيعُ أَجْرَ الْمُحْسِنِينَ', 'سورة هود • ١١٥'),
  ('تَبَسُّمُكَ فِي وَجْهِ أَخِيكَ صَدَقَةٌ', 'حديث شريف • رواه الترمذي'),
  ('وَقُلِ اعْمَلُوا فَسَيَرَى اللَّهُ عَمَلَكُمْ وَرَسُولُهُ وَالْمُؤْمِنُونَ', 'سورة التوبة • ١٠٥'),
  ('وَأَحْسِنُوا ۛ إِنَّ اللَّهَ يُحِبُّ الْمُحْسِنِينَ', 'سورة البقرة • ١٩٥'),
  ('أَحَبُّ النَّاسِ إِلَى اللَّهِ أَنْفَعُهُمْ لِلنَّاسِ', 'حديث شريف • رواه الطبراني'),
  ('لَئِن شَكَرْتُمْ لَأَزِيدَنَّكُمْ', 'سورة إبراهيم • ٧'),
  ('وَمَن يَتَوَكَّلْ عَلَى اللَّهِ فَهُوَ حَسْبُهُ', 'سورة الطلاق • ٣'),
  ('وَتَعَاوَنُوا عَلَى الْبِرِّ وَالتَّقْوَىٰ', 'سورة المائدة • ٢'),
  ('فَإِنَّ مَعَ الْعُسْرِ يُسْرًا', 'سورة الشرح • ٥'),
  ('وَاللَّهُ خَيْرُ الرَّازِقِينَ', 'سورة الجمعة • ١١'),
  ('إِنَّ اللَّهَ مَعَ الصَّابِرِينَ', 'سورة البقرة • ١٥٣'),
  ('وَمَا تَوْفِيقِي إِلَّا بِاللَّهِ', 'سورة هود • ٨٨'),
  ('رَبِّ اشْرَحْ لِي صَدْرِي ۝ وَيَسِّرْ لِي أَمْرِي', 'سورة طه • ٢٥ و٢٦'),
  ('فَاذْكُرُونِي أَذْكُرْكُمْ وَاشْكُرُوا لِي وَلَا تَكْفُرُونِ', 'سورة البقرة • ١٥٢'),
];

(String, String) todaysSaying([DateTime? now]) {
  final d = (now ?? DateTime.now());
  final day = DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;
  return amanaSayings[day % amanaSayings.length];
}

bool _amanaShown = false;

/// Plays the "الأمانة" screen once per app launch, then returns.
Future<void> showAmana(BuildContext context) async {
  if (_amanaShown) return;
  _amanaShown = true;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: cCream,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => const _AmanaScreen(),
    transitionBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  );
}

class _AmanaScreen extends StatefulWidget {
  const _AmanaScreen();
  @override
  State<_AmanaScreen> createState() => _AmanaScreenState();
}

class _AmanaScreenState extends State<_AmanaScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 9000))
    ..forward().whenComplete(_close);
  bool _closed = false;

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b) {
    final x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  @override
  Widget build(BuildContext context) {
    final s = todaysSaying();
    return Material(
      color: cCream,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_c.value > 0.35) _close();
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.35),
              radius: 1.0,
              colors: [Color(0xFF3A2620), cCream],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  final t = _c.value * 9.0;
                  final title = _seg(t, 1.9, 2.7);
                  final verse = _seg(t, 2.8, 4.0);
                  final src = _seg(t, 4.3, 5.1);
                  final hint = _seg(t, 5.8, 6.6);
                  return Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 150,
                          height: 150,
                          child: CustomPaint(painter: _SealPainter(t)),
                        ),
                        const SizedBox(height: 18),
                        Opacity(
                          opacity: title,
                          child: Transform.translate(
                            offset: Offset(0, 14 * (1 - title)),
                            child: const Text('الأمانة',
                                style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    color: cBrand)),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Opacity(
                          opacity: verse,
                          child: Transform.translate(
                            offset: Offset(0, 18 * (1 - verse)),
                            child: Text(s.$1,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 22,
                                    height: 1.9,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Opacity(
                          opacity: src,
                          child: Text(s.$2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: cMuted, fontSize: 14)),
                        ),
                        const SizedBox(height: 28),
                        Opacity(
                          opacity: hint,
                          child: const Text('دوس في أي مكان عشان تكمّل',
                              style: TextStyle(color: cMuted, fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A gold ring that draws itself, then a check mark, then a soft glow.
class _SealPainter extends CustomPainter {
  final double t;
  const _SealPainter(this.t);

  double _seg(double a, double b) {
    final x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  @override
  void paint(Canvas c, Size size) {
    final ctr = size.center(Offset.zero);
    final r = size.width / 2 - 10;
    final glow = _seg(1.6, 2.6);
    if (glow > 0) {
      final pulse = 0.75 + 0.25 * math.sin(t * 2.4);
      c.drawCircle(
          ctr,
          r + 8,
          Paint()
            ..color = cGold.withOpacity(0.22 * glow * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    }
    final ring = _seg(0.2, 1.4);
    c.drawArc(
        Rect.fromCircle(center: ctr, radius: r),
        -math.pi / 2,
        2 * math.pi * ring,
        false,
        Paint()
          ..color = cGold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
    // eight small dots around the ring, like a star pattern
    final dots = _seg(0.9, 1.7);
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      c.drawCircle(ctr + Offset(math.cos(a), math.sin(a)) * (r + 12), 2.2 * dots,
          Paint()..color = cGold.withOpacity(0.8));
    }
    final ck = _seg(1.2, 1.9);
    if (ck > 0) {
      final p = Path()
        ..moveTo(ctr.dx - r * 0.38, ctr.dy + r * 0.02)
        ..lineTo(ctr.dx - r * 0.1, ctr.dy + r * 0.32)
        ..lineTo(ctr.dx + r * 0.42, ctr.dy - r * 0.28);
      final m = p.computeMetrics().first;
      c.drawPath(
          m.extractPath(0, m.length * ck),
          Paint()
            ..color = cBrand
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }
  }

  @override
  bool shouldRepaint(_SealPainter old) => old.t != t;
}
