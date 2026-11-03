import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserAttributes;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'appearance.dart';
import 'cashier.dart';
import 'core.dart';
import 'ops.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'update.dart';

part 'admin_more.dart';

const jobLabels = {
  'seller': 'بياع',
  'barista': 'باريستا',
  'delivery': 'ديليفري',
  'reception': 'استقبال أونلاين',
  'manager': 'مدير',
};

Map<String, String> get _catNames => {for (final c in menuCategories) c.id: c.name};

const _expenseCats = {
  'stock': 'مواد خام',
  'payroll': 'مرتبات وسلف',
  'bills': 'فواتير',
  'maintenance': 'صيانة',
  'other': 'أخرى',
};

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

num _n(dynamic v) => (v as num?) ?? 0;

Widget _loading() => const Center(child: CircularProgressIndicator());

Widget _problem(Object e, VoidCallback retry) => ProblemView(
      offline: isNetworkError(e),
      title: isNetworkError(e) ? 'انقطع الاتصال بالإنترنت' : 'مقدرناش نحمّل البيانات',
      hint: 'جرّب تاني بعد شوية.',
      onRetry: retry,
    );

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Kpi(this.label, this.value, {this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cCream2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cHair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: cMuted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color ?? cInk)),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  final String? title;
  final Widget child;
  const _Panel({this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cCream2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cHair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      );
}

// ------------------------------------------------------------------ shell

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _i = 0;
  static const _all = [
    ('overview', 'نظرة عامة', Icons.dashboard_outlined),
    ('products', 'المنتجات', Icons.local_cafe_outlined),
    ('staff', 'الموظفين', Icons.groups_outlined),
    ('incentives', 'الحوافز', Icons.emoji_events_outlined),
    ('payroll', 'المرتبات', Icons.payments_outlined),
    ('expenses', 'المصروفات', Icons.receipt_long_outlined),
    ('offers', 'التوصيل والعروض', Icons.local_offer_outlined),
    ('reports', 'التقارير والفواتير', Icons.assessment_outlined),
    ('customers', 'العملاء', Icons.people_outline),
    ('audit', 'سجل التعديلات', Icons.history),
    ('settings', 'الدفع والإعدادات', Icons.settings_outlined),
  ];

  /// The supervisor sees reports, expenses and customers; the owner sees everything.
  List<(String, String, IconData)> get _items => isOwner
      ? _all
      : _all
          .where((x) => const ['overview', 'expenses', 'reports', 'customers'].contains(x.$1))
          .toList();

  Widget _section() {
    switch (_items[_i.clamp(0, _items.length - 1)].$1) {
      case 'overview':
        return const _OverviewSection();
      case 'products':
        return const _ProductsSection();
      case 'staff':
        return const _StaffSection();
      case 'incentives':
        return const _IncentivesSection();
      case 'payroll':
        return const _PayrollSection();
      case 'offers':
        return const _OffersSection();
      case 'audit':
        return const _AuditSection();
      case 'expenses':
        return const _ExpensesSection();
      case 'reports':
        return const _ReportsSection();
      case 'customers':
        return const _CustomersSection();
      default:
        return const _SettingsSection();
    }
  }

  void _openWork(String mode) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CashierGate(forceHome: true, mode: mode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isOwner ? 'BONNAYA • لوحة تحكم المالك' : 'BONNAYA • لوحة المدير',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton.icon(
              icon: const Icon(Icons.point_of_sale),
              label: const Text('شاشة البيع'),
              onPressed: () => _openWork('sell')),
          TextButton.icon(
              icon: const Icon(Icons.delivery_dining),
              label: const Text('الأوردرات الأونلاين'),
              onPressed: () => _openWork('online')),
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
          SizedBox(
            width: 220,
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                for (var k = 0; k < _items.length; k++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      selected: _i == k,
                      selectedTileColor: cBrand,
                      selectedColor: cOnBrand,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: Icon(_items[k].$3),
                      title: Text(_items[k].$2,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => setState(() => _i = k),
                    ),
                  ),
                const Divider(height: 24, color: cHair),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) => FilledButton.icon(
                    icon: const Icon(Icons.system_update_alt),
                    label: Text('تحديث البرنامج${snap.hasData ? ' • نسخة ${snap.data!.buildNumber}' : ''}'),
                    onPressed: () => autoPatchNow(context),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, color: cHair),
          Expanded(child: _section()),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ overview

class _OverviewSection extends StatefulWidget {
  const _OverviewSection();
  @override
  State<_OverviewSection> createState() => _OverviewSectionState();
}

class _OverviewSectionState extends State<_OverviewSection> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final now = DateTime.now();
    final today = await sb.rpc('owner_report',
        params: {'p_from': _d(now), 'p_to': _d(now)});
    final month = await sb.rpc('owner_report', params: {
      'p_from': _d(DateTime(now.year, now.month, 1)),
      'p_to': _d(now)
    });
    final present = await sb
        .from('attendance')
        .select('delta_minutes')
        .eq('day', _d(now));
    return [
      Map<String, dynamic>.from(today as Map),
      Map<String, dynamic>.from(month as Map),
      {'present': (present as List).length,
       'late': present.where((r) => ((r['delta_minutes'] as num?) ?? 0) >= 2).length},
    ];
  }

  Widget _row(String t, Map<String, dynamic> r) => _Panel(
        title: t,
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          _Kpi('المبيعات', money(_n(r['sales']))),
          _Kpi('الأوردرات', '${_n(r['orders'])}'),
          _Kpi('تحويلات', money(_n(r['wallet']))),
          _Kpi('فيزا', money(_n(r['visa']))),
          _Kpi('كاش', money(_n(r['cash']))),
          _Kpi('خصومات', money(_n(r['discounts']))),
          _Kpi('ملغي', '${_n(r['cancelled'])}'),
          _Kpi('مصروفات', money(_n(r['expenses']))),
          _Kpi('حوافز وعمولات', money(_n(r['bonuses']))),
          _Kpi('الصافي', money(_n(r['net'])), color: cBrand),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError) {
          return _problem(snap.error!, () => setState(() => _f = _load()));
        }
        final d = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              const Text('نظرة عامة',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                  tooltip: 'تحديث',
                  onPressed: () => setState(() => _f = _load()),
                  icon: const Icon(Icons.refresh)),
            ]),
            if (_n(d[0]['pending_transfers']) > 0)
              _Panel(
                child: Row(children: [
                  const Icon(Icons.hourglass_top, color: cGold),
                  const SizedBox(width: 10),
                  Text('${_n(d[0]['pending_transfers'])} أوردر مستني تأكيد التحويل (من الدفع والإعدادات).',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            if ((d[0]['low_stock'] as List?)?.isNotEmpty == true)
              _Panel(
                title: 'قارب على النفاد',
                child: Wrap(spacing: 10, runSpacing: 6, children: [
                  for (final x in (d[0]['low_stock'] as List).cast<Map>())
                    Chip(
                      avatar: const Icon(Icons.warning_amber, size: 18, color: cGold),
                      label: Text('${x['name']} • باقي ${x['left']}'),
                    ),
                ]),
              ),
            _Panel(
              title: 'الحضور النهاردة',
              child: Wrap(spacing: 12, children: [
                _Kpi('حاضرين', '${d[2]['present']}'),
                _Kpi('متأخرين', '${d[2]['late']}',
                    color: (d[2]['late'] as int) > 0 ? cGold : cInk),
              ]),
            ),
            _row('النهاردة', d[0]),
            _row('الشهر ده', d[1]),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------ products

class _ProductsSection extends StatefulWidget {
  const _ProductsSection();
  @override
  State<_ProductsSection> createState() => _ProductsSectionState();
}

class _ProductsSectionState extends State<_ProductsSection> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    await fetchCategories();
    final r = await sb
        .from('drinks')
        .select('id, name, category, active, base_cost, sort_order, stock_qty, sold_out, is_coffee, drink_prices(size, price)')
        .order('sort_order');
    return (r as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _f = _load());

  String _prices(Map<String, dynamic> d) {
    final m = {
      for (final p in (d['drink_prices'] as List)) p['size'] as String: _n(p['price'])
    };
    if (m.length <= 1) return m.isEmpty ? '—' : money(m.values.first);
    return sizeKeys.where(m.containsKey).map((k) => '${sizeLabel[k]} ${money(m[k]!)}').join(' • ');
  }

  Future<void> _toggle(Map<String, dynamic> d, bool v) async {
    try {
      await sb.from('drinks').update({'active': v}).eq('id', d['id']);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('مسح ${d['name']}؟'),
        content: const Text('لو عليه طلبات قديمة مش هينفع يتمسح، وقتها اخفيه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لأ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('امسح')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sb.from('drinks').delete().eq('id', d['id']);
      _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('الصنف ده عليه طلبات قديمة، اخفيه بدل ما تمسحه.')));
      }
    }
  }

  Future<void> _edit(Map<String, dynamic>? d, int nextSort) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductDialog(drink: d, nextSort: nextSort),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError) return _problem(snap.error!, _reload);
        final all = snap.data!;
        final next =
            all.fold<int>(0, (m, d) => ((d['sort_order'] as num).toInt() > m) ? (d['sort_order'] as num).toInt() : m) + 1;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              const Text('المنتجات',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const Spacer(),
              OutlinedButton.icon(
                  onPressed: () async {
                    await showDialog<void>(
                        context: context, builder: (_) => const _CategoriesDialog());
                    _reload();
                  },
                  icon: const Icon(Icons.category_outlined),
                  label: const Text('الأقسام')),
              const SizedBox(width: 8),
              FilledButton.icon(
                  onPressed: () => _edit(null, next),
                  icon: const Icon(Icons.add),
                  label: const Text('صنف جديد')),
            ]),
            for (final cat in _catNames.keys)
              if (all.any((d) => d['category'] == cat))
                _Panel(
                  title: _catNames[cat],
                  child: Column(children: [
                    for (final d in all.where((d) => d['category'] == cat))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('${d['name']}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: d['active'] == true ? cInk : cMuted)),
                                Text(
                                    '${_prices(d)}'
                                    '${d['sold_out'] == true ? '  •  خلص' : ''}'
                                    '${d['stock_qty'] != null ? '  •  المخزون ${d['stock_qty']}' : ''}',
                                    style: TextStyle(
                                        color: (d['sold_out'] == true ||
                                                (d['stock_qty'] != null && (d['stock_qty'] as num) <= 5))
                                            ? cGold
                                            : cMuted,
                                        fontSize: 12.5)),
                              ])),
                          Switch(
                              value: d['active'] == true,
                              onChanged: (v) => _toggle(d, v)),
                          IconButton(
                              tooltip: 'تعديل',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(d, next)),
                          IconButton(
                              tooltip: 'مسح',
                              icon: const Icon(Icons.delete_outline, color: cDanger),
                              onPressed: () => _delete(d)),
                        ]),
                      ),
                  ]),
                ),
          ],
        );
      },
    );
  }
}

class _ProductDialog extends StatefulWidget {
  final Map<String, dynamic>? drink;
  final int nextSort;
  const _ProductDialog({this.drink, required this.nextSort});
  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final _name = TextEditingController(text: '${widget.drink?['name'] ?? ''}');
  late final _cost =
      TextEditingController(text: '${_n(widget.drink?['base_cost'])}');
  final _single = TextEditingController();
  final _sizes = {
    'small': TextEditingController(),
    'medium': TextEditingController(),
    'large': TextEditingController(),
  };
  late final _stock = TextEditingController(
      text: widget.drink?['stock_qty'] == null ? '' : '${widget.drink?['stock_qty']}');
  bool _soldOut = false;
  bool _coffee = false;
  String _cat = 'hot';
  bool _multi = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.drink;
    if (d != null) {
      _cat = d['category'] as String? ?? 'hot';
      _soldOut = d['sold_out'] == true;
      _coffee = d['is_coffee'] == true;
      final prices = {
        for (final p in (d['drink_prices'] as List)) p['size'] as String: _n(p['price'])
      };
      _multi = prices.length > 1;
      if (_multi) {
        prices.forEach((k, v) => _sizes[k]?.text = '$v');
      } else if (prices.isNotEmpty) {
        _single.text = '${prices.values.first}';
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    _single.dispose();
    for (final c in _sizes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final prices = <String, double>{};
    if (_multi) {
      for (final k in sizeKeys) {
        final v = double.tryParse(_sizes[k]!.text.trim());
        if (v != null) prices[k] = v;
      }
    } else {
      final v = double.tryParse(_single.text.trim());
      if (v != null) prices['medium'] = v;
    }
    if (name.isEmpty || prices.isEmpty) {
      showError(context, 'اكتب اسم الصنف وسعره.');
      return;
    }
    setState(() => _saving = true);
    try {
      var id = widget.drink?['id'] as String?;
      final row = {
        'name': name,
        'category': _cat,
        'base_cost': double.tryParse(_cost.text.trim()) ?? 0,
        'stock_qty': int.tryParse(_stock.text.trim()),
        'sold_out': _soldOut,
        'is_coffee': _coffee,
      };
      if (id == null) {
        final r = await sb
            .from('drinks')
            .insert({...row, 'sort_order': widget.nextSort})
            .select('id')
            .single();
        id = r['id'] as String;
      } else {
        await sb.from('drinks').update(row).eq('id', id);
        await sb.from('drink_prices').delete().eq('drink_id', id);
      }
      await sb.from('drink_prices').insert([
        for (final e in prices.entries)
          {'drink_id': id, 'size': e.key, 'price': e.value}
      ]);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  Widget _f(TextEditingController c, String l) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.drink == null ? 'صنف جديد' : 'تعديل الصنف'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _cat,
              decoration: const InputDecoration(labelText: 'القسم'),
              items: [
                for (final e in _catNames.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value))
              ],
              onChanged: (v) => setState(() => _cat = v ?? _cat),
            ),
            TextField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'المخزون (سيبه فاضي لو مش بتعدّه)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('قهوة (السكر: سادة / على الريحة / مظبوط / زيادة)'),
              value: _coffee,
              onChanged: (v) => setState(() => _coffee = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('خلص دلوقتي (مؤقتاً)'),
              value: _soldOut,
              onChanged: (v) => setState(() => _soldOut = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('أحجام (صغير / وسط / كبير) وسكر'),
              value: _multi,
              onChanged: (v) => setState(() => _multi = v),
            ),
            if (_multi)
              Row(children: [
                _f(_sizes['small']!, 'صغير'),
                const SizedBox(width: 8),
                _f(_sizes['medium']!, 'وسط'),
                const SizedBox(width: 8),
                _f(_sizes['large']!, 'كبير'),
              ])
            else
              Row(children: [_f(_single, 'السعر (ج)')]),
            const SizedBox(height: 10),
            Row(children: [_f(_cost, 'تكلفة الصنف عليك (اختياري)')]),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'بنحفظ...' : 'حفظ')),
      ],
    );
  }
}

// ------------------------------------------------------------------ staff

class _StaffSection extends StatefulWidget {
  const _StaffSection();
  @override
  State<_StaffSection> createState() => _StaffSectionState();
}

class _StaffSectionState extends State<_StaffSection> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await sb
        .from('profiles')
        .select('id, full_name, role, staff_role, employee_no, shift_start, active')
        .neq('role', 'customer')
        .order('employee_no');
    return (r as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _f = _load());

  String _t(String? s) {
    if (s == null) return 'بدون ميعاد';
    final p = s.split(':');
    return fmtMinutes(int.parse(p[0]) * 60 + int.parse(p[1]));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError) return _problem(snap.error!, _reload);
        final list = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              const Text('الموظفين',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                      context: context, builder: (_) => const _AddStaffDialog());
                  if (ok == true) _reload();
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('موظف جديد'),
              ),
            ]),
            const SizedBox(height: 10),
            for (final p in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  tileColor: cCream2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: cHair)),
                  leading: CircleAvatar(
                    backgroundColor: cCream,
                    foregroundColor: cBrand,
                    child: Text(p['employee_no'] ?? (p['role'] == 'manager' ? '★' : '—'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  title: Text('${p['full_name'] ?? ''}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: p['active'] == false ? cMuted : cInk)),
                  subtitle: Text(p['role'] == 'manager'
                      ? 'المالك'
                      : '${jobLabels[p['staff_role']] ?? 'موظف'} • ${_t(p['shift_start'] as String?)}${p['active'] == false ? ' • موقوف' : ''}'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: p['role'] == 'manager'
                      ? null
                      : () async {
                          await showDialog<void>(
                              context: context,
                              builder: (_) => _StaffCardDialog(profile: p));
                          _reload();
                        },
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<String?> _pickTime(BuildContext context, String? cur) async {
  var init = const TimeOfDay(hour: 9, minute: 30);
  if (cur != null) {
    final p = cur.split(':');
    init = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }
  final t = await showTimePicker(context: context, initialTime: init);
  if (t == null) return null;
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
}

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();
  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String _job = 'seller';
  String _start = '09:30:00';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _user.text.trim().isEmpty) {
      showError(context, 'اكتب اسم الموظف واسم المستخدم.');
      return;
    }
    setState(() => _busy = true);
    try {
      final no = await sb.rpc('owner_create_staff', params: {
        'p_username': _user.text.trim(),
        'p_password': _pass.text,
        'p_name': _name.text.trim(),
        'p_staff_role': _job,
        'p_shift_start': _start,
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('اتضاف الموظف'),
          content: Text(
              'الرقم الوظيفي: $no\nاسم المستخدم: ${_user.text.trim().toLowerCase()}\nسلّمه كلمة السر بنفسك.'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام'))
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        final m = e.toString();
        if (m.contains('username taken')) {
          showError(context, 'اسم المستخدم ده مستخدم قبل كده.');
        } else if (m.contains('bad username')) {
          showError(context, 'اسم المستخدم حروف إنجليزي وأرقام و _ من 3 لـ 20.');
        } else {
          showError(context, e);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('موظف جديد'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 10),
            TextField(
                controller: _user,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'اسم المستخدم (إنجليزي)')),
            const SizedBox(height: 10),
            TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة السر (6 حروف على الأقل)')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _job,
              decoration: const InputDecoration(labelText: 'الوظيفة'),
              items: [
                for (final e in jobLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value))
              ],
              onChanged: (v) => setState(() => _job = v ?? _job),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text('ميعاد بداية الشغل: ${fmtMinutes(int.parse(_start.substring(0, 2)) * 60 + int.parse(_start.substring(3, 5)))}'),
              onPressed: () async {
                final t = await _pickTime(context, _start);
                if (t != null) setState(() => _start = t);
              },
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'بنضيف...' : 'إضافة')),
      ],
    );
  }
}

class _StaffCardDialog extends StatefulWidget {
  final Map<String, dynamic> profile;
  const _StaffCardDialog({required this.profile});
  @override
  State<_StaffCardDialog> createState() => _StaffCardDialogState();
}

class _StaffCardDialogState extends State<_StaffCardDialog> {
  late String _job = widget.profile['staff_role'] as String? ?? 'seller';
  late String? _start = widget.profile['shift_start'] as String?;
  late bool _active = widget.profile['active'] != false;
  late Future<Map<String, dynamic>> _f = _load();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _item = TextEditingController();
  String _kind = 'manual';

  String get _id => widget.profile['id'] as String;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _item.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final att = await sb
        .from('attendance')
        .select()
        .eq('staff_id', _id)
        .order('day', ascending: false)
        .limit(30);
    final bon = await sb
        .from('staff_bonuses')
        .select()
        .eq('staff_id', _id)
        .order('created_at', ascending: false)
        .limit(60);
    final gear = await sb
        .from('gear')
        .select()
        .eq('staff_id', _id)
        .order('given_at', ascending: false);
    final now = DateTime.now();
    final rep = await sb.rpc('owner_report', params: {
      'p_from': _d(now.subtract(const Duration(days: 30))),
      'p_to': _d(now)
    });
    final mine = ((rep as Map)['by_staff'] as List).cast<Map>().where(
        (s) => s['employee_no'] == widget.profile['employee_no']);
    return {
      'att': att,
      'bon': bon,
      'gear': gear,
      'sales': mine.isEmpty ? null : mine.first,
    };
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _run(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _saveInfo() => _run(() async {
        await sb.rpc('owner_set_staff', params: {
          'p_user': _id,
          'p_staff_role': _job,
          'p_shift_start': _start ?? '09:30:00',
        });
        await sb.rpc('owner_set_active', params: {'p_user': _id, 'p_active': _active});
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('اتحفظت بيانات الموظف.')));
        }
      });

  Future<void> _addBonus() => _run(() async {
        final v = double.tryParse(_amount.text.trim());
        if (v == null || v <= 0) {
          showError(context, 'اكتب مبلغ صحيح.');
          return;
        }
        await sb.from('staff_bonuses').insert({
          'staff_id': _id,
          'amount': v,
          'kind': _kind,
          'note': _note.text.trim(),
          'created_by': sb.auth.currentUser!.id,
        });
        _amount.clear();
        _note.clear();
        _reload();
      });

  Future<void> _addGear() => _run(() async {
        if (_item.text.trim().isEmpty) return;
        await sb.from('gear').insert({'staff_id': _id, 'item': _item.text.trim()});
        _item.clear();
        _reload();
      });

  static const _kinds = {
    'manual': 'مكافأة',
    'tip': 'بقشيش',
    'penalty': 'خصم',
    'advance': 'سلفة',
  };
  static const _kindAll = {
    'early': 'حضور مبكر',
    'commission': 'عمولة',
    'manual': 'مكافأة',
    'tip': 'بقشيش',
    'penalty': 'خصم',
    'advance': 'سلفة',
  };

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Dialog(
      child: SizedBox(
        width: 680,
        height: 560,
        child: DefaultTabController(
          length: 4,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                CircleAvatar(
                    backgroundColor: cBrand,
                    foregroundColor: cOnBrand,
                    child: Text('${p['employee_no'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('${p['full_name'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800))),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
            ),
            const TabBar(tabs: [
              Tab(text: 'بيانات'),
              Tab(text: 'حضور'),
              Tab(text: 'حوافز'),
              Tab(text: 'عهدة وزي'),
            ]),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _f,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return _loading();
                  if (snap.hasError) return _problem(snap.error!, _reload);
                  final d = snap.data!;
                  final att = (d['att'] as List).cast<Map<String, dynamic>>();
                  final bon = (d['bon'] as List).cast<Map<String, dynamic>>();
                  final gear = (d['gear'] as List).cast<Map<String, dynamic>>();
                  final sales = d['sales'] as Map?;
                  final total = bon.fold<double>(
                      0,
                      (s, b) =>
                          s + ((b['kind'] == 'penalty' || b['kind'] == 'advance') ? -1 : 1) * _n(b['amount']).toDouble());
                  return TabBarView(children: [
                    // ---- info
                    ListView(padding: const EdgeInsets.all(16), children: [
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        _Kpi('مبيعاته (30 يوم)', money(_n(sales?['total']))),
                        _Kpi('عدد البيعات', '${_n(sales?['n'])}'),
                        _Kpi('صافي حوافزه', money(total), color: cBrand),
                      ]),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _job,
                        decoration: const InputDecoration(labelText: 'الوظيفة'),
                        items: [
                          for (final e in jobLabels.entries)
                            DropdownMenuItem(value: e.key, child: Text(e.value))
                        ],
                        onChanged: (v) => setState(() => _job = v ?? _job),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: Text(_start == null
                            ? 'حدد ميعاد بداية الشغل'
                            : 'ميعاد بداية الشغل: ${fmtMinutes(int.parse(_start!.substring(0, 2)) * 60 + int.parse(_start!.substring(3, 5)))}'),
                        onPressed: () async {
                          final t = await _pickTime(context, _start);
                          if (t != null) setState(() => _start = t);
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('شغّال'),
                        subtitle: const Text('لو اتقفل مش هيعرف يدخل البرنامج.'),
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                      ),
                      FilledButton(onPressed: _saveInfo, child: const Text('حفظ')),
                    ]),
                    // ---- attendance
                    att.isEmpty
                        ? const Center(child: Text('مفيش حضور مسجل لسه.'))
                        : ListView(padding: const EdgeInsets.all(16), children: [
                            for (final a in att)
                              ListTile(
                                dense: true,
                                title: Text('${a['day']} • وصل ${fmtTime(a['checked_in_at'] as String)}'),
                                trailing: Text(
                                  (a['delta_minutes'] as num) >= 2
                                      ? 'متأخر ${a['delta_minutes']} د'
                                      : (a['delta_minutes'] as num) <= -5
                                          ? 'بدري ${-(a['delta_minutes'] as num)} د'
                                          : 'في الميعاد',
                                  style: TextStyle(
                                      color: (a['delta_minutes'] as num) >= 2
                                          ? cDanger
                                          : cGreen,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                          ]),
                    // ---- bonuses
                    ListView(padding: const EdgeInsets.all(16), children: [
                      Row(children: [
                        DropdownButton<String>(
                          value: _kind,
                          items: [
                            for (final e in _kinds.entries)
                              DropdownMenuItem(value: e.key, child: Text(e.value))
                          ],
                          onChanged: (v) => setState(() => _kind = v ?? _kind),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                            width: 100,
                            child: TextField(
                                controller: _amount,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'المبلغ'))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: TextField(
                                controller: _note,
                                decoration: const InputDecoration(labelText: 'السبب'))),
                        IconButton.filled(
                            onPressed: _addBonus, icon: const Icon(Icons.add)),
                      ]),
                      const SizedBox(height: 10),
                      for (final b in bon)
                        ListTile(
                          dense: true,
                          title: Text('${_kindAll[b['kind']] ?? b['kind']}${(b['note'] as String?)?.isNotEmpty == true ? ' • ${b['note']}' : ''}'),
                          subtitle: Text('${DateTime.parse(b['created_at'] as String).toLocal()}'.substring(0, 16)),
                          trailing: Text(
                              '${(b['kind'] == 'penalty' || b['kind'] == 'advance') ? '-' : '+'}${money(_n(b['amount']))}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: (b['kind'] == 'penalty' || b['kind'] == 'advance') ? cDanger : cGreen)),
                        ),
                    ]),
                    // ---- gear
                    ListView(padding: const EdgeInsets.all(16), children: [
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: _item,
                                decoration: const InputDecoration(
                                    labelText: 'عنصر جديد (يونيفورم، مفتاح، جهاز...)'))),
                        IconButton.filled(
                            onPressed: _addGear, icon: const Icon(Icons.add)),
                      ]),
                      const SizedBox(height: 10),
                      for (final g in gear)
                        ListTile(
                          dense: true,
                          title: Text('${g['item']}${(g['qty'] as num) > 1 ? ' × ${g['qty']}' : ''}'),
                          subtitle: Text(g['returned_at'] == null
                              ? 'مع الموظف'
                              : 'اتسلّم ورجع'),
                          trailing: g['returned_at'] == null
                              ? TextButton(
                                  onPressed: () => _run(() async {
                                        await sb.from('gear').update({
                                          'returned_at':
                                              DateTime.now().toUtc().toIso8601String()
                                        }).eq('id', g['id']);
                                        _reload();
                                      }),
                                  child: const Text('استلمته'))
                              : null,
                        ),
                    ]),
                  ]);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ incentives

class _IncentivesSection extends StatefulWidget {
  const _IncentivesSection();
  @override
  State<_IncentivesSection> createState() => _IncentivesSectionState();
}

class _IncentivesSectionState extends State<_IncentivesSection> {
  late Future<Map<String, dynamic>> _f = _load();
  final _pct = TextEditingController();
  final _flat = TextEditingController();
  bool _init = false;

  @override
  void dispose() {
    _pct.dispose();
    _flat.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final s = await sb
        .from('app_settings')
        .select('value')
        .eq('key', 'commission')
        .maybeSingle();
    final b = await sb
        .from('staff_bonuses')
        .select('*, profiles!staff_bonuses_staff_id_fkey(full_name)')
        .order('created_at', ascending: false)
        .limit(40);
    return {'c': (s?['value'] as Map?) ?? {}, 'b': b};
  }

  Future<void> _save() async {
    try {
      await sb.from('app_settings').upsert({
        'key': 'commission',
        'value': {
          'seller_pct': double.tryParse(_pct.text.trim()) ?? 0,
          'delivery_flat': double.tryParse(_flat.text.trim()) ?? 0,
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('اتحفظت العمولات.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError) {
          return _problem(snap.error!, () => setState(() => _f = _load()));
        }
        final c = snap.data!['c'] as Map;
        if (!_init) {
          _init = true;
          _pct.text = '${_n(c['seller_pct'])}';
          _flat.text = '${_n(c['delivery_flat'])}';
        }
        final bon = (snap.data!['b'] as List).cast<Map<String, dynamic>>();
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('الحوافز والعمولات',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _Panel(
            title: 'العمولات (صفر معناها مقفولة)',
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _pct,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'عمولة البياع % من كل بيعة'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: _flat,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'عمولة الديليفري (ج) لكل أوردر'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton(onPressed: _save, child: const Text('حفظ')),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const OpsSettingsDialog()),
                  icon: const Icon(Icons.tune),
                  label: const Text('مكافأة الحضور المبكر ومواعيد الشغل'),
                ),
              ]),
              const SizedBox(height: 6),
              const Text('البقشيش والمكافآت والخصومات اليدوية بتتسجل من كارت كل موظف (الموظفين).',
                  style: TextStyle(color: cMuted, fontSize: 12.5)),
            ]),
          ),
          _Panel(
            title: 'آخر الحوافز',
            child: Column(children: [
              if (bon.isEmpty) const Text('لسه مفيش حوافز.'),
              for (final b in bon)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${(b['profiles'] as Map?)?['full_name'] ?? ''}'),
                  subtitle: Text('${_StaffCardDialogState._kindAll[b['kind']] ?? b['kind']}${(b['note'] as String?)?.isNotEmpty == true ? ' • ${b['note']}' : ''}'),
                  trailing: Text(
                      '${(b['kind'] == 'penalty' || b['kind'] == 'advance') ? '-' : '+'}${money(_n(b['amount']))}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: (b['kind'] == 'penalty' || b['kind'] == 'advance') ? cDanger : cGreen)),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ expenses

class _ExpensesSection extends StatefulWidget {
  const _ExpensesSection();
  @override
  State<_ExpensesSection> createState() => _ExpensesSectionState();
}

class _ExpensesSectionState extends State<_ExpensesSection> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _cat = 'stock';

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final now = DateTime.now();
    final r = await sb
        .from('expenses')
        .select()
        .gte('day', _d(DateTime(now.year, now.month, 1)))
        .order('created_at', ascending: false);
    return (r as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _add() async {
    final v = double.tryParse(_amount.text.trim());
    if (_title.text.trim().isEmpty || v == null || v <= 0) {
      showError(context, 'اكتب البند والمبلغ.');
      return;
    }
    try {
      await sb.from('expenses').insert({
        'category': _cat,
        'title': _title.text.trim(),
        'amount': v,
        'paid_by': sb.auth.currentUser!.id,
      });
      _title.clear();
      _amount.clear();
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError) return _problem(snap.error!, _reload);
        final rows = snap.data!;
        final today = _d(DateTime.now());
        final tSum = rows
            .where((r) => r['day'] == today)
            .fold<double>(0, (s, r) => s + _n(r['amount']).toDouble());
        final mSum = rows.fold<double>(0, (s, r) => s + _n(r['amount']).toDouble());
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('المصروفات',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(spacing: 12, children: [
            _Kpi('النهاردة', money(tSum)),
            _Kpi('الشهر ده', money(mSum), color: cBrand),
          ]),
          const SizedBox(height: 14),
          _Panel(
            title: 'سجّل صرف',
            child: Row(children: [
              DropdownButton<String>(
                value: _cat,
                items: [
                  for (final e in _expenseCats.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value))
                ],
                onChanged: (v) => setState(() => _cat = v ?? _cat),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'البند'))),
              const SizedBox(width: 12),
              SizedBox(
                  width: 110,
                  child: TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'المبلغ'))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
            ]),
          ),
          _Panel(
            title: 'مصروفات الشهر',
            child: Column(children: [
              if (rows.isEmpty) const Text('لسه مفيش مصروفات الشهر ده.'),
              for (final r in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${r['title']}'),
                  subtitle: Text('${_expenseCats[r['category']] ?? ''} • ${r['day']}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(_n(r['amount'])),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      tooltip: 'مسح',
                      icon: const Icon(Icons.delete_outline, color: cDanger),
                      onPressed: () async {
                        try {
                          await sb.from('expenses').delete().eq('id', r['id']);
                          _reload();
                        } catch (e) {
                          if (mounted) showError(context, e);
                        }
                      },
                    ),
                  ]),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ reports + invoices

const _invoiceSelect =
    '*, order_items(*, drinks(name, is_coffee, drink_prices(size)), order_item_addons(*, addons(name)))';

class _ReportsSection extends StatefulWidget {
  const _ReportsSection();
  @override
  State<_ReportsSection> createState() => _ReportsSectionState();
}

class _ReportsSectionState extends State<_ReportsSection> {
  int _days = 1; // 1 = today, 7, 30
  late Future<Map<String, dynamic>> _f = _load();

  Future<Map<String, dynamic>> _load() async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: _days - 1));
    final rep = await sb.rpc('owner_report',
        params: {'p_from': _d(from), 'p_to': _d(now)});
    final inv = await sb
        .from('orders')
        .select(_invoiceSelect)
        .eq('status', 'delivered')
        .not('invoice_no', 'is', null)
        .order('invoice_no', ascending: false)
        .limit(40);
    return {'r': Map<String, dynamic>.from(rep as Map), 'inv': inv};
  }

  Future<void> _exportCsv(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: _days - 1));
      final rows = await sb
          .from('orders')
          .select('invoice_no, order_no, created_at, source, payment_method, status, discount, discount_reason, note, cancel_reason, total, seller_id')
          .inFilter('status', ['delivered', 'cancelled'])
          .gte('created_at', from.toUtc().toIso8601String())
          .order('created_at')
          .limit(5000);
      final names = <String, String>{};
      try {
        final ps = await sb.from('profiles').select('id, full_name').not('staff_role', 'is', null);
        for (final p in ps) {
          names[p['id'] as String] = (p['full_name'] as String?) ?? '';
        }
      } catch (_) {}
      String q(Object? v) {
        final t = '${v ?? ''}'.replaceAll('"', '""');
        return '"$t"';
      }
      final b = StringBuffer('\uFEFF')
        ..writeln('رقم الفاتورة,رقم الطلب,الوقت,المصدر,الدفع,الحالة,الخصم,سبب الخصم,الإجمالي,البائع,ملاحظة,سبب الإلغاء');
      for (final o in rows) {
        b.writeln([
          o['invoice_no'], o['order_no'], o['created_at'],
          o['source'] == 'pos' ? 'كاشير' : 'أونلاين',
          o['payment_method'], o['status'], o['discount'], o['discount_reason'],
          o['total'], names[o['seller_id']] ?? '', o['note'], o['cancel_reason'],
        ].map(q).join(','));
      }
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}bonnaya-sales-${_d(now)}.csv');
      await f.writeAsString(b.toString());
      m.showSnackBar(SnackBar(content: Text('اتحفظ الملف: ${f.path}')));
      await OpenFilex.open(f.path);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError) {
          return _problem(snap.error!, () => setState(() => _f = _load()));
        }
        final r = snap.data!['r'] as Map<String, dynamic>;
        final inv = (snap.data!['inv'] as List).cast<Map<String, dynamic>>();
        final byDay = (r['by_day'] as List).cast<Map>();
        final top = (r['top_items'] as List).cast<Map>();
        final byStaff = (r['by_staff'] as List).cast<Map>();
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Text('التقارير والفواتير',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const Spacer(),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('اليوم')),
                ButtonSegment(value: 7, label: Text('7 أيام')),
                ButtonSegment(value: 30, label: Text('30 يوم')),
              ],
              selected: {_days},
              onSelectionChanged: (v) => setState(() {
                _days = v.first;
                _f = _load();
              }),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Kpi('المبيعات', money(_n(r['sales']))),
            _Kpi('الأوردرات', '${_n(r['orders'])}'),
            _Kpi('تحويلات', money(_n(r['wallet']))),
            _Kpi('فيزا', money(_n(r['visa']))),
            _Kpi('كاش', money(_n(r['cash']))),
            _Kpi('خصومات', money(_n(r['discounts']))),
            _Kpi('ملغي', '${_n(r['cancelled'])}'),
            _Kpi('مصروفات', money(_n(r['expenses']))),
            _Kpi('حوافز وعمولات', money(_n(r['bonuses']))),
            _Kpi('الصافي', money(_n(r['net'])), color: cBrand),
          ]),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: const Text('تصدير المبيعات (Excel / CSV)'),
              onPressed: () => _exportCsv(context),
            ),
          ),
          const SizedBox(height: 14),
          if (byDay.length > 1)
            _Panel(
              title: 'يوم بيوم',
              child: Column(children: [
                for (final x in byDay)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Text('${x['day']}'),
                      const Spacer(),
                      Text('${x['n']} أوردر  •  '),
                      Text(money(_n(x['total'])),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ]),
            ),
          _Panel(
            title: 'الأكثر مبيعاً',
            child: Column(children: [
              if (top.isEmpty) const Text('مفيش مبيعات في الفترة دي.'),
              for (final x in top)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Text('${x['name']}'),
                    const Spacer(),
                    Text('${x['qty']} قطعة  •  '),
                    Text(money(_n(x['revenue'])),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
            ]),
          ),
          _Panel(
            title: 'مبيعات كل موظف',
            child: Column(children: [
              if (byStaff.isEmpty) const Text('مفيش مبيعات مسجلة على موظفين.'),
              for (final x in byStaff)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Text('${x['employee_no'] ?? ''}  ${x['name'] ?? ''}'),
                    const Spacer(),
                    Text('${x['n']} أوردر  •  '),
                    Text(money(_n(x['total'])),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
            ]),
          ),
          _Panel(
            title: 'آخر الفواتير (بترقيم متسلسل)',
            child: Column(children: [
              if (inv.isEmpty) const Text('لسه مفيش فواتير.'),
              for (final o in inv)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('فاتورة رقم ${o['invoice_no']}'),
                  subtitle: Text('طلب #${o['order_no']} • ${fmtTime(o['created_at'] as String)}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(_n(o['total'])),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      tooltip: 'اطبع',
                      icon: const Icon(Icons.print_outlined),
                      onPressed: () async {
                        try {
                          await printReceipt(o);
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                    ),
                  ]),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ payment + settings

class _SettingsSection extends StatefulWidget {
  const _SettingsSection();
  @override
  State<_SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<_SettingsSection> {
  late Future<Map<String, dynamic>> _f = _load();
  final _wallet = TextEditingController();
  final _wname = TextEditingController();
  final _maxDisc = TextEditingController();
  bool _init = false;

  @override
  void dispose() {
    _maxDisc.dispose();
    _wallet.dispose();
    _wname.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final s = await sb
        .from('app_settings')
        .select('value')
        .eq('key', 'payment')
        .maybeSingle();
    final pend = await sb
        .from('orders')
        .select('id, order_no, total, pay_ref, address_text, created_at')
        .eq('status', 'pending_payment')
        .order('created_at');
    final pos = await sb
        .from('app_settings')
        .select('value')
        .eq('key', 'pos')
        .maybeSingle();
    return {
      'p': (s?['value'] as Map?) ?? {},
      'pend': pend,
      'pos': (pos?['value'] as Map?) ?? {},
    };
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _saveWallet() async {
    try {
      await sb.from('app_settings').upsert({
        'key': 'payment',
        'value': {
          'wallet_number': _wallet.text.trim(),
          'wallet_name': _wname.text.trim(),
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('اتحفظ رقم المحفظة.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _saveDiscount() async {
    final v = double.tryParse(_maxDisc.text.trim());
    if (v == null || v < 0 || v > 100) {
      showError(context, 'اكتب نسبة من 0 لـ 100.');
      return;
    }
    try {
      await sb.from('app_settings').upsert({
        'key': 'pos',
        'value': {'max_discount_pct': v},
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('اتحفظ حد الخصم.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _confirm(String id) async {
    try {
      await sb.rpc('confirm_order_payment', params: {'p_order': id});
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError) return _problem(snap.error!, _reload);
        final p = snap.data!['p'] as Map;
        if (!_init) {
          _init = true;
          _wallet.text = '${p['wallet_number'] ?? ''}';
          _wname.text = '${p['wallet_name'] ?? ''}';
          final pos = snap.data!['pos'] as Map;
          _maxDisc.text = '${pos['max_discount_pct'] ?? 10}';
        }
        final pend = (snap.data!['pend'] as List).cast<Map<String, dynamic>>();
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('الدفع والإعدادات',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const _AccountPanel(),
          _Panel(
            title: 'المحفظة اللي العميل بيحوّل عليها',
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _wallet,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'رقم المحفظة'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: _wname,
                        decoration: const InputDecoration(labelText: 'الاسم (اختياري)'))),
                const SizedBox(width: 12),
                FilledButton(onPressed: _saveWallet, child: const Text('حفظ')),
              ]),
            ]),
          ),
          _Panel(
            title: 'حد الخصم للبائع',
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: _maxDisc,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'أقصى خصم يقدر البائع يعمله (٪ من الفاتورة)'))),
              const SizedBox(width: 12),
              FilledButton(onPressed: _saveDiscount, child: const Text('حفظ')),
            ]),
          ),
          _Panel(
            title: 'تحويلات مستنية التأكيد',
            child: Column(children: [
              if (pend.isEmpty) const Text('مفيش تحويلات مستنية.'),
              for (final o in pend)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('طلب #${o['order_no']} • ${money(_n(o['total']))}'),
                  subtitle: Text('من محفظة: ${o['pay_ref'] ?? ''}\n${o['address_text'] ?? ''}'),
                  isThreeLine: true,
                  trailing: FilledButton(
                      onPressed: () => _confirm(o['id'] as String),
                      child: const Text('تأكدت من التحويل')),
                ),
            ]),
          ),
          _Panel(
            title: 'إعدادات المتجر',
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                    context: context, builder: (_) => const OpsSettingsDialog()),
                icon: const Icon(Icons.schedule),
                label: const Text('مواعيد الشغل وقفل الطلبات'),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                    context: context, builder: (_) => const WelcomeSettingsDialog()),
                icon: const Icon(Icons.palette_outlined),
                label: const Text('شاشة الترحيب'),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}


/// Owner: add, rename and remove menu categories.
class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog();
  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog> {
  bool busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
      await fetchCategories();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _edit(MenuCategory? c) async {
    final name = TextEditingController(text: c?.name ?? '');
    var icon = c?.icon ?? 'restaurant';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? 'قسم جديد' : 'تعديل القسم'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'اسم القسم')),
                const SizedBox(height: 14),
                const Text('الأيقونة', style: TextStyle(color: cMuted)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in categoryIcons.entries)
                    ChoiceChip(
                      label: Icon(e.value, size: 22),
                      selected: icon == e.key,
                      selectedColor: cGold,
                      onSelected: (_) => set(() => icon = e.key),
                    ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final n = name.text.trim();
    if (ok != true || n.isEmpty) return;
    await _run(() async {
      if (c == null) {
        final id = 'c${DateTime.now().millisecondsSinceEpoch}';
        await sb.from('menu_categories').insert({
          'id': id,
          'name': n,
          'icon': icon,
          'sort_order': menuCategories.length + 1,
        });
      } else {
        await sb
            .from('menu_categories')
            .update({'name': n, 'icon': icon}).eq('id', c.id);
      }
    });
  }

  Future<void> _delete(MenuCategory c) async {
    final used = await sb.from('drinks').select('id').eq('category', c.id).limit(1);
    if (!mounted) return;
    if ((used as List).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('القسم فيه منتجات. انقلها لقسم تاني الأول وبعدين امسحه.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تمسح قسم "${c.name}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('لأ')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cDanger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('امسح')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => sb.from('menu_categories').delete().eq('id', c.id));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('أقسام المنيو'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in menuCategories)
              ListTile(
                leading: Icon(c.iconData),
                title: Text(c.name),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'تعديل الاسم والأيقونة',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: busy ? null : () => _edit(c)),
                  IconButton(
                      tooltip: 'مسح',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: busy ? null : () => _delete(c)),
                ]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
            onPressed: busy ? null : () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('قسم جديد')),
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('تمام')),
      ],
    );
  }
}


// ------------------------------------------------------------------ customers

class _CustomersSection extends StatefulWidget {
  const _CustomersSection();
  @override
  State<_CustomersSection> createState() => _CustomersSectionState();
}

class _CustomersSectionState extends State<_CustomersSection> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await sb.rpc('owner_customers');
    return (r as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError) {
          return _problem(snap.error!, () => setState(() => _f = _load()));
        }
        final l = snap.data!;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Text('العملاء',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(
                tooltip: 'تحديث',
                onPressed: () => setState(() => _f = _load()),
                icon: const Icon(Icons.refresh)),
          ]),
          _Panel(
            title: 'أكتر العملاء شراءً (${l.length})',
            child: Column(children: [
              if (l.isEmpty) const Text('لسه مفيش عملاء طلبوا.'),
              for (final c in l)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text((c['name'] as String?)?.isNotEmpty == true
                      ? '${c['name']}'
                      : 'بدون اسم'),
                  subtitle: Text(
                      '${_n(c['orders'])} أوردر • آخر أوردر ${fmtTime(c['last_order'] as String)}'),
                  trailing: Text(money(_n(c['spent'])),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}
