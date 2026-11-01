import 'dart:async';

import 'package:flutter/material.dart';

import 'core.dart';

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return nasyaMaterialApp(
      AuthGate(
        signedIn: () => const HomePage(),
        signedOut: const AuthPage(title: 'قهوتك تستناك قبل ما توصل'),
      ),
    );
  }
}

// ---------------------------------------------------------------- menu

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _failed = false;
  late Future<Menu> _menu = _fetch();

  Future<Menu> _fetch() async {
    try {
      final m = await loadMenu();
      _failed = false;
      return m;
    } catch (e) {
      _failed = true;
      if (isNetworkError(e)) net.markOffline();
      rethrow;
    }
  }

  // The menu loads by itself as soon as the connection comes back.
  void _onNet() {
    if (net.online && _failed && mounted) {
      setState(() {
        _menu = _fetch();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('BONNAYA',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
        actions: [
          IconButton(
            tooltip: 'طلباتي',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrdersPage()),
            ),
          ),
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: () => sb.auth.signOut(),
          ),
        ],
      ),
      body: FutureBuilder<Menu>(
        future: _menu,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final off = isNetworkError(snap.error!);
            return ProblemView(
              offline: off,
              title: off ? 'انقطع الاتصال بالإنترنت' : 'حصلت مشكلة وإحنا بنحمّل المنيو',
              hint: off
                  ? 'هنحمّل المنيو لوحده أول ما النت يرجع.'
                  : 'جرّب تاني بعد شوية.',
              onRetry: () {
                setState(() {
                  _menu = _fetch();
                });
              },
            );
          }
          final menu = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text('عايز تشرب إيه؟',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('اطلب وانت في الطريق، وقهوتك تلاقيها جاهزة.',
                  style: TextStyle(color: cMuted)),
              const SizedBox(height: 16),
              for (final d in menu.drinks) DrinkTile(drink: d, addons: menu.addons),
            ],
          );
        },
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          if (cart.lines.isEmpty) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartPage()),
                ),
                child: Text('كمّل الطلب  •  ${money(cart.total)}',
                    style: const TextStyle(fontSize: 17)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class DrinkTile extends StatelessWidget {
  final Drink drink;
  final List<Addon> addons;
  const DrinkTile({super.key, required this.drink, required this.addons});

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cCream,
      builder: (_) => DrinkSheet(drink: drink, addons: addons),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cCream2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: cHair),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          onTap: () => _open(context),
          leading: const CircleAvatar(
            radius: 28,
            backgroundColor: cCream,
            foregroundColor: cBrand,
            child: Icon(Icons.local_cafe_outlined, size: 28),
          ),
          title: Text(drink.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          subtitle: Text('من ${money(drink.minPrice)}',
              style: const TextStyle(
                  color: cBrand, fontWeight: FontWeight.w700, fontSize: 15)),
          trailing: IconButton.filled(
            tooltip: 'أضف ${drink.name}',
            icon: const Icon(Icons.add),
            onPressed: () => _open(context),
          ),
        ),
      ),
    );
  }
}

class DrinkSheet extends StatefulWidget {
  final Drink drink;
  final List<Addon> addons;
  const DrinkSheet({super.key, required this.drink, required this.addons});
  @override
  State<DrinkSheet> createState() => _DrinkSheetState();
}

class _DrinkSheetState extends State<DrinkSheet> {
  late String size = widget.drink.prices.containsKey('medium')
      ? 'medium'
      : widget.drink.prices.keys.first;
  String sugar = 'normal';
  int qty = 1;
  final Set<String> picked = {};

  List<Addon> get _pickedAddons =>
      widget.addons.where((a) => picked.contains(a.id)).toList();

  double get _total {
    final unit = widget.drink.prices[size] ?? 0;
    final extra = _pickedAddons.fold<double>(0, (s, a) => s + a.price);
    return (unit + extra) * qty;
  }

  @override
  Widget build(BuildContext context) {
    final sizes = sizeKeys.where(widget.drink.prices.containsKey).toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.drink.name,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SectionLabel('الحجم'),
            Choices<String>(
              values: sizes,
              selected: size,
              label: (s) => '${sizeLabel[s]}  ${money(widget.drink.prices[s]!)}',
              onChanged: (v) => setState(() => size = v),
            ),
            const SectionLabel('السكر'),
            Choices<String>(
              values: sugarKeys,
              selected: sugar,
              label: (s) => sugarLabel[s]!,
              onChanged: (v) => setState(() => sugar = v),
            ),
            if (widget.addons.isNotEmpty) const SectionLabel('إضافات'),
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
                  tooltip: 'قلّل',
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
                  tooltip: 'زوّد',
                  icon: const Icon(Icons.add),
                  onPressed: qty < 20 ? () => setState(() => qty++) : null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56)),
              onPressed: () {
                cart.add(CartLine(
                  drink: widget.drink,
                  size: size,
                  sugar: sugar,
                  qty: qty,
                  addons: _pickedAddons,
                ));
                Navigator.pop(context);
              },
              child: Text('أضف للطلب  •  ${money(_total)}',
                  style: const TextStyle(fontSize: 17)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- cart

class CartPage extends StatefulWidget {
  const CartPage({super.key});
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  String pay = 'cash';
  int eta = 10;
  bool busy = false;
  // True after the customer pressed send but the connection was down: we send by ourselves
  // as soon as it returns. The same request id guarantees one order even if we retry.
  bool waiting = false;
  final String requestId = newRequestId();

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

  void _onNet() {
    if (net.online && waiting && !busy && mounted) _place();
  }

  Future<void> _place() async {
    if (busy) return;
    if (!net.online) {
      setState(() => waiting = true);
      return;
    }
    setState(() {
      busy = true;
      waiting = false;
    });
    try {
      final res = await sb.rpc('place_order_v2', params: {
        'p_request_id': requestId,
        'p_items': cart.lines.map((l) => l.toJson()).toList(),
        'p_payment': pay,
        'p_eta': eta,
        'p_source': 'app',
      });
      final id = res as String;
      cart.clear();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => TrackPage(orderId: id)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        waiting = isNetworkError(e);
      });
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلبك')),
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          if (cart.lines.isEmpty) {
            return const Center(child: Text('الطلب فاضي'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (var i = 0; i < cart.lines.length; i++) _line(i),
              const SectionLabel('هتوصل بعد قد إيه؟'),
              Choices<int>(
                values: const [5, 10, 15],
                selected: eta,
                label: (m) => '$m دقيقة',
                onChanged: (v) => setState(() => eta = v),
              ),
              const SectionLabel('الدفع'),
              Choices<String>(
                values: const ['cash', 'wallet'],
                selected: pay,
                label: (p) => p == 'cash' ? 'كاش عند الاستلام' : 'محفظة إلكترونية',
                onChanged: (v) => setState(() => pay = v),
              ),
              if (pay == 'wallet')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'الدفع بالمحفظة بيتأكد عند الاستلام. الربط مع بوابة دفع هييجي في مرحلة تانية.',
                    style: TextStyle(color: cMuted, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 24),
              if (waiting)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cCream2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cGold, width: 2),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: cMuted),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'مفيش إنترنت دلوقتي. طلبك محفوظ وهيتبعت لوحده أول ما النت يرجع، متقفلش الصفحة.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56)),
                onPressed: busy ? null : _place,
                child: Text(
                    waiting
                        ? 'استنى النت وابعت  •  ${money(cart.total)}'
                        : 'ابعت الطلب  •  ${money(cart.total)}',
                    style: const TextStyle(fontSize: 17)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _line(int i) {
    final l = cart.lines[i];
    final notes = [
      sugarDesc[l.sugar] ?? '',
      for (final a in l.addons) '+ ${a.name}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cCream2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cHair),
      ),
      child: ListTile(
        title: Text('${l.drink.name} ${sizeLabel[l.size]} × ${l.qty}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$notes\n${money(l.total)}'),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'شيل',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => cart.removeAt(i),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- tracking

class TrackPage extends StatefulWidget {
  final String orderId;
  const TrackPage({super.key, required this.orderId});
  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage> {
  Map<String, dynamic>? order;
  Object? _error;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = sb
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', widget.orderId)
        .listen((_) => _load());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    net.addListener(_onNet);
  }

  @override
  void dispose() {
    net.removeListener(_onNet);
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  // Refresh right away when the connection returns.
  void _onNet() {
    if (net.online && mounted) _load();
  }

  Future<void> _load() async {
    try {
      final r = await sb
          .from('orders')
          .select(
              '*, order_items(*, drinks(name), order_item_addons(*, addons(name)))')
          .eq('id', widget.orderId)
          .single();
      if (mounted) {
        setState(() {
          order = r;
          _error = null;
        });
      }
    } catch (e) {
      // keep the last known state; the next refresh retries
      if (isNetworkError(e)) net.markOffline();
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final err = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('تتبع الطلب')),
      body: o != null
          ? _body(o)
          : err != null
              ? ProblemView(
                  offline: isNetworkError(err),
                  title: isNetworkError(err)
                      ? 'انقطع الاتصال بالإنترنت'
                      : 'مقدرناش نفتح الطلب',
                  hint: isNetworkError(err)
                      ? 'هنفتح الطلب لوحده أول ما النت يرجع.'
                      : 'جرّب تاني بعد شوية.',
                  onRetry: _load,
                )
              : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _body(Map<String, dynamic> o) {
    final status = o['status'] as String;
    final items = (o['order_items'] as List).cast<Map<String, dynamic>>();
    final idx = const ['received', 'preparing', 'ready', 'delivered']
        .indexOf(status);
    final eta = o['eta_minutes'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListenableBuilder(
          listenable: net,
          builder: (context, _) {
            if (net.online) return const SizedBox.shrink();
            return const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'مش قادرين نحدّث حالة الطلب لأن النت قاطع. هنحدّثها أول ما يرجع، وطلبك ماشي عادي.',
                style: TextStyle(color: cMuted),
              ),
            );
          },
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cInk,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('طلب رقم ${o['order_no']}',
                  style: const TextStyle(color: cHair)),
              const SizedBox(height: 4),
              Text(statusLabel[status] ?? status,
                  style: const TextStyle(
                      color: cCream, fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                status == 'ready'
                    ? 'قهوتك جاهزة، العربية مستنياك.'
                    : status == 'cancelled'
                        ? 'الطلب اتلغى. لو فيه مشكلة كلّم بنايه.'
                        : status == 'delivered'
                            ? 'بالهنا والشفا.'
                            : eta != null
                                ? 'بتوصل بعد حوالي $eta دقيقة.'
                                : 'جاري تجهيز طلبك.',
                style: const TextStyle(color: cCream2),
              ),
            ],
          ),
        ),
        if (status != 'cancelled') ...[
          const SizedBox(height: 20),
          _step('تم استلام الطلب', 0, idx),
          _step('جاري التحضير', 1, idx),
          _step('جاهز للاستلام', 2, idx),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cCream2,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cHair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final it in items) ...[
                Text(itemTitle(it),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(itemNotes(it),
                    style: const TextStyle(color: cMuted, fontSize: 13)),
                const SizedBox(height: 10),
              ],
              const Divider(color: cHair),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(o['payment_method'] == 'cash'
                      ? 'كاش عند الاستلام'
                      : 'محفظة إلكترونية'),
                  Text(money(o['total'] as num),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: cBrand)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _step(String title, int i, int idx) {
    final done = idx > i;
    final current = idx == i;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? cGreen : cCream,
              border: Border.all(
                  color: done ? cGreen : (current ? cBrand : cHair), width: 3),
            ),
            child: done
                ? const Icon(Icons.check, size: 18, color: cCream)
                : current
                    ? const Center(
                        child: CircleAvatar(radius: 5, backgroundColor: cBrand))
                    : null,
          ),
          const SizedBox(width: 14),
          Text(title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: current ? cBrand : (done ? cInk : cMuted),
              )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- my orders

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  bool _failed = false;
  late Future<List<Map<String, dynamic>>> _orders = _fetch();

  Future<List<Map<String, dynamic>>> _fetch() async {
    try {
      final rows = await sb
          .from('orders')
          .select('id, order_no, status, total, created_at')
          .order('created_at', ascending: false)
          .limit(30);
      _failed = false;
      return rows;
    } catch (e) {
      _failed = true;
      if (isNetworkError(e)) net.markOffline();
      rethrow;
    }
  }

  void _onNet() {
    if (net.online && _failed && mounted) {
      setState(() {
        _orders = _fetch();
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
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _orders,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final off = isNetworkError(snap.error!);
            return ProblemView(
              offline: off,
              title: off ? 'انقطع الاتصال بالإنترنت' : 'مقدرناش نحمّل الطلبات',
              hint: off
                  ? 'هنحمّل طلباتك لوحدها أول ما النت يرجع.'
                  : 'جرّب تاني بعد شوية.',
              onRetry: () {
                setState(() {
                  _orders = _fetch();
                });
              },
            );
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('لسه معملتش طلبات'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final o = rows[i];
              return Material(
                color: cCream2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: cHair),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  title: Text('طلب رقم ${o['order_no']}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${statusLabel[o['status']] ?? ''} • ${fmtTime(o['created_at'] as String)}'),
                  trailing: Text(money(o['total'] as num),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: cBrand)),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrackPage(orderId: o['id'] as String),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
