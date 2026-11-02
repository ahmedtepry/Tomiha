import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import 'core.dart';

class AvatarInfo {
  final String id;
  final String name;
  const AvatarInfo(this.id, this.name);
}

const avatarList = [
  AvatarInfo('m1', 'الباريستا'),
  AvatarInfo('m2', 'عم التركي'),
  AvatarInfo('m3', 'حبة البن'),
  AvatarInfo('m4', 'الحاج صاحب الفنجان'),
  AvatarInfo('f1', 'بنت البن'),
  AvatarInfo('f2', 'لاتيه آرت'),
  AvatarInfo('f3', 'ست الصباحية'),
  AvatarInfo('f4', 'تيتة الفنجان'),
];

/// Cartoon avatar drawn on a 100x100 canvas. Every one has a coffee twist.
class AvatarPainter extends CustomPainter {
  final String id;
  const AvatarPainter(this.id);

  static const _bgs = {
    'm1': Color(0xFF6A3D22),
    'm2': Color(0xFF7A2E24),
    'm3': Color(0xFF3E5A44),
    'm4': Color(0xFF4A3A5C),
    'f1': Color(0xFFB5683A),
    'f2': Color(0xFF8A4B5E),
    'f3': Color(0xFF3A5A66),
    'f4': Color(0xFF6B5A3A),
  };

  Paint _p(Color c) => Paint()..color = c;

  void _mug(Canvas c, double x, double y, {bool handle = true, Color body = const Color(0xFFF5E9D8)}) {
    final r = RRect.fromRectAndCorners(Rect.fromLTWH(x, y, 20, 16),
        bottomLeft: const Radius.circular(8), bottomRight: const Radius.circular(8));
    c.drawRRect(r, _p(body));
    c.drawRect(Rect.fromLTWH(x, y, 20, 3.5), _p(const Color(0xFF3B2314)));
    if (handle) {
      c.drawArc(Rect.fromLTWH(x + 15, y + 3, 10, 9), -math.pi / 2, math.pi, false,
          Paint()
            ..color = body
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4);
    }
    final steam = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 2; i++) {
      final sx = x + 6 + i * 8;
      final p = Path()
        ..moveTo(sx, y - 2)
        ..quadraticBezierTo(sx - 3, y - 6, sx, y - 9)
        ..quadraticBezierTo(sx + 3, y - 12, sx, y - 15);
      c.drawPath(p, steam);
    }
  }

  void _bean(Canvas c, double x, double y, double rot, double s) {
    c.save();
    c.translate(x, y);
    c.rotate(rot);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 11 * s, height: 15 * s),
        _p(const Color(0xFF4A2A18)));
    final line = Paint()
      ..color = const Color(0xFF1A0F08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * s;
    final p = Path()
      ..moveTo(0, -6 * s)
      ..quadraticBezierTo(3 * s, 0, 0, 6 * s);
    c.drawPath(p, line);
    c.restore();
  }

  void _face(Canvas c, Color skin, {bool lashes = false, double ey = 46}) {
    c.drawOval(Rect.fromCenter(center: const Offset(50, 46), width: 44, height: 48), _p(skin));
    final eye = _p(const Color(0xFF2A1A12));
    c.drawCircle(Offset(41, ey), 2.2, eye);
    c.drawCircle(Offset(59, ey), 2.2, eye);
    if (lashes) {
      final l = Paint()
        ..color = const Color(0xFF2A1A12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      c.drawLine(Offset(38.5, ey - 2), Offset(37, ey - 4), l);
      c.drawLine(Offset(61.5, ey - 2), Offset(63, ey - 4), l);
    }
    final smile = Paint()
      ..color = const Color(0xFF7A3A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    c.drawArc(Rect.fromCenter(center: const Offset(50, 55), width: 14, height: 9), 0.25,
        math.pi - 0.5, false, smile);
  }

  void _body(Canvas c, Color cloth) {
    c.drawOval(Rect.fromCenter(center: const Offset(50, 104), width: 84, height: 54), _p(cloth));
  }

  void _glasses(Canvas c) {
    final g = Paint()
      ..color = const Color(0xFF2A1A12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    c.drawCircle(const Offset(41, 46), 6, g);
    c.drawCircle(const Offset(59, 46), 6, g);
    c.drawLine(const Offset(47, 46), const Offset(53, 46), g);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.clipPath(Path()..addOval(const Rect.fromLTWH(0, 0, 100, 100)));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100), _p(_bgs[id] ?? const Color(0xFF6A3D22)));
    final c = canvas;
    switch (id) {
      case 'm1': // barista with cap and apron
        _body(c, const Color(0xFFF5E9D8));
        c.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(34, 80, 32, 24), const Radius.circular(6)),
            _p(const Color(0xFF3B2314)));
        _face(c, const Color(0xFFE8B98F));
        c.drawOval(Rect.fromCenter(center: const Offset(50, 28), width: 50, height: 22),
            _p(const Color(0xFF3B2314)));
        c.drawRect(const Rect.fromLTWH(30, 30, 40, 6), _p(const Color(0xFF2A1A12)));
        c.drawCircle(const Offset(50, 20), 2.6, _p(const Color(0xFFD9894A)));
        _mug(c, 70, 74);
        break;
      case 'm2': // fez and big moustache
        _body(c, const Color(0xFF2E2A28));
        _face(c, const Color(0xFFD9A47A));
        final fez = Path()
          ..moveTo(33, 33)
          ..lineTo(37, 12)
          ..lineTo(63, 12)
          ..lineTo(67, 33)
          ..close();
        c.drawPath(fez, _p(const Color(0xFFB02A20)));
        c.drawLine(const Offset(63, 12), const Offset(72, 24),
            Paint()
              ..color = const Color(0xFF1A110C)
              ..strokeWidth = 2.2);
        c.drawCircle(const Offset(72, 25), 2.6, _p(const Color(0xFF1A110C)));
        final m = Path()
          ..moveTo(50, 52)
          ..quadraticBezierTo(40, 50, 33, 57)
          ..quadraticBezierTo(42, 60, 50, 56)
          ..quadraticBezierTo(58, 60, 67, 57)
          ..quadraticBezierTo(60, 50, 50, 52);
        c.drawPath(m, _p(const Color(0xFF3B2A22)));
        _mug(c, 6, 76, handle: false, body: const Color(0xFFD9894A));
        break;
      case 'm3': // coffee bean hair + glasses
        _body(c, const Color(0xFFE3B04B));
        _face(c, const Color(0xFFF0C9A4));
        _bean(c, 36, 26, -0.6, 1.1);
        _bean(c, 50, 21, 0.1, 1.2);
        _bean(c, 64, 26, 0.6, 1.1);
        _bean(c, 28, 38, -1.0, 0.9);
        _bean(c, 72, 38, 1.0, 0.9);
        _glasses(c);
        break;
      case 'm4': // grandpa with white beard and a Turkish coffee cup
        _body(c, const Color(0xFF6A4A32));
        _face(c, const Color(0xFFE2B48C));
        final beard = Path()
          ..moveTo(29, 50)
          ..quadraticBezierTo(32, 80, 50, 80)
          ..quadraticBezierTo(68, 80, 71, 50)
          ..quadraticBezierTo(62, 58, 50, 58)
          ..quadraticBezierTo(38, 58, 29, 50);
        c.drawPath(beard, _p(const Color(0xFFEDEDED)));
        c.drawArc(const Rect.fromLTWH(28, 18, 44, 36), math.pi, math.pi, true,
            _p(const Color(0xFFDADADA)));
        c.drawCircle(const Offset(41, 46), 2.2, _p(const Color(0xFF2A1A12)));
        c.drawCircle(const Offset(59, 46), 2.2, _p(const Color(0xFF2A1A12)));
        _mug(c, 70, 76, body: const Color(0xFFE3B04B));
        break;
      case 'f1': // ponytail + bean earrings
        _body(c, const Color(0xFFF5E9D8));
        c.drawCircle(const Offset(76, 36), 9, _p(const Color(0xFF3B2314)));
        _face(c, const Color(0xFFE8B98F), lashes: true);
        c.drawArc(const Rect.fromLTWH(27, 20, 46, 40), math.pi, math.pi, true,
            _p(const Color(0xFF3B2314)));
        _bean(c, 28, 56, 0.2, 0.7);
        _bean(c, 72, 56, -0.2, 0.7);
        c.drawCircle(const Offset(74, 30), 3, _p(const Color(0xFFD9894A)));
        break;
      case 'f2': // long hair + latte art heart
        c.drawOval(Rect.fromCenter(center: const Offset(50, 56), width: 58, height: 70),
            _p(const Color(0xFF7A3A22)));
        _body(c, const Color(0xFFF2D6C6));
        _face(c, const Color(0xFFF0C9A4), lashes: true);
        c.drawArc(const Rect.fromLTWH(27, 20, 46, 40), math.pi, math.pi, true,
            _p(const Color(0xFF7A3A22)));
        c.drawCircle(const Offset(80, 84), 13, _p(const Color(0xFF6A3D22)));
        final h = Path()
          ..moveTo(80, 90)
          ..cubicTo(70, 83, 73, 77, 77, 78)
          ..cubicTo(79, 78, 80, 80, 80, 81)
          ..cubicTo(80, 80, 81, 78, 83, 78)
          ..cubicTo(87, 77, 90, 83, 80, 90);
        c.drawPath(h, _p(const Color(0xFFF5E9D8)));
        break;
      case 'f3': // hijab + cup
        c.drawOval(Rect.fromCenter(center: const Offset(50, 50), width: 62, height: 70),
            _p(const Color(0xFFC9955E)));
        _body(c, const Color(0xFFC9955E));
        _face(c, const Color(0xFFEBC09A), lashes: true);
        c.drawArc(const Rect.fromLTWH(27, 22, 46, 20), math.pi, math.pi, true,
            _p(const Color(0xFFC9955E)));
        _bean(c, 66, 74, 0.5, 0.9);
        _mug(c, 6, 76);
        break;
      case 'f4': // grandma with bun, glasses and a small finjan
        _body(c, const Color(0xFF8A5A7A));
        c.drawCircle(const Offset(50, 14), 9, _p(const Color(0xFFD0D0D0)));
        _face(c, const Color(0xFFE6B890), lashes: true);
        c.drawArc(const Rect.fromLTWH(27, 18, 46, 40), math.pi, math.pi, true,
            _p(const Color(0xFFD0D0D0)));
        _glasses(c);
        _mug(c, 70, 76, handle: false, body: const Color(0xFFD9894A));
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(AvatarPainter old) => old.id != id;
}

class AvatarView extends StatelessWidget {
  final String? id;
  final double size;
  const AvatarView({super.key, required this.id, this.size = 40});
  @override
  Widget build(BuildContext context) {
    if (id == null || !avatarList.any((a) => a.id == id)) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: cCream2,
        foregroundColor: cBrand,
        child: Icon(Icons.person, size: size * 0.6),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: AvatarPainter(id!)),
    );
  }
}

/// The account icon at the top of the menu: shows the chosen avatar.
class AccountButton extends StatefulWidget {
  const AccountButton({super.key});
  @override
  State<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<AccountButton> {
  String? _avatar;
  late final sub = sb.auth.onAuthStateChange.listen((_) => _load());

  @override
  void initState() {
    super.initState();
    sub;
    _load();
  }

  @override
  void dispose() {
    sub.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final u = sb.auth.currentUser;
    if (u == null) {
      if (mounted) setState(() => _avatar = null);
      return;
    }
    try {
      final r = await sb.from('profiles').select('avatar').eq('id', u.id).maybeSingle();
      if (mounted) setState(() => _avatar = r?['avatar'] as String?);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'حسابي',
      icon: AvatarView(id: _avatar, size: 36),
      onPressed: () async {
        if (sb.auth.currentSession == null) {
          final ok = await ensureSignedIn(context);
          if (!ok || !context.mounted) return;
        }
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AccountPage()));
        _load();
      },
    );
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _name = TextEditingController();
  String? _avatar;
  bool _loading = true;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final u = sb.auth.currentUser!;
      final r = await sb
          .from('profiles')
          .select('full_name, avatar')
          .eq('id', u.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _name.text = (r?['full_name'] as String?) ?? '';
        _avatar = r?['avatar'] as String?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final u = sb.auth.currentUser!;
      await sb.from('profiles').update({
        'full_name': _name.text.trim(),
        'avatar': _avatar,
      }).eq('id', u.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اتحفظت بياناتك.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  Widget _tile(AvatarInfo a) {
    final on = a.id == _avatar;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _avatar = a.id),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: on ? cCream2 : cCream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? cBrand : cHair, width: on ? 2.5 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarView(id: a.id, size: 64),
            const SizedBox(height: 4),
            Text(a.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    color: on ? cBrand : cInk)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = sb.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('مقدرناش نحمّل بيانات حسابك. اتأكد من الإنترنت وجرّب تاني.',
                      textAlign: TextAlign.center),
                ))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(child: AvatarView(id: _avatar, size: 104)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'الاسم'),
                    ),
                    const SizedBox(height: 12),
                    if (email.isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.alternate_email, color: cMuted),
                        title: const Text('الإيميل',
                            style: TextStyle(color: cMuted, fontSize: 12)),
                        subtitle: Text(email,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.start,
                            style: const TextStyle(fontSize: 15)),
                      ),
                    const SectionLabel('اختار شخصيتك'),
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.78,
                      children: [for (final a in avatarList) _tile(a)],
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54)),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'بنحفظ...' : 'حفظ'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50)),
                      icon: const Icon(Icons.logout),
                      label: const Text('تسجيل خروج'),
                      onPressed: () async {
                        await sb.auth.signOut();
                        if (context.mounted) {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        }
                      },
                    ),
                  ],
                ),
    );
  }
}
