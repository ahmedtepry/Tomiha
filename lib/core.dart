import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Public client credentials (anon key is safe to ship: access is limited by RLS).
const supabaseUrl = 'https://bfwydbseqkujqvnprtar.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmd3lkYnNlcWt1anF2bnBydGFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1MTQwOTUsImV4cCI6MjEwOTA5MDA5NX0.1zNyQ8nqvy7iZWfiFcrBIN_lHG7ysNaXvQbJfb20Hz8';

const cInk = Color(0xFF2A1A12);
const cCream = Color(0xFFF6EBDD);
const cCream2 = Color(0xFFEADBC6);
const cHair = Color(0xFFD9C6AB);
const cMuted = Color(0xFF6B5444);
const cBrand = Color(0xFFA24E1B);
const cCopper = Color(0xFFC8662B);
const cGreen = Color(0xFF3F5D4A);
const cGold = Color(0xFFE3B04B);
const cDanger = Color(0xFFB3342A);

SupabaseClient get sb => Supabase.instance.client;

Future<void> initNasya() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
}

ThemeData nasyaTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: cBrand).copyWith(
    primary: cBrand,
    onPrimary: cCream,
    secondary: cGreen,
    onSecondary: cCream,
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
    title: 'الناصية',
    debugShowCheckedModeBanner: false,
    theme: nasyaTheme(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
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
const sugarDesc = {
  'none': 'سادة',
  'light': 'سكر على الريحة',
  'normal': 'سكر مظبوط',
  'extra': 'سكر زيادة',
};
const statusLabel = {
  'received': 'تم الاستلام',
  'preparing': 'جاري التحضير',
  'ready': 'جاهز',
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

String errorText(Object e) {
  String m;
  if (e is AuthException) {
    m = e.message;
  } else if (e is PostgrestException) {
    m = e.message;
  } else {
    m = e.toString();
  }
  if (m.contains('no open shift')) return 'افتح وردية الأول.';
  if (m.contains('unknown drink') || m.contains('unknown addon')) {
    return 'الصنف ده مش متاح دلوقتي.';
  }
  if (m.contains('Invalid login')) return 'الإيميل أو كلمة السر غلط.';
  return m;
}

void showError(BuildContext context, Object e) {
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
  Drink(this.id, this.name, this.prices);
  factory Drink.from(Map<String, dynamic> m) {
    final prices = <String, double>{};
    for (final p in (m['drink_prices'] as List)) {
      final row = p as Map<String, dynamic>;
      prices[row['size'] as String] = (row['price'] as num).toDouble();
    }
    return Drink(m['id'] as String, m['name'] as String, prices);
  }
  double get minPrice =>
      prices.isEmpty ? 0 : prices.values.reduce((a, b) => a < b ? a : b);
}

class Menu {
  final List<Drink> drinks;
  final List<Addon> addons;
  Menu(this.drinks, this.addons);
}

Future<Menu> loadMenu() async {
  final d = await sb
      .from('drinks')
      .select('id, name, drink_prices(size, price)')
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
  return '${drink['name']} ${sizeLabel[it['size']] ?? ''} × ${it['qty']}';
}

String itemNotes(Map<String, dynamic> it) {
  final parts = <String>[sugarDesc[it['sugar']] ?? ''];
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
  bool _busy = false;

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _pass.text.length < 6) {
      showError(context, 'اكتب الإيميل وكلمة سر 6 حروف على الأقل.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_signUp) {
        await sb.auth.signUp(
          email: email,
          password: _pass.text,
          data: {'full_name': _name.text.trim()},
        );
        if (sb.auth.currentSession == null) {
          await sb.auth.signInWithPassword(email: email, password: _pass.text);
        }
      } else {
        await sb.auth.signInWithPassword(email: email, password: _pass.text);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Center(
                child: Text('الناصية',
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
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'الإيميل'),
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
      ),
    );
  }
}
