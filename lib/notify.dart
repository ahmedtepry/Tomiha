import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import 'core.dart';

const _statusMsg = {
  'received': 'تم تأكيد طلبك، هنبدأ نجهزه دلوقتي.',
  'preparing': 'بنحضّر طلبك دلوقتي ☕',
  'ready': 'طلبك جاهز.',
  'on_the_way': 'طلبك في الطريق ليك.',
  'delivered': 'بالهنا والشفا! طلبك اتسلّم.',
  'cancelled': 'للأسف طلبك اتلغى. تقدر تطلب من جديد.',
};

/// Tells the customer, inside the app, whenever the status of one of
/// their orders changes. Silent when anything goes wrong.
class OrderNotifier extends StatefulWidget {
  final Widget child;
  const OrderNotifier({super.key, required this.child});
  @override
  State<OrderNotifier> createState() => _OrderNotifierState();
}

class _OrderNotifierState extends State<OrderNotifier> {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription<AuthState>? _auth;
  final Map<String, String> _last = {};
  bool _primed = false;

  @override
  void initState() {
    super.initState();
    _listen();
    _auth = sb.auth.onAuthStateChange.listen((_) => _listen());
  }

  void _listen() {
    _sub?.cancel();
    _sub = null;
    _last.clear();
    _primed = false;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      _sub = sb
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('customer_id', uid)
          .listen(_onRows, onError: (_) {});
    } catch (_) {}
  }

  void _onRows(List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      final id = r['id'] as String;
      final st = r['status'] as String;
      final prev = _last[id];
      _last[id] = st;
      if (!_primed || prev == null || prev == st) continue;
      final msg = _statusMsg[st];
      if (msg == null || !mounted) continue;
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          content: Row(children: [
            const Icon(Icons.notifications_active, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ));
    }
    _primed = true;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
