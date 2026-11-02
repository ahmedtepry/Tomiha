import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import 'core.dart';
import 'welcome.dart';
import 'update.dart';
import 'avatars.dart';
import 'delivery.dart';

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return nasyaMaterialApp(
      const SplashGate(next: UpdateWatcher(child: HomePage())),
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
  final _search = TextEditingController();
  String _q = '';

  Future<Menu> _fetch() async {
    try {
      final m = await loadMenu();
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

class MenuCategory {
  final String id;
  final String name;
  final IconData icon;
  const MenuCategory(this.id, this.name, this.icon);
}

const menuCategories = [
  MenuCategory('snacks', 'سناكس', Icons.cookie_outlined),
  MenuCategory('crackers', 'مقرمشات', Icons.bakery_dining_outlined),
  MenuCategory('hot', 'مشروبات ساخنة', Icons.coffee_outlined),
  MenuCategory('cold', 'مشروبات باردة', Icons.local_drink_outlined),
  MenuCategory('sandwiches', 'سندوتشات', Icons.lunch_dining_outlined),
  MenuCategory('chocolate', 'كورنر الشوكولاتة', Icons.icecream_outlined),
];

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
                child: Icon(cat.icon, size: 26),
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
                  Icon(cat.icon, color: cBrand, size: 30),
                  const SizedBox(height: 6),
                  Text(drink.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(money(drink.minPrice),
                      style: const TextStyle(
                          color: cBrand, fontWeight: FontWeight.w800)),
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
          subtitle: Text(drink.hasOptions ? 'من ${money(drink.minPrice)}' : money(drink.minPrice),
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
                values: sugarKeys,
                selected: sugar,
                label: (s) => sugarLabel[s]!,
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
  Address? _addr;
  Address? _saved;
  ({String number, String name}) _wallet = (number: '', name: '');
  final _payRef = TextEditingController();
  bool busy = false;
  // True after the customer pressed send but the connection was down: we send by ourselves
  // as soon as it returns. The same request id guarantees one order even if we retry.
  bool waiting = false;
  final String requestId = newRequestId();

  @override
  void initState() {
    super.initState();
    net.addListener(_onNet);
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
      final res = await sb.rpc('place_order_v3', params: {
        'p_request_id': requestId,
        'p_items': cart.lines.map((l) => l.toJson()).toList(),
        'p_address': _addr!.toJson(),
        'p_pay_ref': _payRef.text.trim(),
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
                          ? 'حوّل ${money(cart.total)} على المحفظة، وبعدين اكتب رقم المحفظة اللي حوّلت منها. هنبعتلك رقم المحفظة أول ما تبعت الطلب.'
                          : 'حوّل ${money(cart.total)} على المحفظة رقم:',
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
                        : 'اتحوّل؟ ابعت الطلب  •  ${money(cart.total)}',
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
              '*, order_items(*, drinks(name, drink_prices(size)), order_item_addons(*, addons(name)))')
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
