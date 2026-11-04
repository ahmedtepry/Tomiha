import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import 'core.dart';
import 'notify.dart';
import 'welcome.dart';
import 'update.dart';
import 'avatars.dart';
import 'delivery.dart';
import 'ops.dart';

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return nasyaMaterialApp(
      const SplashGate(next: UpdateWatcher(child: OrderNotifier(child: HomePage()))),
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
  List<String> _top = [];
  StoreStatus? _store;
  final _search = TextEditingController();
  String _q = '';

  Future<Menu> _fetch() async {
    try {
      final m = await loadMenu();
      _store = await loadStoreStatus();
      try {
        final r = await sb.rpc('top_drinks', params: {'p_limit': 8});
        _top = [for (final x in (r as List)) (x as Map)['drink_id'] as String];
      } catch (_) {
        _top = [];
      }
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

  /// Best sellers first; if there are not enough orders yet, fill with the menu.
  List<Drink> _popular(Menu menu) {
    final byId = {for (final d in menu.drinks) d.id: d};
    final out = <Drink>[for (final id in _top) if (byId[id] != null) byId[id]!];
    for (final d in menu.drinks) {
      if (out.length >= 8) break;
      if (!out.contains(d)) out.add(d);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    net.addListener(_onNet);
  }

  @override
  void dispose() {
    net.removeListener(_onNet);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BONNAYA',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
        actions: const [AccountButton(), SizedBox(width: 6)],
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
              if (_store != null && !_store!.open) ClosedBanner(status: _store!),
              TextField(
                controller: _search,
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  hintText: 'دوّر على صنف...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _search.clear();
                            _q = '';
                          }),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              if (_q.isNotEmpty) ...[
                for (final d in menu.drinks.where((d) => d.name.contains(_q)))
                  DrinkTile(drink: d, addons: menu.addons),
                if (!menu.drinks.any((d) => d.name.contains(_q)))
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('مفيش صنف بالاسم ده.',
                            style: TextStyle(color: cMuted))),
                  ),
              ] else ...[
                const Text('الأكثر طلباً',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 124,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final d in _popular(menu))
                        _PopularCard(
                          drink: d,
                          onTap: () => openDrinkSheet(context, d, menu.addons),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('الأقسام',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.92,
                  children: [
                    for (final c in menuCategories)
                      _CategoryCard(
                        cat: c,
                        count: menu.drinks.where((d) => d.category == c.id).length,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CategoryPage(cat: c, menu: menu)),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              const Center(child: VersionButton()),
            ],
          );
        },
      ),
      bottomNavigationBar: const BonnayaBar(atHome: true),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final MenuCategory cat;
  final int count;
  final VoidCallback onTap;
  const _CategoryCard(
      {required this.cat, required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: cCream2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: cHair),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: cCream,
                foregroundColor: cBrand,
                child: Icon(cat.iconData, size: 26),
              ),
              const SizedBox(height: 10),
              Text(cat.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('$count صنف', style: const TextStyle(color: cMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class CategoryPage extends StatelessWidget {
  final MenuCategory cat;
  final Menu menu;
  const CategoryPage({super.key, required this.cat, required this.menu});
  @override
  Widget build(BuildContext context) {
    final items = menu.drinks.where((d) => d.category == cat.id).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(cat.name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: items.isEmpty
          ? const Center(
              child: Text('القسم ده لسه فاضي، قريب هنضيف فيه.',
                  style: TextStyle(color: cMuted)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                for (final d in items) DrinkTile(drink: d, addons: menu.addons),
              ],
            ),
      bottomNavigationBar: const BonnayaBar(atHome: false),
    );
  }
}

/// Bottom bar: cart on one side, home shortcut in the middle (with a back
/// arrow once the customer has gone into a section), orders/login on the other.
class BonnayaBar extends StatelessWidget {
  final bool atHome;
  const BonnayaBar({super.key, required this.atHome});

  void _home(BuildContext context) =>
      Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 68,
        decoration: const BoxDecoration(
          color: cCream2,
          border: Border(top: BorderSide(color: cHair)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: cart,
                builder: (context, _) {
                  final n = cart.lines.fold<int>(0, (s, l) => s + l.qty);
                  return InkWell(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CartPage())),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Badge(
                          isLabelVisible: n > 0,
                          label: Text('$n'),
                          child: const Icon(Icons.shopping_cart_outlined, size: 28),
                        ),
                        const SizedBox(height: 2),
                        Text(n > 0 ? 'السلة • ${money(cart.total)}' : 'السلة',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!atHome)
                    IconButton.outlined(
                      tooltip: 'رجوع',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: 'الرئيسية',
                    iconSize: 30,
                    icon: const Icon(Icons.home_rounded),
                    onPressed: atHome ? null : () => _home(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<AuthState>(
                stream: sb.auth.onAuthStateChange,
                builder: (context, _) {
                  final signed = sb.auth.currentSession != null;
                  return InkWell(
                    onTap: () => signed
                        ? Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const OrdersPage()))
                        : ensureSignedIn(context),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(signed ? Icons.receipt_long : Icons.login, size: 28),
                        const SizedBox(height: 2),
                        Text(signed ? 'طلباتي' : 'دخول',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void openDrinkSheet(BuildContext context, Drink drink, List<Addon> addons) {
  if (!drink.available) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('الصنف ده خلص دلوقتي.')));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: cCream,
    builder: (_) => DrinkSheet(drink: drink, addons: addons),
  );
}

class _PopularCard extends StatelessWidget {
  final Drink drink;
  final VoidCallback onTap;
  const _PopularCard({required this.drink, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cat = menuCategories.firstWhere((c) => c.id == drink.category,
        orElse: () => menuCategories.first);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: Material(
        color: cCream2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: cHair),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            width: 112,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(cat.iconData, color: cBrand, size: 30),
                  const SizedBox(height: 6),
                  Text(drink.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(drink.available ? money(drink.minPrice) : 'خلص',
                      style: TextStyle(
                          color: drink.available ? cBrand : cMuted,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DrinkTile extends StatelessWidget {
  final Drink drink;
  final List<Addon> addons;
  const DrinkTile({super.key, required this.drink, required this.addons});

  void _open(BuildContext context) {
    if (!drink.available) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('الصنف ده خلص دلوقتي.')));
      return;
    }
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
          subtitle: Text(!drink.available ? 'خلص دلوقتي' : (drink.hasOptions ? 'من ${money(drink.minPrice)}' : money(drink.minPrice)),
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
            if (!widget.drink.hasOptions)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(money(widget.drink.minPrice),
                    style: const TextStyle(
                        color: cBrand, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            if (widget.drink.hasOptions) ...[
              const SectionLabel('الحجم'),
              Choices<String>(
                values: sizes,
                selected: size,
                label: (s) => '${sizeLabel[s]}  ${money(widget.drink.prices[s]!)}',
                onChanged: (v) => setState(() => size = v),
              ),
              const SectionLabel('السكر'),
              Choices<String>(
                values: sugarKeysFor(widget.drink.isCoffee),
                selected: sugar,
                label: (s) => sugarLabelFor(widget.drink.isCoffee, s),
                onChanged: (v) => setState(() => sugar = v),
              ),
              if (widget.addons.isNotEmpty) const SectionLabel('إضافات'),
            ],
            if (widget.drink.hasOptions) Wrap(
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
  StoreStatus? _store;
  Address? _addr;
  Address? _saved;
  ({String number, String name}) _wallet = (number: '', name: '');
  final _payRef = TextEditingController();
  bool busy = false;
  // True after the customer pressed send but the connection was down: we send by ourselves
  // as soon as it returns. The same request id guarantees one order even if we retry.
  bool waiting = false;
  final String requestId = newRequestId();
  Map<String, dynamic>? _q;
  final _coupon = TextEditingController();
  String _appliedCoupon = '';
  String? _couponErr;
  bool _usePoints = false;
  double get _total => (_q?['total'] as num?)?.toDouble() ?? cart.total;

  Future<void> _refreshQuote() async {
    if (cart.lines.isEmpty) return;
    try {
      final r = await sb.rpc('order_quote', params: {
        'p_items': cart.lines.map((l) => l.toJson()).toList(),
        'p_coupon': _appliedCoupon.isEmpty ? null : _appliedCoupon,
        'p_points': _usePoints ? 100000 : 0,
      });
      if (!mounted) return;
      final q = Map<String, dynamic>.from(r as Map);
      setState(() {
        _q = q;
        final ce = q['coupon_error'] as String?;
        _couponErr = ce == null ? null : errorText(Exception(ce));
        if (ce != null) _appliedCoupon = '';
        if (ce == null && _appliedCoupon.isNotEmpty) _couponOpen = false;
      });
    } catch (_) {}
  }

  void _applyCoupon() {
    _appliedCoupon = _coupon.text.trim();
    _refreshQuote();
  }

  @override
  void initState() {
    super.initState();
    cart.addListener(_refreshQuote);
    _refreshQuote();
    net.addListener(_onNet);
    loadStoreStatus().then((s) {
      if (mounted) setState(() => _store = s);
    });
    loadWallet().then((w) {
      if (mounted) setState(() => _wallet = w);
    });
    loadSavedAddress().then((a) {
      if (mounted && a != null) {
        setState(() {
          _saved = a;
          _addr ??= a;
        });
      }
    });
  }

  @override
  void dispose() {
    cart.removeListener(_refreshQuote);
    _coupon.dispose();
    net.removeListener(_onNet);
    _payRef.dispose();
    super.dispose();
  }

  void _onNet() {
    if (net.online && waiting && !busy && mounted) _place();
  }

  Future<void> _chooseAddress() async {
    final a = await showModalBottomSheet<Address>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cCream,
      builder: (_) => AddressSheet(initial: _addr),
    );
    if (a == null || !mounted) return;
    setState(() => _addr = a);
    final same = _saved != null &&
        _saved!.text == a.text &&
        _saved!.mapsLink == a.mapsLink;
    if (same) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ العنوان'),
        content: const Text('تحفظ العنوان ده كعنوان افتراضي؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لأ')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('أوك')),
        ],
      ),
    );
    if (save == true) {
      try {
        await saveDefaultAddress(a);
        if (mounted) setState(() => _saved = a);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  Future<void> _place() async {
    if (busy) return;
    if (sb.auth.currentSession == null) {
      final ok = await ensureSignedIn(context);
      if (!ok || !mounted) return;
    }
    if (_store != null && !_store!.open) {
      showError(context, _store!.message);
      return;
    }
    if (_addr == null) {
      showError(context, 'حدّد عنوان التوصيل الأول.');
      return;
    }
    if (_payRef.text.trim().isEmpty) {
      showError(context, 'اكتب رقم المحفظة اللي حوّلت منها، عشان نتأكد من التحويل.');
      return;
    }
    if (!net.online) {
      setState(() => waiting = true);
      return;
    }
    setState(() {
      busy = true;
      waiting = false;
    });
    try {
      final res = await sb.rpc('place_order_v4', params: {
        'p_request_id': requestId,
        'p_items': cart.lines.map((l) => l.toJson()).toList(),
        'p_address': _addr!.toJson(),
        'p_pay_ref': _payRef.text.trim(),
        'p_coupon': _appliedCoupon.isEmpty ? null : _appliedCoupon,
        'p_points': _usePoints ? 100000 : 0,
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
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'رجوع للرئيسية',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
        title: const Text('طلبك'),
      ),
      bottomNavigationBar: _bottomBar(),
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          if (cart.lines.isEmpty) {
            return const Center(child: Text('الطلب فاضي'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_store != null && !_store!.open) ClosedBanner(status: _store!),
              for (var i = 0; i < cart.lines.length; i++) _line(i),
              _extras(),
              const SectionLabel('عنوان التوصيل'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cCream2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _addr == null ? cGold : cHair, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_addr != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on, color: cBrand),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_addr!.text,
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w600))),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    OutlinedButton.icon(
                      onPressed: _chooseAddress,
                      icon: Icon(_addr == null ? Icons.add_location_alt : Icons.edit_location_alt),
                      label: Text(_addr == null ? 'حدّد عنوان التوصيل' : 'غيّر العنوان'),
                    ),
                  ],
                ),
              ),
              const SectionLabel('الدفع'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cCream2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cHair),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.account_balance_wallet_outlined, color: cBrand),
                      SizedBox(width: 8),
                      Text('محفظة إلكترونية',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      _wallet.number.isEmpty
                          ? 'حوّل ${money(_total)} على المحفظة، وبعدين اكتب رقم المحفظة اللي حوّلت منها. هنبعتلك رقم المحفظة أول ما تبعت الطلب.'
                          : 'حوّل ${money(_total)} على المحفظة رقم:',
                      style: const TextStyle(color: cMuted, height: 1.6),
                    ),
                    if (_wallet.number.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SelectableText(_wallet.number,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: cBrand)),
                      if (_wallet.name.isNotEmpty)
                        Text(_wallet.name,
                            style: const TextStyle(color: cMuted)),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('انسخ الرقم'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _wallet.number));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('اتنسخ الرقم.')));
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _payRef,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'رقم المحفظة اللي حوّلت منها'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'الطلب بيتأكد أول ما الكاشير يتأكد من التحويل، وبعدها بنجهزه ونبعتهولك.',
                      style: TextStyle(color: cMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  bool get _belowMin {
    final q = _q;
    if (q == null) return false;
    return (q['subtotal'] as num) < (q['min_order'] as num);
  }

  Widget _row(String a, String b, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(a,
                  style: TextStyle(
                      color: color,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text(b,
              style: TextStyle(
                  color: color,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  bool _couponOpen = false;

  Widget _extras() {
    final q = _q;
    final bal = (q?['balance'] as num?)?.toInt() ?? 0;
    final minRedeem = (q?['min_redeem'] as num?)?.toInt() ?? 0;
    final loyalty = q?['loyalty'] == true;
    final pv = (q?['point_value'] as num?)?.toDouble() ?? 0.5;
    final canUse = bal >= minRedeem && bal > 0;
    BoxDecoration deco() => BoxDecoration(
          color: cCream2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cHair),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: deco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _couponOpen = !_couponOpen),
            child: Row(children: [
              const Icon(Icons.local_offer_outlined, color: cBrand),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    _appliedCoupon.isNotEmpty ? 'كوبون $_appliedCoupon مفعّل ✓' : 'عندك كود خصم؟',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: cBrand)),
              ),
              Icon(_couponOpen ? Icons.expand_less : Icons.expand_more, color: cMuted),
            ]),
          ),
          if (_couponOpen) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _coupon,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'اكتب الكود'),
                  onSubmitted: (_) => _applyCoupon(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _applyCoupon, child: const Text('تطبيق')),
            ]),
          ],
          if (_couponErr != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_couponErr!, style: const TextStyle(color: cDanger)),
            ),
        ]),
      ),
      if (loyalty && sb.auth.currentSession != null && bal > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: deco(),
          child: Row(children: [
            const Icon(Icons.auto_awesome, color: cGold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  canUse
                      ? 'عندك $bal نقطة = ${money(bal * pv)}'
                      : 'عندك $bal نقطة • الاستبدال من $minRedeem',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Switch(
              value: _usePoints && canUse,
              onChanged: canUse
                  ? (v) {
                      _usePoints = v;
                      _refreshQuote();
                    }
                  : null,
            ),
          ]),
        ),
    ]);
  }

  Widget _bottomBar() {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        if (cart.lines.isEmpty) return const SizedBox.shrink();
        final q = _q;
        final cd = (q?['coupon_discount'] as num?)?.toDouble() ?? 0;
        final pd = (q?['points_discount'] as num?)?.toDouble() ?? 0;
        final fee = (q?['fee'] as num?)?.toDouble() ?? 0;
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: cCream2,
              border: Border(top: BorderSide(color: cHair)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (waiting)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cGold, width: 2),
                  ),
                  child: const Row(children: [
                    Icon(Icons.wifi_off, color: cMuted),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'مفيش إنترنت دلوقتي. طلبك محفوظ وهيتبعت لوحده أول ما النت يرجع، متقفلش الصفحة.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              _row('حساب الطلب', money((q?['subtotal'] as num?)?.toDouble() ?? cart.total)),
              _row('التوصيل', fee == 0 ? 'مجاني' : money(fee), color: fee == 0 ? cGreen : null),
              if (cd > 0) _row('خصم الكوبون', '-${money(cd)}', color: cGreen),
              if (pd > 0) _row('خصم النقاط', '-${money(pd)}', color: cGreen),
              _row('الإجمالي', money(_total), bold: true),
              if (_belowMin)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      'أقل قيمة للطلب ${money((q!['min_order'] as num).toDouble())}. زوّد حاجة عشان تكمّل.',
                      style: const TextStyle(color: cDanger, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: busy || (_store != null && !_store!.open) || _belowMin ? null : _place,
                child: Text(waiting ? 'استنى النت وابعت' : 'اتحوّل؟ ابعت الطلب',
                    style: const TextStyle(fontSize: 17)),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _line(int i) {
    final l = cart.lines[i];
    final notes = l.notes;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cCream2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cHair),
      ),
      child: ListTile(
        title: Text(l.title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(notes.isEmpty ? money(l.total) : '$notes\n${money(l.total)}'),
        isThreeLine: notes.isNotEmpty,
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
              '*, order_items(*, drinks(name, is_coffee, drink_prices(size)), order_item_addons(*, addons(name)))')
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
    final idx = const ['pending_payment', 'received', 'preparing', 'ready', 'on_the_way', 'delivered']
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
            color: cBrand,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('طلب رقم ${o['order_no']}',
                  style: const TextStyle(color: cOnBrand)),
              const SizedBox(height: 4),
              Text(statusLabel[status] ?? status,
                  style: const TextStyle(
                      color: cOnBrand, fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                status == 'pending_payment'
                    ? 'بنتأكد من التحويل، وأول ما نتأكد هنأكد طلبك ونجهزه.'
                    : status == 'on_the_way'
                    ? 'الطلب في الطريق ليك.'
                    : status == 'ready'
                    ? 'قهوتك جاهزة وهتتبعتلك دلوقتي.'
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
        if (status == 'delivered') RatingBox(orderId: widget.orderId),
        if (status == 'pending_payment')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('إلغاء الأوردر'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('تلغي الأوردر؟'),
                    content: const Text(
                        'لو حوّلت الفلوس قبل كده، كلّم بنايه عشان نرجّعهالك.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('لأ')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('إلغاء الأوردر')),
                    ],
                  ),
                );
                if (ok != true) return;
                try {
                  await sb.rpc('customer_cancel_order',
                      params: {'p_order': o['id']});
                  _load();
                } catch (e) {
                  if (mounted) showError(context, e);
                }
              },
            ),
          ),
        if (status != 'cancelled') ...[
          const SizedBox(height: 20),
          _step('بانتظار تأكيد التحويل', 0, idx),
          _step('تم تأكيد الأوردر', 1, idx),
          _step('جاري التحضير', 2, idx),
          _step('جاهز', 3, idx),
          _step('في الطريق ليك', 4, idx),
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
              if (((o['delivery_fee'] as num?) ?? 0) > 0)
                Text('توصيل: ${money(o['delivery_fee'] as num)}',
                    style: const TextStyle(color: cMuted)),
              if (((o['coupon_discount'] as num?) ?? 0) > 0)
                Text('خصم الكوبون: -${money(o['coupon_discount'] as num)}',
                    style: const TextStyle(color: cGreen)),
              if (((o['points_discount'] as num?) ?? 0) > 0)
                Text('خصم النقاط: -${money(o['points_discount'] as num)}',
                    style: const TextStyle(color: cGreen)),
              if (((o['points_earned'] as num?) ?? 0) > 0)
                Text('كسبت ${o['points_earned']} نقطة من الطلب ده ✨',
                    style: const TextStyle(color: cGreen)),
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
                ? const Icon(Icons.check, size: 18, color: cInk)
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


/// Stars + comment after delivery. Saved once per order.
class RatingBox extends StatefulWidget {
  final String orderId;
  const RatingBox({super.key, required this.orderId});
  @override
  State<RatingBox> createState() => _RatingBoxState();
}

class _RatingBoxState extends State<RatingBox> {
  int _stars = 0;
  bool _sent = false;
  bool _busy = false;
  bool _checked = false;
  final _comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    sb.from('order_ratings').select('stars').eq('order_id', widget.orderId).maybeSingle().then((r) {
      if (mounted) {
        setState(() {
          _checked = true;
          if (r != null) {
            _sent = true;
            _stars = (r['stars'] as num).toInt();
          }
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _checked = true);
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_stars == 0 || _busy) return;
    setState(() => _busy = true);
    try {
      await sb.rpc('rate_order', params: {
        'p_order': widget.orderId,
        'p_stars': _stars,
        'p_comment': _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      });
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cCream2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cHair),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_sent ? 'شكراً على تقييمك!' : 'قيّم طلبك',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              onPressed: _sent ? null : () => setState(() => _stars = i),
              icon: Icon(i <= _stars ? Icons.star : Icons.star_border, color: cGold, size: 34),
            ),
        ]),
        if (!_sent) ...[
          TextField(
              controller: _comment,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'عايز تقولنا حاجة؟ (اختياري)')),
          FilledButton(
              onPressed: _stars == 0 || _busy ? null : _send, child: const Text('ابعت التقييم')),
        ],
      ]),
    );
  }
}
