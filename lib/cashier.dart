import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'core.dart';
import 'update.dart';

const _orderSelect =
    '*, profiles(full_name), order_items(*, drinks(name), order_item_addons(*, addons(name)))';

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
  const CashierGate({super.key});
  @override
  State<CashierGate> createState() => _CashierGateState();
}

class _CashierGateState extends State<CashierGate> {
  late Future<Map<String, dynamic>> _state = _load();

  Future<Map<String, dynamic>> _load() async {
    final uid = sb.auth.currentUser!.id;
    final prof =
        await sb.from('profiles').select('role').eq('id', uid).maybeSingle();
    final role = prof?['role'];
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
        final shift = s['shift'];
        if (shift == null) return OpenShiftPage(onOpened: _reload);
        return CashierHome(
          shift: shift as Map<String, dynamic>,
          onClosed: _reload,
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
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      await sb.from('shifts').insert({
        'cashier_id': sb.auth.currentUser!.id,
        'opening_cash': double.tryParse(_cash.text.trim()) ?? 0,
      });
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
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: () => sb.auth.signOut(),
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
              const Text('افتح الوردية',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('اكتب الكاش اللي في الدرج دلوقتي.',
                  style: TextStyle(color: cMuted)),
              const SizedBox(height: 16),
              TextField(
                controller: _cash,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'كاش بداية الوردية (ج)'),
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

class CashierHome extends StatelessWidget {
  final Map<String, dynamic> shift;
  final VoidCallback onClosed;
  const CashierHome({super.key, required this.shift, required this.onClosed});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'BONNAYA • كاشير  (وردية من ${fmtTime(shift['opened_at'] as String)})'),
        actions: [
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
            onPressed: () => sb.auth.signOut(),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: 440, child: OnlineOrdersPanel()),
          const VerticalDivider(width: 1, color: cHair),
          const Expanded(child: PosPanel()),
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
          .inFilter('status', ['received', 'preparing', 'ready'])
          .order('created_at');
      final fresh = rows
          .where((o) => o['status'] == 'received' && !_seen.contains(o['id']))
          .toList();
      for (final o in rows) {
        _seen.add(o['id'] as String);
      }
      if (!_first && fresh.isNotEmpty) {
        SystemSound.play(SystemSoundType.alert);
      }
      _first = false;
      if (mounted) {
        setState(() {
          _orders = rows;
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

  Future<void> _paid(String id) async {
    try {
      await sb.rpc('set_order_paid', params: {'p_order': id});
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _cancel(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الطلب؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لأ')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إلغاء الطلب')),
        ],
      ),
    );
    if (ok == true) await _status(id, 'cancelled');
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
    final chipColor = st == 'received'
        ? cGold
        : st == 'preparing'
            ? cGreen
            : cCream;
    final chipText = st == 'preparing' ? cInk : cOnBrand;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: st == 'received' ? cCream2 : cCream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: st == 'received' ? cBrand : cHair, width: 2),
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
              if (st == 'received')
                Expanded(
                  child: FilledButton(
                    onPressed: () => _status(id, 'preparing'),
                    child: const Text('ابدأ التحضير'),
                  ),
                ),
              if (st == 'preparing')
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cGreen),
                    onPressed: () => _status(id, 'ready'),
                    child: const Text('جهّزت الطلب'),
                  ),
                ),
              if (st == 'ready')
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
              if (!isCash && !paid)
                TextButton(
                  onPressed: () => _paid(id),
                  child: const Text('تأكيد الدفع'),
                ),
              const Spacer(),
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
  const PosPanel({super.key});
  @override
  State<PosPanel> createState() => _PosPanelState();
}

class _PosPanelState extends State<PosPanel> {
  late Future<Menu> _menu = _fetchMenu();
  Drink? drink;
  String size = 'medium';
  String sugar = 'normal';
  int qty = 1;
  final Set<String> picked = {};
  final List<CartLine> ticket = [];
  String pay = 'cash';
  bool busy = false;

  double get _ticketTotal => ticket.fold<double>(0, (s, l) => s + l.total);

  void _addLine(Menu menu) {
    final d = drink;
    if (d == null) return;
    final sz = d.prices.containsKey(size) ? size : d.prices.keys.first;
    setState(() {
      ticket.add(CartLine(
        drink: d,
        size: sz,
        sugar: sugar,
        qty: qty,
        addons: menu.addons.where((a) => picked.contains(a.id)).toList(),
      ));
      drink = null;
      qty = 1;
      picked.clear();
    });
  }

  Future<void> _pay() async {
    if (ticket.isEmpty) return;
    setState(() => busy = true);
    try {
      final res = await sb.rpc('place_order', params: {
        'p_items': ticket.map((l) => l.toJson()).toList(),
        'p_payment': pay,
        'p_source': 'pos',
      });
      final id = res as String;
      final order =
          await sb.from('orders').select(_orderSelect).eq('id', id).single();
      if (!mounted) return;
      setState(() {
        ticket.clear();
        busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم البيع. طلب رقم ${order['order_no']}')));
      try {
        await printReceipt(order);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        if (isNetworkError(e)) {
          net.markOffline();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'انقطع الاتصال والفاتورة لسه متسجّلتش. الفاتورة محفوظة قدامك، ادفع تاني لما النت يرجع. ولو مش متأكد إنها اتسجّلت، راجع تقرير الوردية الأول.'),
            duration: Duration(seconds: 8),
          ));
        } else {
          showError(context, e);
        }
      }
    }
  }

  bool _menuFailed = false;

  Future<Menu> _fetchMenu() async {
    try {
      final m = await loadMenu();
      _menuFailed = false;
      return m;
    } catch (e) {
      _menuFailed = true;
      if (isNetworkError(e)) net.markOffline();
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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _selector(menu)),
            const VerticalDivider(width: 1, color: cHair),
            SizedBox(width: 320, child: _ticket()),
          ],
        );
      },
    );
  }

  Widget _selector(Menu menu) {
    final d = drink;
    final sizes = d == null
        ? sizeKeys
        : sizeKeys.where(d.prices.containsKey).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('بيع مباشر',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final x in menu.drinks)
                SizedBox(
                  width: 150,
                  height: 72,
                  child: x.id == d?.id
                      ? FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: cInk),
                          onPressed: () => setState(() => drink = x),
                          child: Text(x.name, textAlign: TextAlign.center),
                        )
                      : FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: cCream2,
                            foregroundColor: cInk,
                          ),
                          onPressed: () => setState(() => drink = x),
                          child: Text(x.name, textAlign: TextAlign.center),
                        ),
                ),
            ],
          ),
          const SectionLabel('الحجم'),
          Choices<String>(
            values: sizes,
            selected: size,
            label: (s) => d == null
                ? sizeLabel[s]!
                : '${sizeLabel[s]}  ${money(d.prices[s] ?? 0)}',
            onChanged: (v) => setState(() => size = v),
          ),
          const SectionLabel('السكر'),
          Choices<String>(
            values: sugarKeys,
            selected: sugar,
            label: (s) => sugarLabel[s]!,
            onChanged: (v) => setState(() => sugar = v),
          ),
          const SectionLabel('إضافات'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in menu.addons)
                FilterChip(
                  label: Text('${a.name}  +${money(a.price)}'),
                  selected: picked.contains(a.id),
                  showCheckmark: false,
                  selectedColor: cGold,
                  backgroundColor: cCream2,
                  side: const BorderSide(color: cHair),
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        picked.add(a.id);
                      } else {
                        picked.remove(a.id);
                      }
                    });
                  },
                ),
            ],
          ),
          const SectionLabel('الكمية'),
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
                onPressed: qty < 20 ? () => setState(() => qty++) : null,
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cBrand,
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: d == null ? null : () => _addLine(menu),
            child: Text(d == null ? 'اختار المشروب الأول' : 'أضف للفاتورة'),
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
                      final notes = [
                        sugarDesc[l.sugar] ?? '',
                        for (final a in l.addons) '+ ${a.name}',
                      ].join(' · ');
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${l.drink.name} ${sizeLabel[l.size]} × ${l.qty}',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الإجمالي',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(money(_ticketTotal),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800, color: cBrand)),
            ],
          ),
          const SizedBox(height: 8),
          Choices<String>(
            values: const ['cash', 'wallet'],
            selected: pay,
            label: (p) => p == 'cash' ? 'كاش' : 'محفظة',
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
              '${diff == 0 ? 'الكاش مظبوط.' : (diff > 0 ? 'زيادة في الدرج.' : 'عجز في الدرج.')}'),
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
                        _row('مبيعات محفظة', money(r['wallet_sales'] as num)),
                        _row('الكاش المتوقع في الدرج', money(r['expected_cash'] as num)),
                        _row('عدد الأكواب', '${r['cups']}'),
                        _row('طلبات ملغية', '${r['cancelled']}'),
                        const Divider(color: cHair),
                        for (final x in (r['by_drink'] as List))
                          _row('${(x as Map)['name']}', '${x['cups']}'),
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
  final regular = await PdfGoogleFonts.cairoRegular();
  final bold = await PdfGoogleFonts.cairoBold();
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
          t('طلب رقم ${order['order_no']}  •  ${fmtTime(order['created_at'] as String)}'),
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
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              t(money(order['total'] as num), b: true, size: 14),
              t('الإجمالي', b: true, size: 14),
            ],
          ),
          pw.SizedBox(height: 4),
          t(isCash ? 'الدفع: كاش' : 'الدفع: محفظة إلكترونية'),
          pw.SizedBox(height: 8),
          pw.Center(child: t('شكرًا لزيارتك بنايه', size: 9)),
        ],
      ),
    ),
  );
  await Printing.layoutPdf(
    name: 'bonnaya-${order['order_no']}',
    onLayout: (format) async => doc.save(),
  );
}
