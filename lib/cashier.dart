import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'core.dart';
import 'offline.dart';
import 'devprefs.dart';
import 'amana.dart';
import 'update.dart';
import 'appearance.dart';
import 'delivery.dart';
import 'ops.dart';
import 'admin.dart';

const _orderSelect =
    '*, profiles(full_name), order_items(*, drinks(name, is_coffee, drink_prices(size)), order_item_addons(*, addons(name)))';

/// The signed-in employee (job, name, employee number), loaded by the gate.
Map<String, dynamic> myStaff = {};
/// Result of today's check-in, shown once after opening the shift.
Map<String, dynamic>? pendingWelcome;
/// The seller shown on the sell screen (switchable without a password).
String? activeSellerId;
String? activeSellerName;

bool get isOwner => myStaff['role'] == 'manager';
/// Supervisor (مدير): a staff member with reports, expenses and approval powers.
bool get isSupervisor => isOwner || myStaff['staff_role'] == 'manager';

/// Which order steps this employee may press. Accounts without a job keep everything.
bool canSet(String status) {
  if (isOwner) return true;
  switch (myStaff['staff_role']) {
    case 'reception':
      return status == 'received' || status == 'cancelled';
    case 'barista':
      return status == 'preparing' || status == 'ready';
    case 'delivery':
      return status == 'on_the_way' || status == 'delivered';
    case 'seller':
      return status == 'preparing' || status == 'ready' || status == 'delivered';
    default:
      return true;
  }
}

bool get canConfirmPayment =>
    isSupervisor || const [null, 'reception', 'seller'].contains(myStaff['staff_role']);

class CashierApp extends StatelessWidget {
  const CashierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return nasyaMaterialApp(
      AuthGate(
        signedIn: () => const UpdateWatcher(child: CashierGate()),
        signedOut: const AuthPage(title: 'دخول الكاشير', allowSignUp: false),
      ),
    );
  }
}

// ---------------------------------------------------------------- gate + shift

class CashierGate extends StatefulWidget {
  /// Owner opening a work screen from the dashboard ('sell' or 'online').
  final bool forceHome;
  final String? mode;
  const CashierGate({super.key, this.forceHome = false, this.mode});
  @override
  State<CashierGate> createState() => _CashierGateState();
}

class _CashierGateState extends State<CashierGate> {
  late Future<Map<String, dynamic>> _state = _load();

  Future<Map<String, dynamic>> _load() async {
    final uid = sb.auth.currentUser!.id;
    final prof = await sb
        .from('profiles')
        .select('role, staff_role, full_name, employee_no, active')
        .eq('id', uid)
        .maybeSingle();
    myStaff = prof ?? {};
    final role = prof?['role'];
    if (prof?['active'] == false) return {'staff': false};
    if (role != 'cashier' && role != 'manager') return {'staff': false};
    final shifts = await sb
        .from('shifts')
        .select()
        .eq('cashier_id', uid)
        .isFilter('closed_at', null)
        .order('opened_at', ascending: false)
        .limit(1);
    return {'staff': true, 'shift': shifts.isEmpty ? null : shifts.first};
  }

  bool _lastFailed = false;

  void _reload() {
    setState(() {
      _state = _load();
    });
  }

  void _onNet() {
    if (net.online && _lastFailed && mounted) _reload();
  }

  @override
  void initState() {
    super.initState();
    net.addListener(_onNet);
  }

  @override
  void dispose() {
    net.removeListener(_onNet);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _state,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        _lastFailed = snap.hasError;
        if (snap.hasError) {
          final off = isNetworkError(snap.error!);
          return Scaffold(
            body: ProblemView(
              offline: off,
              title: off ? 'انقطع الاتصال بالإنترنت' : 'مقدرناش نفتح الوردية',
              hint: off
                  ? 'هنكمّل لوحدنا أول ما النت يرجع.'
                  : errorText(snap.error!),
              onRetry: _reload,
            ),
          );
        }
        final s = snap.data!;
        if (s['staff'] != true) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('الحساب ده مش مسجّل كموظف في بنايه.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => sb.auth.signOut(),
                    child: const Text('خروج'),
                  ),
                ],
              ),
            ),
          );
        }
        // Owner lands on the dashboard; each job lands on its own screen.
        if (isSupervisor && !widget.forceHome) return const AdminDashboard();
        final shift = s['shift'];
        if (shift == null) return OpenShiftPage(onOpened: _reload);
        final String mode;
        if (widget.mode != null) {
          mode = widget.mode!;
        } else {
          switch (myStaff['staff_role']) {
            case 'seller':
              mode = 'sell';
              break;
            case 'reception':
            case 'barista':
            case 'delivery':
              mode = 'online';
              break;
            default:
              mode = 'all';
          }
        }
        return CashierHome(
          shift: shift as Map<String, dynamic>,
          onClosed: _reload,
          mode: mode,
        );
      },
    );
  }
}

class OpenShiftPage extends StatefulWidget {
  final VoidCallback onOpened;
  const OpenShiftPage({super.key, required this.onOpened});
  @override
  State<OpenShiftPage> createState() => _OpenShiftPageState();
}

class _OpenShiftPageState extends State<OpenShiftPage> {
  final _cash = TextEditingController(text: '0');
  final _pass = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cash.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_pass.text.isEmpty) {
      showError(context, 'اكتب كلمة السر عشان تأكد فتح الوردية.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Opening a shift needs the employee's own password again.
      await sb.auth.signInWithPassword(
          email: sb.auth.currentUser!.email!, password: _pass.text);
      if (!await confirmPresence('أكّد بصمتك عشان تفتح الوردية')) {
        if (mounted) {
          setState(() => _busy = false);
          showError(context, 'مقدرناش نتأكد من البصمة. جرّب تاني.');
        }
        return;
      }
      await sb.from('shifts').insert({
        'cashier_id': sb.auth.currentUser!.id,
        'opening_cash': double.tryParse(_cash.text.trim()) ?? 0,
      });
      try {
        final r = await sb.rpc('staff_check_in');
        pendingWelcome = Map<String, dynamic>.from(r as Map);
      } catch (_) {}
      widget.onOpened();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BONNAYA • كاشير'),
        actions: [
          IconButton(
            tooltip: 'الطابعة والبصمة',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showDeviceSettings(context),
          ),
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              sb.auth.signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  (myStaff['full_name'] as String?)?.isNotEmpty == true
                      ? 'أهلاً يا ${myStaff['full_name']}'
                      : 'أهلاً بيك',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const SizedBox(height: 8),
              const Text('اكتب الكاش اللي في الدرج وكلمة السر عشان نفتح الوردية.',
                  style: TextStyle(color: cMuted)),
              const SizedBox(height: 16),
              TextField(
                controller: _cash,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'كاش بداية الوردية (ج)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة السر (تأكيد)'),
                onSubmitted: (_) => _open(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy ? null : _open,
                child: const Text('افتح الوردية'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- home

class CashierHome extends StatefulWidget {
  final Map<String, dynamic> shift;
  final VoidCallback onClosed;
  final String mode; // 'all', 'sell' or 'online'
  const CashierHome(
      {super.key, required this.shift, required this.onClosed, this.mode = 'all'});
  @override
  State<CashierHome> createState() => _CashierHomeState();
}

class _CashierHomeState extends State<CashierHome> {
  Map<String, dynamic> get shift => widget.shift;
  VoidCallback get onClosed => widget.onClosed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _welcome());
  }

  Future<void> _welcome() async {
    if (!mounted) return;
    await showAmana(context);
    if (!mounted) return;
    final name = (myStaff['full_name'] as String?)?.trim();
    final who = (name == null || name.isEmpty) ? '' : ' يا $name';
    final w = pendingWelcome;
    pendingWelcome = null;
    if (w == null || w['skipped'] == true || w['already'] == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('أهلاً بيك$who. يوم موفق!')));
      return;
    }
    final d = (w['delta_minutes'] as num?)?.toInt() ?? 0;
    final bonus = (w['bonus'] as num?)?.toDouble() ?? 0;
    String msg;
    IconData icon;
    if (d >= 2) {
      msg = 'اتأخرت $d دقيقة عن ميعادك. حاول تيجي في ميعادك المرة الجاية، ويومك حلو.';
      icon = Icons.schedule;
    } else if (d <= -5) {
      msg = 'جاي قبل ميعادك بـ ${-d} دقيقة، تسلم يا بطل!'
          '${bonus > 0 ? '\nمكافأتك النهاردة ${money(bonus)}.' : ''}';
      icon = Icons.emoji_events_outlined;
    } else {
      msg = 'جيت في ميعادك. تسلم!';
      icon = Icons.check_circle_outline;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, color: cBrand, size: 40),
        title: Text('أهلاً بيك$who'),
        content: Text(
            msg),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('يلا نشتغل')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'BONNAYA • كاشير  (وردية من ${fmtTime(shift['opened_at'] as String)})'),
        actions: [
          const VersionButton(),
          if (isOwner)
            IconButton(
              tooltip: 'إعدادات التشغيل (مواعيد الشغل والمكافآت)',
              icon: const Icon(Icons.tune),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const OpsSettingsDialog(),
              ),
            ),
          if (isOwner)
            IconButton(
              tooltip: 'شاشة الترحيب',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const WelcomeSettingsDialog(),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.summarize_outlined),
            label: const Text('تقرير / قفل الوردية'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ShiftDialog(
                shiftId: shift['id'] as String,
                onClosed: onClosed,
              ),
            ),
          ),
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              sb.auth.signOut();
            },
          ),
        ],
      ),
      body: widget.mode == 'sell'
          ? PosPanel(shiftId: shift['id'] as String)
          : widget.mode == 'online'
              ? Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: const OnlineOrdersPanel()))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(width: 440, child: OnlineOrdersPanel()),
                    const VerticalDivider(width: 1, color: cHair),
                    Expanded(child: PosPanel(shiftId: shift['id'] as String)),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------- online orders

class OnlineOrdersPanel extends StatefulWidget {
  const OnlineOrdersPanel({super.key});
  @override
  State<OnlineOrdersPanel> createState() => _OnlineOrdersPanelState();
}

class _OnlineOrdersPanelState extends State<OnlineOrdersPanel> {
  List<Map<String, dynamic>> _orders = [];
  final Set<String> _seen = {};
  bool _first = true;
  bool _loadFailed = false;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = sb.from('orders').stream(primaryKey: ['id']).listen((_) => _load());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    net.addListener(_onNet);
  }

  @override
  void dispose() {
    net.removeListener(_onNet);
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  // Orders refresh right away when the connection returns.
  void _onNet() {
    if (net.online && mounted) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await sb
          .from('orders')
          .select(_orderSelect)
          .eq('source', 'app')
          .inFilter('status', ['pending_payment', 'received', 'preparing', 'ready', 'on_the_way'])
          .order('created_at');
      final role = isOwner ? null : myStaff['staff_role'] as String?;
      final visible = rows.where((o) {
        final st = o['status'];
        if (role == 'barista') return st == 'received' || st == 'preparing';
        if (role == 'delivery') return st == 'ready' || st == 'on_the_way';
        return true;
      }).toList();
      final alertOn = role == 'delivery' ? 'ready' : 'received';
      final fresh = visible
          .where((o) =>
              (o['status'] == alertOn ||
                  (role != 'barista' && role != 'delivery' && o['status'] == 'pending_payment')) &&
              !_seen.contains(o['id']))
          .toList();
      for (final o in visible) {
        _seen.add(o['id'] as String);
      }
      if (!_first && fresh.isNotEmpty) {
        SystemSound.play(SystemSoundType.alert);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(fresh.length == 1
                  ? 'أوردر جديد #${fresh.first['order_no']}'
                  : 'وصل ${fresh.length} أوردرات جديدة')));
        }
      }
      _first = false;
      if (mounted) {
        setState(() {
          _orders = visible;
          _loadFailed = false;
        });
      }
    } catch (e) {
      if (isNetworkError(e)) net.markOffline();
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _status(String id, String status) async {
    try {
      await sb.rpc('set_order_status',
          params: {'p_order': id, 'p_status': status});
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _confirmPayment(String id) async {
    try {
      await sb.rpc('confirm_order_payment', params: {'p_order': id});
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _paid(String id) async {
    try {
      await sb.rpc('set_order_paid', params: {'p_order': id});
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _cancel(String id) async {
    final reason = await askReason(context, 'إلغاء الطلب', 'سبب الإلغاء');
    if (reason == null) return;
    try {
      await sb.rpc('cancel_order', params: {'p_order': id, 'p_reason': reason});
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _print(Map<String, dynamic> o) async {
    try {
      await printReceipt(o);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('الطلبات الأونلاين',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 14,
                backgroundColor: cBrand,
                foregroundColor: cCream,
                child: Text('${_orders.length}'),
              ),
              const Spacer(),
              if (_loadFailed)
                const Flexible(
                  child: Text('مش قادرين نحدّث الطلبات. هنحدّثها أول ما الاتصال يرجع.',
                      style: TextStyle(color: cDanger, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _orders.isEmpty
                ? const Center(
                    child: Text('مفيش طلبات دلوقتي',
                        style: TextStyle(color: cMuted)))
                : ListView.separated(
                    itemCount: _orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _card(_orders[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> o) {
    final id = o['id'] as String;
    final st = o['status'] as String;
    final items = (o['order_items'] as List).cast<Map<String, dynamic>>();
    final name = (o['profiles'] as Map<String, dynamic>?)?['full_name'];
    final isCash = o['payment_method'] == 'cash';
    final paid = o['payment_status'] == 'paid';
    final chipColor = st == 'received' || st == 'pending_payment'
        ? cGold
        : st == 'preparing'
            ? cGreen
            : cCream;
    final chipText = st == 'preparing' ? cInk : cOnBrand;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: st == 'received' || st == 'pending_payment' ? cCream2 : cCream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: st == 'received' || st == 'pending_payment' ? cBrand : cHair,
            width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: st == 'ready' ? cGreen : chipColor),
                ),
                child: Text(statusLabel[st] ?? st,
                    style: TextStyle(
                        color: st == 'ready' ? cGreen : chipText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text('#${o['order_no']}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              if (st == 'pending_payment' || st == 'received')
                Builder(builder: (_) {
                  final mins = DateTime.now()
                      .difference(DateTime.parse(o['created_at'] as String).toLocal())
                      .inMinutes;
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: Text('بقاله $mins د',
                        style: TextStyle(
                            color: mins >= 10 ? cDanger : cMuted,
                            fontWeight: mins >= 10 ? FontWeight.w800 : FontWeight.w400,
                            fontSize: 13)),
                  );
                }),
              const Spacer(),
              Text(
                  o['eta_minutes'] != null
                      ? 'بعد ${o['eta_minutes']} د • ${fmtTime(o['created_at'] as String)}'
                      : fmtTime(o['created_at'] as String),
                  style: const TextStyle(color: cMuted, fontSize: 13)),
            ],
          ),
          if (name != null && '$name'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('$name', style: const TextStyle(color: cMuted)),
            ),
          const SizedBox(height: 8),
          for (final it in items) ...[
            Text(itemTitle(it),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(itemNotes(it),
                style: const TextStyle(color: cMuted, fontSize: 13)),
            const SizedBox(height: 6),
          ],
          if ((o['address_text'] as String?)?.isNotEmpty == true)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cCream2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cHair),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, color: cBrand, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${o['address_text']}')),
                  TextButton(
                    onPressed: () => openMaps(
                        context,
                        Address(
                          text: '',
                          lat: (o['lat'] as num?)?.toDouble(),
                          lng: (o['lng'] as num?)?.toDouble(),
                          url: o['maps_url'] as String?,
                        ).mapsLink),
                    child: const Text('افتح الموقع'),
                  ),
                ],
              ),
            ),
          if (!isCash && (o['pay_ref'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('التحويل من محفظة: ${o['pay_ref']}',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(color: cGold, fontWeight: FontWeight.w700)),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isCash
                  ? 'كاش عند الاستلام'
                  : (paid ? 'محفظة • مدفوع' : 'محفظة • لسه متأكدش')),
              Text(money(o['total'] as num),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: cBrand)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (st == 'pending_payment' && canConfirmPayment)
                Expanded(
                  child: FilledButton(
                    onPressed: () => _confirmPayment(id),
                    child: const Text('تأكدت من التحويل • أكّد الأوردر'),
                  ),
                ),
              if (st == 'received' && canSet('preparing'))
                Expanded(
                  child: FilledButton(
                    onPressed: () => _status(id, 'preparing'),
                    child: const Text('ابدأ التحضير'),
                  ),
                ),
              if (st == 'preparing' && canSet('ready'))
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cGreen),
                    onPressed: () => _status(id, 'ready'),
                    child: const Text('جهّزت الطلب'),
                  ),
                ),
              if (st == 'ready' && canSet('on_the_way'))
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cInk),
                    onPressed: () => _status(id, 'on_the_way'),
                    child: const Text('خرج للتوصيل'),
                  ),
                ),
              if (st == 'on_the_way' && canSet('delivered'))
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cInk),
                    onPressed: () => _status(id, 'delivered'),
                    child: const Text('تم التسليم'),
                  ),
                ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _print(o),
                child: const Text('اطبع'),
              ),
            ],
          ),
          Row(
            children: [
              const Spacer(),
              if (canSet('cancelled'))
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: cDanger),
                  onPressed: () => _cancel(id),
                  child: const Text('إلغاء'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- direct sale

class PosPanel extends StatefulWidget {
  final String shiftId;
  const PosPanel({super.key, required this.shiftId});
  @override
  State<PosPanel> createState() => _PosPanelState();
}

class _PosPanelState extends State<PosPanel> {
  late Future<Menu> _menu = _fetchMenu();
  String cat = 'all';
  double cashTotal = 0;
  double visaTotal = 0;
  final List<CartLine> ticket = [];
  String pay = 'cash';
  bool busy = false;
  double discount = 0;
  String discountReason = '';
  String note = '';
  double maxDiscountPct = 10;
  final List<List<CartLine>> held = [];

  double get _ticketTotal => ticket.fold<double>(0, (s, l) => s + l.total);
  double get _netTotal => (_ticketTotal - discount).clamp(0, double.infinity).toDouble();

  Future<void> _loadSettings() async {
    try {
      final row = await sb
          .from('app_settings')
          .select('value')
          .eq('key', 'pos')
          .maybeSingle();
      final v = (row?['value'] as Map?)?['max_discount_pct'];
      if (v is num && mounted) setState(() => maxDiscountPct = v.toDouble());
    } catch (_) {}
  }

  void _resetSale() {
    ticket.clear();
    discount = 0;
    discountReason = '';
    note = '';
  }

  Future<void> _askDiscount() async {
    if (ticket.isEmpty) return;
    final res = await showDialog<(double, String)>(
      context: context,
      builder: (_) => _DiscountDialog(
          total: _ticketTotal, maxPct: isSupervisor ? 100 : maxDiscountPct),
    );
    if (res != null && mounted) {
      setState(() {
        discount = res.$1;
        discountReason = res.$2;
      });
    }
  }

  Future<void> _askNote() async {
    final c = TextEditingController(text: note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ملاحظة على الفاتورة'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'مثال: بدون سكر / للعميل أحمد')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => note = c.text.trim());
  }

  void _hold() {
    if (ticket.isEmpty) return;
    setState(() {
      held.add(List.of(ticket));
      _resetSale();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('الفاتورة اتعلّقت. هتلاقيها في "المعلّقة".')));
  }

  Future<void> _recall() async {
    if (held.isEmpty) return;
    if (ticket.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خلّص الفاتورة الحالية أو علّقها الأول.')));
      return;
    }
    final i = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الفواتير المعلّقة'),
        content: SizedBox(
          width: 360,
          child: ListView(shrinkWrap: true, children: [
            for (var k = 0; k < held.length; k++)
              ListTile(
                title: Text(held[k].map((l) => l.title).join('، '),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(money(held[k].fold<double>(0, (s, l) => s + l.total))),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => Navigator.pop(ctx, -1 - k)),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('رجوع')),
        ],
      ),
    );
    if (i == null || !mounted) return;
    setState(() {
      if (i >= 0) {
        ticket.addAll(held.removeAt(i));
      } else {
        held.removeAt(-1 - i);
      }
    });
  }

  Future<void> _toggleSoldOut(Drink d) async {
    try {
      await sb.rpc('set_sold_out', params: {'p_drink': d.id, 'p_sold': d.available});
      if (mounted) {
        setState(() => _menu = _fetchMenu());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(d.available ? '${d.name} اتعلّم "خلص".' : '${d.name} رجع متاح.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pick(Menu menu, Drink d) async {
    final line = await showDialog<CartLine>(
      context: context,
      builder: (_) => _ItemDialog(drink: d, addons: menu.addons),
    );
    if (line != null && mounted) setState(() => ticket.add(line));
  }

  Future<void> _pay() async {
    if (ticket.isEmpty) return;
    if (discount > _ticketTotal) {
      setState(() {
        discount = 0;
        discountReason = '';
      });
    }
    if (discount > 0 &&
        !isSupervisor &&
        discount > (_ticketTotal * maxDiscountPct / 100) + 0.001) {
      showError(context, 'discount too high');
      return;
    }
    setState(() => busy = true);
    final ref = newRequestId();
    final sale = <String, dynamic>{
      'ref': ref,
      'items': ticket.map((l) => l.toJson()).toList(),
      'payment': pay,
      'seller': activeSellerId,
      'discount': discount,
      'reason': discountReason.isEmpty ? null : discountReason,
      'note': note.isEmpty ? null : note,
      'at': DateTime.now().toUtc().toIso8601String(),
      'total': _ticketTotal - discount,
      'label': fmtTime(DateTime.now().toUtc().toIso8601String()),
    };
    final localOrder = _localOrder(sale);
    try {
      if (!net.online) throw const SocketException('offline');
      final res = await sb.rpc('pos_sale', params: {
        'p_ref': ref,
        'p_items': sale['items'],
        'p_payment': pay,
        'p_seller': activeSellerId,
        'p_discount': discount,
        'p_reason': sale['reason'],
        'p_note': sale['note'],
        'p_at': null,
      }).timeout(const Duration(seconds: 15));
      final id = res as String;
      final order =
          await sb.from('orders').select(_orderSelect).eq('id', id).single();
      if (!mounted) return;
      final paidNow = (order['total'] as num?)?.toDouble() ?? _ticketTotal;
      setState(() {
        if (pay == 'cash') cashTotal += paidNow;
        if (pay == 'visa') visaTotal += paidNow;
        _resetSale();
        busy = false;
        _menu = _fetchMenu();
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم البيع. طلب رقم ${order['order_no']}')));
      try {
        await printReceipt(order);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    } catch (e) {
      if (!mounted) return;
      if (isNetworkError(e)) {
        // No internet: keep the sale on this device, print it, and let it
        // reach the server by itself when the connection is back.
        net.markOffline();
        await pendingSales.add(sale);
        if (!mounted) return;
        final paidNow = _ticketTotal - discount;
        setState(() {
          if (pay == 'cash') cashTotal += paidNow;
          if (pay == 'visa') visaTotal += paidNow;
          _resetSale();
          busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('مفيش نت • الفاتورة اتحفظت على الجهاز وهتتبعت لوحدها.'),
          duration: Duration(seconds: 5),
        ));
        try {
          await printReceipt(localOrder);
        } catch (_) {}
      } else {
        setState(() => busy = false);
        showError(context, e);
      }
    }
  }

  /// A receipt-shaped copy of a sale that has not reached the server yet.
  Map<String, dynamic> _localOrder(Map<String, dynamic> sale) {
    final lines = ticket.toList();
    return {
      'order_no': 'أوفلاين',
      'invoice_no': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'total': sale['total'],
      'discount': sale['discount'],
      'discount_reason': sale['reason'],
      'note': sale['note'],
      'payment_method': sale['payment'],
      'order_items': [
        for (final l in lines)
          {
            'size': l.size,
            'sugar': l.sugar,
            'qty': l.qty,
            'unit_price': l.unit,
            'drinks': {
              'name': l.drink.name,
              'is_coffee': l.drink.isCoffee,
              'drink_prices': [for (final k in l.drink.prices.keys) {'size': k}],
            },
            'order_item_addons': [
              for (final a in l.addons) {'price': a.price, 'addons': {'name': a.name}}
            ],
          }
      ],
    };
  }

  bool _menuFailed = false;

  Future<Menu> _fetchMenu() async {
    try {
      final m = await loadMenu();
      _menuFailed = false;
      return m;
    } catch (e) {
      _menuFailed = true;
      if (isNetworkError(e)) {
        net.markOffline();
        final cached = await loadMenuCache();
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  void _onNet() {
    if (net.online && _menuFailed && mounted) {
      setState(() {
        _menu = _fetchMenu();
      });
    }
  }

  Future<void> _loadTotals() async {
    try {
      final rows = await sb
          .from('orders')
          .select('total, payment_method')
          .eq('shift_id', widget.shiftId)
          .eq('payment_status', 'paid')
          .neq('status', 'cancelled');
      var c = 0.0, v = 0.0;
      for (final r in rows) {
        final t = (r['total'] as num?)?.toDouble() ?? 0;
        if (r['payment_method'] == 'cash') c += t;
        if (r['payment_method'] == 'visa') v += t;
      }
      if (mounted) setState(() {
        cashTotal = c;
        visaTotal = v;
      });
    } catch (_) {}
  }

  Future<void> _pickSeller() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _SellerDialog(),
    );
    if (picked != null && mounted) {
      setState(() {
        activeSellerId = picked['id'] as String;
        activeSellerName = picked['full_name'] as String? ?? '';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    activeSellerId ??= sb.auth.currentUser?.id;
    activeSellerName ??= (myStaff['full_name'] as String?) ?? 'البائع';
    net.addListener(_onNet);
    _loadTotals();
    _loadSettings();
  }

  @override
  void dispose() {
    net.removeListener(_onNet);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Menu>(
      future: _menu,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final off = isNetworkError(snap.error!);
          return ProblemView(
            offline: off,
            title: off ? 'انقطع الاتصال بالإنترنت' : 'مقدرناش نحمّل المنيو',
            hint: off
                ? 'هنحمّل المنيو لوحده أول ما النت يرجع.'
                : 'جرّب تاني بعد شوية.',
            onRetry: () {
              setState(() {
                _menu = _fetchMenu();
              });
            },
          );
        }
        final menu = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PendingBanner(),
            _topBar(),
            const Divider(height: 1, color: cHair),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 190, child: _categories(menu)),
                  const VerticalDivider(width: 1, color: cHair),
                  Expanded(child: _selector(menu)),
                  const VerticalDivider(width: 1, color: cHair),
                  SizedBox(width: 320, child: _ticket()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _total(String label, double v, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: cCream2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cHair),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: cBrand),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (w, a) => ScaleTransition(
                    scale: a, child: FadeTransition(opacity: a, child: w)),
                child: Text(money(v),
                    key: ValueKey(v),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: cBrand)),
              ),
            ],
          ),
        ),
      );

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.badge_outlined),
            label: Text('البائع: ${activeSellerName ?? ''}'),
            onPressed: _pickSeller,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('الفواتير'),
            onPressed: () async {
              final changed = await showDialog<bool>(
                context: context,
                builder: (_) => _RecentSalesDialog(shiftId: widget.shiftId),
              );
              if (changed == true) {
                _loadTotals();
                setState(() => _menu = _fetchMenu());
              }
            },
          ),
          IconButton(
            tooltip: 'الطابعة والبصمة',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => showDeviceSettings(context),
          ),
          const SizedBox(width: 8),
          _total('كاش', cashTotal, Icons.payments_outlined),
          const SizedBox(width: 10),
          _total('فيزا', visaTotal, Icons.credit_card),
        ],
      ),
    );
  }

  Widget _categories(Menu menu) {
    int count(String c) =>
        c == 'all' ? menu.drinks.length : menu.drinks.where((x) => x.category == c).length;
    final items = [
      for (final c in _posCats)
        if (c.$1 == 'all' || count(c.$1) > 0) c,
    ];
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        for (final c in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              selected: cat == c.$1,
              selectedTileColor: cBrand,
              selectedColor: cOnBrand,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: Icon(c.$3),
              title: Text(c.$2,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text('${count(c.$1)}',
                  style: const TextStyle(fontSize: 12)),
              onTap: () => setState(() => cat = c.$1),
            ),
          ),
      ],
    );
  }

  Widget _selector(Menu menu) {
    final list = cat == 'all'
        ? menu.drinks
        : menu.drinks.where((x) => x.category == cat).toList();
    final title = _posCats.firstWhere((c) => c.$1 == cat, orElse: () => _posCats.first).$2;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cat == 'all' ? 'بيع مباشر' : title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const Text('اضغط مطوّلاً على أي منتج لتعليمه "خلص" أو إرجاعه متاح.',
              style: TextStyle(color: cMuted, fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final x in list)
                SizedBox(
                  width: 150,
                  height: 84,
                  child: GestureDetector(
                    onLongPress: () => _toggleSoldOut(x),
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: x.available ? cCream2 : cCream,
                        foregroundColor: x.available ? cInk : cMuted,
                      ),
                      onPressed: x.available
                          ? () => _pick(menu, x)
                          : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('${x.name} خلص. اضغط مطوّلاً عشان ترجّعه متاح.'))),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(x.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(
                              !x.available
                                  ? 'خلص'
                                  : (x.stock != null && x.stock! <= 5
                                      ? 'باقي ${x.stock}'
                                      : (x.hasOptions
                                          ? 'من ${money(x.minPrice)}'
                                          : money(x.minPrice))),
                              style: TextStyle(
                                  color: !x.available
                                      ? cDanger
                                      : (x.stock != null && x.stock! <= 5 ? cGold : cBrand),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ticket() {
    return Container(
      color: cCream2,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('الفاتورة الحالية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Expanded(
            child: ticket.isEmpty
                ? const Center(
                    child: Text('فاضية', style: TextStyle(color: cMuted)))
                : ListView.separated(
                    itemCount: ticket.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: cHair, height: 12),
                    itemBuilder: (context, i) {
                      final l = ticket[i];
                      final notes = l.notes;
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text(notes,
                                    style: const TextStyle(
                                        color: cMuted, fontSize: 12)),
                              ],
                            ),
                          ),
                          Text(money(l.total),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          IconButton(
                            tooltip: 'شيل',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => ticket.removeAt(i)),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(color: cHair),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                  icon: const Icon(Icons.percent, size: 18),
                  label: Text(discount > 0 ? 'خصم ${money(discount)}' : 'خصم'),
                  onPressed: ticket.isEmpty ? null : _askDiscount),
              OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: Text(note.isEmpty ? 'ملاحظة' : 'ملاحظة ✓'),
                  onPressed: ticket.isEmpty ? null : _askNote),
              OutlinedButton.icon(
                  icon: const Icon(Icons.pause_circle_outline, size: 18),
                  label: const Text('تعليق'),
                  onPressed: ticket.isEmpty ? null : _hold),
              if (held.isNotEmpty)
                OutlinedButton.icon(
                    icon: const Icon(Icons.history, size: 18),
                    label: Text('المعلّقة (${held.length})'),
                    onPressed: _recall),
            ],
          ),
          const SizedBox(height: 8),
          if (discount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('خصم${discountReason.isEmpty ? '' : ' ($discountReason)'}',
                    style: const TextStyle(color: cMuted)),
                Text('-${money(discount)}', style: const TextStyle(color: cDanger)),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الإجمالي',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(money(_netTotal),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800, color: cBrand)),
            ],
          ),
          const SizedBox(height: 8),
          Choices<String>(
            values: const ['cash', 'visa', 'wallet'],
            selected: pay,
            label: (p) => p == 'cash' ? 'كاش' : (p == 'visa' ? 'فيزا' : 'محفظة'),
            onChanged: (v) => setState(() => pay = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cGreen,
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: busy || ticket.isEmpty ? null : _pay,
            child: const Text('ادفع واطبع الفاتورة'),
          ),
        ],
      ),
    );
  }
}

List<(String, String, IconData)> get _posCats => [
      ('all', 'الكل', Icons.apps),
      for (final c in menuCategories) (c.id, c.name, c.iconData),
    ];

/// Opens when a product is tapped: shows its price, options, extras and quantity.
class _ItemDialog extends StatefulWidget {
  final Drink drink;
  final List<Addon> addons;
  const _ItemDialog({required this.drink, required this.addons});
  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late String size = widget.drink.prices.containsKey('medium')
      ? 'medium'
      : widget.drink.prices.keys.first;
  String sugar = 'normal';
  int qty = 1;
  final Set<String> picked = {};

  CartLine get _line => CartLine(
        drink: widget.drink,
        size: size,
        sugar: sugar,
        qty: qty,
        addons: widget.addons.where((a) => picked.contains(a.id)).toList(),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.drink;
    final sizes = sizeKeys.where(d.prices.containsKey).toList();
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(d.name)),
          Text(money(d.prices[size] ?? d.minPrice),
              style: const TextStyle(
                  color: cBrand, fontWeight: FontWeight.w800)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (d.hasOptions) ...[
                const SectionLabel('الحجم'),
                Choices<String>(
                  values: sizes,
                  selected: size,
                  label: (s) => '${sizeLabel[s]}  ${money(d.prices[s] ?? 0)}',
                  onChanged: (v) => setState(() => size = v),
                ),
                const SectionLabel('السكر'),
                Choices<String>(
                  values: sugarKeysFor(d.isCoffee),
                  selected: sugar,
                  label: (s) => sugarLabelFor(d.isCoffee, s),
                  onChanged: (v) => setState(() => sugar = v),
                ),
              ],
              if (widget.addons.isNotEmpty) ...[
                const SectionLabel('إضافات'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in widget.addons)
                      FilterChip(
                        label: Text('${a.name}  +${money(a.price)}'),
                        selected: picked.contains(a.id),
                        showCheckmark: false,
                        selectedColor: cGold,
                        backgroundColor: cCream2,
                        side: const BorderSide(color: cHair),
                        onSelected: (v) => setState(() {
                          if (v) {
                            picked.add(a.id);
                          } else {
                            picked.remove(a.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SectionLabel('الكمية'),
              if (d.stock != null && d.stock! <= 10)
                Text('باقي ${d.stock} بس', style: const TextStyle(color: cGold)),
              Row(
                children: [
                  IconButton.outlined(
                    icon: const Icon(Icons.remove),
                    onPressed: qty > 1 ? () => setState(() => qty--) : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text('$qty',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  IconButton.outlined(
                    icon: const Icon(Icons.add),
                    onPressed: qty < (d.stock != null && d.stock! < 20 ? d.stock! : 20)
                        ? () => setState(() => qty++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cBrand),
          onPressed: () => Navigator.pop(context, _line),
          child: Text('أضف للفاتورة • ${money(_line.total)}'),
        ),
      ],
    );
  }
}

/// Pick who is selling right now. No password: just choose a name.
class _SellerDialog extends StatefulWidget {
  const _SellerDialog();
  @override
  State<_SellerDialog> createState() => _SellerDialogState();
}

class _SellerDialogState extends State<_SellerDialog> {
  late final Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await sb
        .from('profiles')
        .select('id, full_name, staff_role')
        .not('staff_role', 'is', null)
        .eq('active', true)
        .order('full_name');
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مين البائع دلوقتي؟'),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 80, child: Center(child: CircularProgressIndicator()));
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return const Text('مفيش موظفين متسجلين لسه.');
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final p in list)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text((p['full_name'] as String?)?.trim().isNotEmpty == true
                        ? p['full_name'] as String
                        : 'بدون اسم'),
                    subtitle: Text(jobLabels[p['staff_role']] ?? ''),
                    selected: p['id'] == activeSellerId,
                    onTap: () => Navigator.pop(context, p),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      ],
    );
  }
}

/// Discount by percent or fixed amount, with a reason. Non-supervisors are capped.
class _DiscountDialog extends StatefulWidget {
  final double total;
  final double maxPct;
  const _DiscountDialog({required this.total, required this.maxPct});
  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  final _v = TextEditingController();
  final _r = TextEditingController();
  bool pct = true;
  String? err;

  void _ok() {
    final x = double.tryParse(_v.text.trim().replaceAll(',', '.'));
    if (x == null || x <= 0) {
      setState(() => err = 'اكتب رقم أكبر من صفر.');
      return;
    }
    final amount = pct ? (widget.total * x / 100) : x;
    final a = (amount * 100).round() / 100;
    if (a > widget.total) {
      setState(() => err = 'الخصم أكبر من الفاتورة.');
      return;
    }
    if (a > widget.total * widget.maxPct / 100 + 0.001) {
      setState(() => err =
          'الحد المسموح ليك ${widget.maxPct.toStringAsFixed(0)}٪ من الفاتورة. اطلب من المدير.');
      return;
    }
    if (_r.text.trim().isEmpty) {
      setState(() => err = 'اكتب سبب الخصم.');
      return;
    }
    Navigator.pop(context, (a, _r.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('خصم على الفاتورة'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Choices<bool>(
              values: const [true, false],
              selected: pct,
              label: (b) => b ? 'نسبة ٪' : 'مبلغ ج',
              onChanged: (v) => setState(() => pct = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _v,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: pct ? 'نسبة الخصم' : 'مبلغ الخصم (ج)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _r,
              decoration: const InputDecoration(labelText: 'سبب الخصم'),
              onSubmitted: (_) => _ok(),
            ),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(err!, style: const TextStyle(color: cDanger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
        FilledButton(onPressed: _ok, child: const Text('تطبيق الخصم')),
      ],
    );
  }
}

/// Asks for a short written reason. Returns null when cancelled or empty.
Future<String?> askReason(BuildContext context, String title, String label) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
      ],
    ),
  );
  final v = c.text.trim();
  if (ok != true || v.isEmpty) return null;
  return v;
}

/// This shift's sales: reprint a receipt or cancel (void) a sale with a reason.
class _RecentSalesDialog extends StatefulWidget {
  final String shiftId;
  const _RecentSalesDialog({required this.shiftId});
  @override
  State<_RecentSalesDialog> createState() => _RecentSalesDialogState();
}

class _RecentSalesDialogState extends State<_RecentSalesDialog> {
  List<Map<String, dynamic>>? rows;
  Object? error;
  bool changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await sb
          .from('orders')
          .select(_orderSelect)
          .eq('shift_id', widget.shiftId)
          .order('created_at', ascending: false)
          .limit(40);
      if (mounted) setState(() => rows = r.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> _void(Map<String, dynamic> o) async {
    final reason = await askReason(context, 'إلغاء الفاتورة', 'سبب الإلغاء');
    if (reason == null) return;
    try {
      await sb.rpc('cancel_order', params: {'p_order': o['id'], 'p_reason': reason});
      changed = true;
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = rows;
    return AlertDialog(
      title: const Text('فواتير الوردية'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: error != null
            ? Text(errorText(error!))
            : r == null
                ? const Center(child: CircularProgressIndicator())
                : r.isEmpty
                    ? const Center(child: Text('مفيش فواتير لسه.'))
                    : ListView.separated(
                        itemCount: r.length,
                        separatorBuilder: (_, __) => const Divider(color: cHair, height: 1),
                        itemBuilder: (_, i) {
                          final o = r[i];
                          final cancelled = o['status'] == 'cancelled';
                          final pm = o['payment_method'];
                          return ListTile(
                            dense: true,
                            title: Text(
                                '${o['invoice_no'] != null ? 'فاتورة ${o['invoice_no']}' : 'طلب ${o['order_no']}'}'
                                '  •  ${fmtTime(o['created_at'] as String)}',
                                style: TextStyle(
                                    decoration: cancelled ? TextDecoration.lineThrough : null,
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(
                                '${pm == 'cash' ? 'كاش' : (pm == 'visa' ? 'فيزا' : 'محفظة')}'
                                '${cancelled ? ' • ملغية: ${o['cancel_reason'] ?? ''}' : ''}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(money(o['total'] as num),
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                              IconButton(
                                tooltip: 'طباعة',
                                icon: const Icon(Icons.print_outlined),
                                onPressed: () async {
                                  try {
                                    await printReceipt(o);
                                  } catch (e) {
                                    if (mounted) showError(context, e);
                                  }
                                },
                              ),
                              if (!cancelled)
                                IconButton(
                                  tooltip: 'إلغاء الفاتورة',
                                  color: cDanger,
                                  icon: const Icon(Icons.cancel_outlined),
                                  onPressed: () => _void(o),
                                ),
                            ]),
                          );
                        },
                      ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context, changed), child: const Text('تمام')),
      ],
    );
  }
}

// ---------------------------------------------------------------- shift report

class ShiftDialog extends StatefulWidget {
  final String shiftId;
  final VoidCallback onClosed;
  const ShiftDialog({super.key, required this.shiftId, required this.onClosed});
  @override
  State<ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<ShiftDialog> {
  Map<String, dynamic>? report;
  Object? error;
  final _actual = TextEditingController();
  final _note = TextEditingController();
  bool busy = false;
  static const _closing = [
    'عدّ الكاش اللي في الدرج واكتبه تحت.',
    'راجع إيصالات الفيزا مع مبلغ مبيعات الفيزا فوق.',
    'نضّف العربية والمكنة والأسطح.',
    'اقفل الغاز والكهربا وأي جهاز شغال.',
    'سلّم الدرج والمفاتيح، وسجّل أي نقص في الملاحظة.',
  ];
  final List<bool> _done = List.filled(5, false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await sb.rpc('shift_report', params: {'p_shift': widget.shiftId});
      if (mounted) {
        setState(() => report = Map<String, dynamic>.from(r as Map));
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> _close() async {
    if (pendingSales.count > 0) {
      showError(context,
          'فيه ${pendingSales.count} فاتورة لسه متبعتتش للسيرفر. استنى النت يرجع وتتبعت، وبعدها اقفل الوردية.');
      return;
    }
    final actual = double.tryParse(_actual.text.trim());
    if (actual == null) {
      showError(context, 'اكتب الكاش الفعلي اللي في الدرج.');
      return;
    }
    setState(() => busy = true);
    try {
      final r = await sb.rpc('close_shift', params: {
        'p_shift': widget.shiftId,
        'p_actual': actual,
        'p_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      final res = Map<String, dynamic>.from(r as Map);
      if (!mounted) return;
      final diff = (res['difference'] as num).toDouble();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('اتقفلت الوردية'),
          content: Text(
              'الفرق بين الكاش المتوقع والفعلي: ${money(diff)}\n'
              '${diff == 0 ? 'الكاش مظبوط.' : (diff > 0 ? 'زيادة في الدرج.' : 'عجز في الدرج.')}\n\n'
              'تسلم إيدك النهاردة. ربنا يبارك لك في رزقك وتروح بالسلامة.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
      widget.onClosed();
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showError(context, e);
      }
    }
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(k), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = report;
    return AlertDialog(
      title: const Text('تقرير الوردية'),
      content: SizedBox(
        width: 420,
        child: error != null
            ? Text(errorText(error!))
            : r == null
                ? const SizedBox(
                    height: 80, child: Center(child: CircularProgressIndicator()))
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _row('كاش بداية الوردية', money(r['opening_cash'] as num)),
                        _row('مبيعات كاش', money(r['cash_sales'] as num)),
                        _row('مبيعات فيزا', money((r['visa_sales'] ?? 0) as num)),
                        _row('مبيعات محفظة', money(r['wallet_sales'] as num)),
                        if (((r['discounts'] ?? 0) as num) > 0)
                          _row('خصومات', money((r['discounts']) as num)),
                        if (((r['refunds'] ?? 0) as num) > 0)
                          _row('فواتير ملغية (مرتجع)', money((r['refunds']) as num)),
                        _row('الكاش المتوقع في الدرج', money(r['expected_cash'] as num)),
                        _row('عدد الأكواب', '${r['cups']}'),
                        _row('طلبات ملغية', '${r['cancelled']}'),
                        const Divider(color: cHair),
                        for (final x in (r['by_drink'] as List))
                          _row('${(x as Map)['name']}', '${x['cups']}'),
                        const Divider(color: cHair),
                        const Text('قبل ما تقفل',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: cBrand)),
                        for (var i = 0; i < _closing.length; i++)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(_closing[i]),
                            value: _done[i],
                            onChanged: (v) => setState(() => _done[i] = v ?? false),
                          ),
                        const Divider(color: cHair),
                        TextField(
                          controller: _actual,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'الكاش الفعلي في الدرج (ج)'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _note,
                          decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
                        ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('رجوع'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cDanger),
          onPressed: busy || r == null ? null : _close,
          child: const Text('قفل الوردية'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- receipt

Future<void> printReceipt(Map<String, dynamic> order) async {
  final (regular, bold) = await receiptFonts();
  pw.Widget t(String s, {bool b = false, double size = 10}) => pw.Text(
        s,
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(font: b ? bold : regular, fontSize: size),
      );
  final items = (order['order_items'] as List).cast<Map<String, dynamic>>();
  final isCash = order['payment_method'] == 'cash';
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(10),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: t('BONNAYA', b: true, size: 20)),
          pw.SizedBox(height: 4),
          t('${order['invoice_no'] != null ? 'فاتورة رقم ${order['invoice_no']}  •  ' : ''}طلب رقم ${order['order_no']}  •  ${fmtTime(order['created_at'] as String)}'),
          pw.Divider(),
          for (final it in items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      t(money(itemTotal(it)), b: true),
                      t(itemTitle(it), b: true),
                    ],
                  ),
                  t(itemNotes(it), size: 8),
                ],
              ),
            ),
          pw.Divider(),
          if (((order['discount'] as num?) ?? 0) > 0)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                t('-${money(order['discount'] as num)}'),
                t('خصم${(order['discount_reason'] as String?)?.isNotEmpty == true ? ' (${order['discount_reason']})' : ''}'),
              ],
            ),
          if ((order['note'] as String?)?.isNotEmpty == true) t('ملاحظة: ${order['note']}', size: 9),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              t(money(order['total'] as num), b: true, size: 14),
              t('الإجمالي', b: true, size: 14),
            ],
          ),
          pw.SizedBox(height: 4),
          t(isCash ? 'الدفع: كاش' : (order['payment_method'] == 'visa' ? 'الدفع: فيزا' : 'الدفع: محفظة إلكترونية')),
          pw.SizedBox(height: 8),
          pw.Center(child: t('شكرًا لزيارتك بنايه', size: 9)),
        ],
      ),
    ),
  );
  await printDoc('bonnaya-${order['order_no']}', doc);
}
