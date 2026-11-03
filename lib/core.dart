import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Public client credentials (anon key is safe to ship: access is limited by RLS).
const supabaseUrl = 'https://bfwydbseqkujqvnprtar.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmd3lkYnNlcWt1anF2bnBydGFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1MTQwOTUsImV4cCI6MjEwOTA5MDA5NX0.1zNyQ8nqvy7iZWfiFcrBIN_lHG7ysNaXvQbJfb20Hz8';

// Dark roast palette ("سهرة قهوة"): cInk is the light text colour,
// cCream the dark background. Names are kept so every screen follows.
const cInk = Color(0xFFF5E9D8);
const cCream = Color(0xFF1A110C);
const cCream2 = Color(0xFF2A1C14);
const cHair = Color(0xFF3A281C);
const cMuted = Color(0xFFB79F88);
const cBrand = Color(0xFFD9894A);
const cOnBrand = Color(0xFF1A110C);
const cCopper = Color(0xFFEBB27A);
const cGreen = Color(0xFF3E7C57);
const cGold = Color(0xFFE3B04B);
const cDanger = Color(0xFFC8493A);
const cCoffee = Color(0xFF6A3D22);

SupabaseClient get sb => Supabase.instance.client;

Future<void> initNasya() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  net.start();
}

// ---------------------------------------------------------------- connectivity

/// Watches the real connection to the server (not just "wifi is on").
class NetStatus extends ChangeNotifier {
  bool online = true;
  bool justReconnected = false;
  Timer? _poll;
  Timer? _flash;
  bool _checking = false;

  void start() {
    _check();
    _poll ??= Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  /// Called when a request fails because of the network; the next check restores the state.
  void markOffline() => _set(false);

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    var ok = false;
    try {
      final req = await client.getUrl(Uri.parse('$supabaseUrl/auth/v1/health'));
      req.headers.set('apikey', supabaseAnonKey);
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
      ok = res.statusCode < 500;
    } catch (_) {
      ok = false;
    } finally {
      client.close(force: true);
      _checking = false;
    }
    _set(ok);
  }

  void _set(bool ok) {
    if (ok == online) return;
    online = ok;
    if (ok) {
      justReconnected = true;
      _flash?.cancel();
      _flash = Timer(const Duration(seconds: 4), () {
        justReconnected = false;
        notifyListeners();
      });
    } else {
      justReconnected = false;
    }
    notifyListeners();
  }
}

final net = NetStatus();

Widget _netBanner(String text, Color color, IconData icon) {
  return Material(
    color: color,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: cInk, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: cInk, fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ],
        ),
      ),
    ),
  );
}

bool isNetworkError(Object e) {
  if (e is SocketException || e is TimeoutException) return true;
  final s = e.toString().toLowerCase();
  const keys = [
    'socketexception',
    'failed host lookup',
    'clientexception',
    'connection refused',
    'connection closed',
    'connection reset',
    'network is unreachable',
    'no address associated',
    'timeoutexception',
    'handshakeexception',
    'authretryablefetchexception',
    'xmlhttprequest',
    'software caused connection abort',
    'broken pipe',
  ];
  return keys.any((k) => s.contains(k));
}

/// Random UUID v4, used so that retrying an order never creates a duplicate.
String newRequestId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
      '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

ThemeData nasyaTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: cBrand, brightness: Brightness.dark).copyWith(
    brightness: Brightness.dark,
    primary: cBrand,
    onPrimary: cOnBrand,
    secondary: cGreen,
    onSecondary: cInk,
    surface: cCream,
    onSurface: cInk,
    error: cDanger,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cCream,
  );
  return base.copyWith(
    textTheme: GoogleFonts.cairoTextTheme(base.textTheme)
        .apply(bodyColor: cInk, displayColor: cInk),
    appBarTheme: const AppBarTheme(
      backgroundColor: cCream,
      foregroundColor: cInk,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cCream2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

MaterialApp nasyaMaterialApp(Widget home) {
  return MaterialApp(
    title: 'BONNAYA',
    debugShowCheckedModeBanner: false,
    theme: nasyaTheme(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => Column(
      children: [
        ListenableBuilder(
          listenable: net,
          builder: (context, _) {
            if (!net.online) {
              return _netBanner(
                  'انقطع الاتصال بالإنترنت. هتكمّل من مكانك أول ما يرجع.',
                  cDanger,
                  Icons.wifi_off);
            }
            if (net.justReconnected) {
              return _netBanner('رجع الاتصال. كمّل اللي كنت بتعمله.', cGreen,
                  Icons.wifi);
            }
            return const SizedBox.shrink();
          },
        ),
        Expanded(child: child ?? const SizedBox.shrink()),
      ],
    ),
    home: home,
  );
}

// ---------------------------------------------------------------- labels

const sizeKeys = ['small', 'medium', 'large'];
const sizeLabel = {'small': 'صغير', 'medium': 'وسط', 'large': 'كبير'};
const sugarKeys = ['none', 'light', 'normal', 'extra'];
const sugarLabel = {
  'none': 'سادة',
  'light': 'على الريحة',
  'normal': 'مظبوط',
  'extra': 'زيادة',
};
/// Coffee: سادة / على الريحة / مظبوط / زيادة. Other drinks: بسيط / مظبوط / زيادة.
List<String> sugarKeysFor(bool coffee) =>
    coffee ? sugarKeys : const ['light', 'normal', 'extra'];
String sugarLabelFor(bool coffee, String k) => coffee
    ? (sugarLabel[k] ?? '')
    : const {'none': 'بسيط', 'light': 'بسيط', 'normal': 'مظبوط', 'extra': 'زيادة'}[k] ?? '';
String sugarDescFor(bool coffee, String? k) => coffee
    ? (sugarDesc[k] ?? '')
    : const {
          'none': 'سكر بسيط',
          'light': 'سكر بسيط',
          'normal': 'سكر مظبوط',
          'extra': 'سكر زيادة'
        }[k] ??
        '';
const sugarDesc = {
  'none': 'سادة',
  'light': 'سكر على الريحة',
  'normal': 'سكر مظبوط',
  'extra': 'سكر زيادة',
};
const statusLabel = {
  'pending_payment': 'بانتظار تأكيد التحويل',
  'received': 'تم تأكيد الأوردر',
  'preparing': 'جاري التحضير',
  'ready': 'جاهز',
  'on_the_way': 'في الطريق ليك',
  'delivered': 'اتسلّم',
  'cancelled': 'ملغي',
};

String money(num v) {
  final d = v.toDouble();
  return '${d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2)} ج';
}

String fmtTime(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

const _errorRules = <List<String>>[
  ['no open shift', 'افتح وردية الأول.'],
  ['shift not open', 'الوردية دي اتقفلت قبل كده.'],
  ['unknown drink', 'الصنف ده مش متاح دلوقتي.'],
  ['unknown addon', 'إضافة من اللي اخترتها مش متاحة دلوقتي.'],
  ['empty order', 'الطلب فاضي.'],
  ['too many items', 'الطلب كبير. قسّمه على طلبين.'],
  ['staff only', 'الصلاحية دي للموظفين بس.'],
  ['not allowed', 'مفيش عندك صلاحية للخطوة دي.'],
  ['out_of_stock', 'الصنف ده خلص دلوقتي.'],
  ['coupon invalid', 'كود الخصم ده مش شغال.'],
  ['coupon min', 'كود الخصم ده لطلب أكبر من كده.'],
  ['coupon used', 'استخدمت كود الخصم ده قبل كده.'],
  ['below minimum', 'أقل قيمة للطلب لسه ماوصلتش.'],
  ['password short', 'الباسورد لازم يكون 8 حروف أو أكتر.'],
  ['discount too high', 'الخصم أعلى من المسموح. اطلب من المدير.'],
  ['already discounted', 'الفاتورة دي اتخصم عليها قبل كده.'],
  ['reason required', 'اكتب السبب الأول.'],
  ['already cancelled', 'الأوردر ده ملغي بالفعل.'],
  ['cannot cancel', 'مينفعش تلغي الأوردر ده دلوقتي.'],
  ['store_closed', 'مش بنستقبل أوردرات دلوقتي. جرّب في مواعيد الشغل.'],
  ['address required', 'اكتب عنوان التوصيل.'],
  ['payment reference', 'اكتب رقم المحفظة اللي حوّلت منها.'],
  ['not authenticated', 'سجّل دخول الأول.'],
  ['order not found', 'الطلب ده مش موجود.'],
  ['invalid login', 'الإيميل أو كلمة السر غلط.'],
  ['already registered', 'الإيميل ده مسجّل قبل كده. جرّب تدخل.'],
  ['already been registered', 'الإيميل ده مسجّل قبل كده. جرّب تدخل.'],
  ['password should be', 'كلمة السر لازم تكون 6 حروف على الأقل.'],
  ['rate limit', 'جرّبت كتير في وقت قصير. استنى شوية وحاول تاني.'],
  ['email not confirmed', 'الإيميل لسه متأكدش. كلّم بنايه.'],
  ['unable to validate email', 'اكتب إيميل صحيح.'],
  ['invalid email', 'اكتب إيميل صحيح.'],
  ['jwt', 'انتهت جلستك. سجّل دخول تاني.'],
];

/// Turns any error into a short Arabic message a customer can act on.
String errorText(Object e) {
  if (e is String) return e;
  if (isNetworkError(e)) {
    return 'انقطع الاتصال بالإنترنت. اتأكد من النت وجرّب تاني.';
  }
  String m;
  if (e is AuthException) {
    m = e.message;
  } else if (e is PostgrestException) {
    m = e.message;
  } else {
    m = e.toString();
  }
  final l = m.toLowerCase();
  for (final r in _errorRules) {
    if (l.contains(r[0])) return r[1];
  }
  return 'حصلت مشكلة عندنا. جرّب تاني بعد شوية.';
}

void showError(BuildContext context, Object e) {
  if (isNetworkError(e)) net.markOffline();
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(errorText(e))));
}

// ---------------------------------------------------------------- models

class Addon {
  final String id;
  final String name;
  final double price;
  Addon(this.id, this.name, this.price);
  factory Addon.from(Map<String, dynamic> m) =>
      Addon(m['id'] as String, m['name'] as String, (m['price'] as num).toDouble());
}

class Drink {
  final String id;
  final String name;
  final Map<String, double> prices;
  final String category;
  final bool soldOut;
  final int? stock;
  final bool isCoffee;
  Drink(this.id, this.name, this.prices,
      [this.category = 'hot', this.soldOut = false, this.stock, this.isCoffee = false]);
  /// False when the owner marked it sold out or its stock count reached zero.
  bool get available => !soldOut && (stock == null || stock! > 0);
  /// Drinks come in sizes with sugar choices; snacks and sandwiches are a single item.
  bool get hasOptions => prices.length > 1;
  factory Drink.from(Map<String, dynamic> m) {
    final prices = <String, double>{};
    for (final p in (m['drink_prices'] as List)) {
      final row = p as Map<String, dynamic>;
      prices[row['size'] as String] = (row['price'] as num).toDouble();
    }
    return Drink(m['id'] as String, m['name'] as String, prices,
        (m['category'] as String?) ?? 'hot',
        m['sold_out'] == true,
        (m['stock_qty'] as num?)?.toInt(),
        m['is_coffee'] == true);
  }
  double get minPrice =>
      prices.isEmpty ? 0 : prices.values.reduce((a, b) => a < b ? a : b);
}

class Menu {
  final List<Drink> drinks;
  final List<Addon> addons;
  Menu(this.drinks, this.addons);
}

class MenuCategory {
  final String id;
  final String name;
  final String icon;
  const MenuCategory(this.id, this.name, this.icon);
  IconData get iconData => categoryIcons[icon] ?? Icons.restaurant_outlined;
}

/// Icons the owner can pick for a category.
const categoryIcons = <String, IconData>{
  'coffee': Icons.coffee_outlined,
  'drink': Icons.local_drink_outlined,
  'icecream': Icons.icecream_outlined,
  'cookie': Icons.cookie_outlined,
  'bakery': Icons.bakery_dining_outlined,
  'lunch': Icons.lunch_dining_outlined,
  'cake': Icons.cake_outlined,
  'pizza': Icons.local_pizza_outlined,
  'fastfood': Icons.fastfood_outlined,
  'tea': Icons.emoji_food_beverage_outlined,
  'restaurant': Icons.restaurant_outlined,
  'star': Icons.star_outline,
};

const _defaultCategories = [
  MenuCategory('hot', 'مشروبات ساخنة', 'coffee'),
  MenuCategory('cold', 'مشروبات باردة', 'drink'),
  MenuCategory('chocolate', 'كورنر الشوكولاتة', 'icecream'),
  MenuCategory('snacks', 'سناكس', 'cookie'),
  MenuCategory('crackers', 'مقرمشات', 'bakery'),
  MenuCategory('sandwiches', 'سندوتشات', 'lunch'),
];

/// The current categories (updated whenever the menu or the owner's list loads).
List<MenuCategory> menuCategories = _defaultCategories;

Future<List<MenuCategory>> fetchCategories() async {
  try {
    final r = await sb
        .from('menu_categories')
        .select('id, name, icon')
        .eq('active', true)
        .order('sort_order')
        .order('name');
    final l = (r as List)
        .map((e) => MenuCategory(
            e['id'] as String, e['name'] as String, (e['icon'] as String?) ?? 'restaurant'))
        .toList();
    if (l.isNotEmpty) menuCategories = l;
  } catch (e) {
    if (isNetworkError(e)) rethrow;
  }
  return menuCategories;
}

Future<Menu> loadMenu() async {
  await fetchCategories();
  final d = await sb
      .from('drinks')
      .select('id, name, category, sold_out, stock_qty, is_coffee, drink_prices(size, price)')
      .eq('active', true)
      .order('sort_order');
  final a = await sb
      .from('addons')
      .select('id, name, kind, price')
      .eq('active', true)
      .order('price');
  return Menu(
    d.map((e) => Drink.from(e)).toList(),
    a.map((e) => Addon.from(e)).toList(),
  );
}

class CartLine {
  final Drink drink;
  final String size;
  final String sugar;
  final int qty;
  final List<Addon> addons;
  CartLine({
    required this.drink,
    required this.size,
    required this.sugar,
    required this.qty,
    required this.addons,
  });

  String get title => drink.hasOptions
      ? '${drink.name} ${sizeLabel[size] ?? ''} × $qty'
      : '${drink.name} × $qty';
  String get notes => [
        if (drink.hasOptions) sugarDescFor(drink.isCoffee, sugar),
        for (final a in addons) '+ ${a.name}',
      ].join(' · ');

  double get unit => drink.prices[size] ?? 0;
  double get total =>
      (unit + addons.fold<double>(0, (s, a) => s + a.price)) * qty;

  Map<String, dynamic> toJson() => {
        'drink_id': drink.id,
        'size': size,
        'sugar': sugar,
        'qty': qty,
        'addon_ids': addons.map((a) => a.id).toList(),
      };
}

class Cart extends ChangeNotifier {
  final List<CartLine> lines = [];
  double get total => lines.fold<double>(0, (s, l) => s + l.total);
  void add(CartLine l) {
    lines.add(l);
    notifyListeners();
  }

  void removeAt(int i) {
    lines.removeAt(i);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }
}

final cart = Cart();

// Text helpers for orders fetched with embedded order_items.
String itemTitle(Map<String, dynamic> it) {
  final drink = it['drinks'] as Map<String, dynamic>;
  final multi = ((drink['drink_prices'] as List?)?.length ?? 2) > 1;
  return multi
      ? '${drink['name']} ${sizeLabel[it['size']] ?? ''} × ${it['qty']}'
      : '${drink['name']} × ${it['qty']}';
}

String itemNotes(Map<String, dynamic> it) {
  final multi =
      (((it['drinks'] as Map<String, dynamic>)['drink_prices'] as List?)?.length ??
              2) >
          1;
  final coffee = (it['drinks'] as Map<String, dynamic>)['is_coffee'] == true;
  final parts = <String>[if (multi) sugarDescFor(coffee, it['sugar'] as String?)];
  for (final a in (it['order_item_addons'] as List)) {
    final row = a as Map<String, dynamic>;
    final addon = row['addons'] as Map<String, dynamic>;
    parts.add('+ ${addon['name']}');
  }
  return parts.join(' · ');
}

double itemTotal(Map<String, dynamic> it) {
  var s = (it['unit_price'] as num).toDouble();
  for (final a in (it['order_item_addons'] as List)) {
    s += ((a as Map<String, dynamic>)['price'] as num).toDouble();
  }
  return s * (it['qty'] as num).toInt();
}

// ---------------------------------------------------------------- shared widgets

class Choices<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  const Choices({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            showCheckmark: false,
            selectedColor: cInk,
            backgroundColor: cCream2,
            side: const BorderSide(color: cHair),
            labelStyle: TextStyle(
              color: v == selected ? cCream : cInk,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => onChanged(v),
          ),
      ],
    );
  }
}

/// Friendly full-screen state for "couldn't load": tells the reason and how it resolves.
class ProblemView extends StatelessWidget {
  final bool offline;
  final String title;
  final String hint;
  final VoidCallback onRetry;
  const ProblemView({
    super.key,
    required this.offline,
    required this.title,
    required this.hint,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(offline ? Icons.wifi_off : Icons.error_outline,
                size: 52, color: cMuted),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: cMuted)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('حاول تاني دلوقتي')),
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}

class AuthGate extends StatelessWidget {
  final Widget Function() signedIn;
  final Widget signedOut;
  const AuthGate({super.key, required this.signedIn, required this.signedOut});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (context, snapshot) {
        return sb.auth.currentSession == null ? signedOut : signedIn();
      },
    );
  }
}

/// Guests can browse the menu; this asks them to sign in only when needed.
Future<bool> ensureSignedIn(BuildContext context) async {
  if (sb.auth.currentSession != null) return true;
  final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _LoginRoute()));
  return ok == true && sb.auth.currentSession != null;
}

class _LoginRoute extends StatefulWidget {
  const _LoginRoute();
  @override
  State<_LoginRoute> createState() => _LoginRouteState();
}

class _LoginRouteState extends State<_LoginRoute> {
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = sb.auth.onAuthStateChange.listen((s) {
      if (s.session != null && mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const AuthPage(title: 'سجّل دخولك عشان تكمّل الطلب'),
        SafeArea(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: IconButton(
              tooltip: 'رجوع',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ),
        ),
      ],
    );
  }
}

class AuthPage extends StatefulWidget {
  final String title;
  final bool allowSignUp;
  const AuthPage({super.key, required this.title, this.allowSignUp = true});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _signUp = false;
  String _gender = 'm';
  bool _busy = false;
  bool _retryWhenOnline = false;

  @override
  void initState() {
    super.initState();
    net.addListener(_onNet);
  }

  @override
  void dispose() {
    net.removeListener(_onNet);
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  // If the connection dropped while signing in, finish the sign-in when it returns.
  void _onNet() {
    if (net.online && _retryWhenOnline && !_busy && mounted) {
      _retryWhenOnline = false;
      _submit();
    }
  }

  Future<void> _submit() async {
    final raw = _email.text.trim();
    // Staff and the owner sign in with a username; customers use their email.
    final email = raw.contains('@') || _signUp ? raw : '${raw.toLowerCase()}@bonnaya.app';
    if (email.isEmpty || _pass.text.length < 6) {
      showError(context, 'اكتب الإيميل وكلمة سر 6 حروف على الأقل.');
      return;
    }
    if (_signUp && !raw.contains('@')) {
      showError(context, 'اكتب إيميل صحيح.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_signUp) {
        try {
          await sb.auth.signUp(
            email: email,
            password: _pass.text,
            data: {
              'full_name': _name.text.trim(),
              'gender': _gender,
              // A random coffee avatar for their gender; they can change it later.
              'avatar':
                  '${_gender}${1 + Random().nextInt(4)}',
            },
          );
        } on AuthException catch (e) {
          // A retry after a dropped connection may find the account already created.
          if (!e.message.toLowerCase().contains('already')) rethrow;
        }
        if (sb.auth.currentSession == null) {
          await sb.auth.signInWithPassword(email: email, password: _pass.text);
        }
      } else {
        await sb.auth.signInWithPassword(email: email, password: _pass.text);
      }
    } catch (e) {
      if (isNetworkError(e)) _retryWhenOnline = true;
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Center(
                child: Text('BONNAYA',
                    style: TextStyle(
                        fontSize: 44, fontWeight: FontWeight.w800, color: cInk)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(widget.title,
                    style: const TextStyle(color: cMuted, fontSize: 15)),
              ),
              const SizedBox(height: 24),
              if (_signUp) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'm', label: Text('ذكر'), icon: Icon(Icons.man)),
                    ButtonSegment(
                        value: 'f', label: Text('أنثى'), icon: Icon(Icons.woman)),
                  ],
                  selected: {_gender},
                  onSelectionChanged: (v) => setState(() => _gender = v.first),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    labelText: widget.allowSignUp ? 'الإيميل' : 'اسم المستخدم'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة السر'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy ? null : _submit,
                child: Text(_signUp ? 'إنشاء حساب' : 'دخول'),
              ),
              if (widget.allowSignUp)
                TextButton(
                  onPressed: () => setState(() => _signUp = !_signUp),
                  child: Text(_signUp ? 'عندي حساب' : 'مستخدم جديد؟ سجّل'),
                ),
            ],
          ),
        ),
      );
    final wide = MediaQuery.of(context).size.width >= 860 && !widget.allowSignUp;
    return Scaffold(
      body: wide
          ? Row(children: [
              Expanded(child: form),
              Expanded(
                child: Container(
                  color: cCream2,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_cafe, size: 96, color: cBrand),
                      SizedBox(height: 14),
                      Text('BONNAYA',
                          style: TextStyle(
                              fontSize: 54,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 6,
                              color: cBrand)),
                      SizedBox(height: 10),
                      Text('قهوتك في الطريق.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cMuted, fontSize: 17)),
                    ],
                  ),
                ),
              ),
            ])
          : form,
    );
  }
}
