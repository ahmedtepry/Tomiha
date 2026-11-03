part of 'admin.dart';

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void _toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

// ------------------------------------------------------- offers & delivery

class _OffersSection extends StatefulWidget {
  const _OffersSection();
  @override
  State<_OffersSection> createState() => _OffersSectionState();
}

class _OffersSectionState extends State<_OffersSection> {
  late Future<Map<String, dynamic>> _f = _load();
  final _fee = TextEditingController();
  final _min = TextEditingController();
  final _free = TextEditingController();
  final _every = TextEditingController();
  final _pval = TextEditingController();
  final _minR = TextEditingController();
  bool _loyalty = true;
  bool _init = false;

  @override
  void dispose() {
    for (final c in [_fee, _min, _free, _every, _pval, _minR]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final s = await sb.from('app_settings').select('key, value').inFilter('key', ['delivery', 'loyalty']);
    final c = await sb.from('coupons').select().order('created_at', ascending: false);
    return {
      'settings': {for (final r in s) r['key'] as String: (r['value'] as Map)},
      'coupons': c,
    };
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _save() async {
    double v(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await sb.from('app_settings').upsert({
        'key': 'delivery',
        'value': {'fee': v(_fee), 'min_order': v(_min), 'free_over': v(_free)},
        'updated_at': now,
      });
      await sb.from('app_settings').upsert({
        'key': 'loyalty',
        'value': {
          'enabled': _loyalty,
          'earn_every': v(_every) <= 0 ? 10 : v(_every),
          'point_value': v(_pval) <= 0 ? 0.5 : v(_pval),
          'min_redeem': v(_minR).round(),
        },
        'updated_at': now,
      });
      if (mounted) _toast(context, 'اتحفظت الإعدادات.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _addCoupon() async {
    final code = TextEditingController();
    final value = TextEditingController();
    final minO = TextEditingController(text: '0');
    final uses = TextEditingController();
    var kind = 'pct';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('كوبون جديد'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'الكود (مثلاً BONNAYA10)')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pct', label: Text('نسبة %')),
                  ButtonSegment(value: 'fixed', label: Text('مبلغ ثابت')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => set(() => kind = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: value,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: kind == 'pct' ? 'النسبة' : 'المبلغ')),
              TextField(
                  controller: minO,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'أقل قيمة للطلب')),
              TextField(
                  controller: uses,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'عدد مرات الاستخدام (فاضي = بلا حد)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(value.text.trim());
    if (code.text.trim().isEmpty || v == null || v <= 0 || (kind == 'pct' && v > 100)) {
      if (mounted) showError(context, 'راجع الكود والقيمة.');
      return;
    }
    try {
      await sb.from('coupons').insert({
        'code': code.text.trim().toUpperCase(),
        'kind': kind,
        'value': v,
        'min_order': double.tryParse(minO.text.trim()) ?? 0,
        'max_uses': int.tryParse(uses.text.trim()),
      });
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggle(Map c) async {
    try {
      await sb.from('coupons').update({'active': !(c['active'] as bool)}).eq('code', c['code']);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Map c) async {
    try {
      await sb.from('coupons').delete().eq('code', c['code']);
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
        final st = snap.data!['settings'] as Map<String, Map>;
        if (!_init) {
          _init = true;
          final d = st['delivery'] ?? {};
          final l = st['loyalty'] ?? {};
          _fee.text = '${d['fee'] ?? 0}';
          _min.text = '${d['min_order'] ?? 0}';
          _free.text = '${d['free_over'] ?? 0}';
          _loyalty = l['enabled'] != false;
          _every.text = '${l['earn_every'] ?? 10}';
          _pval.text = '${l['point_value'] ?? 0.5}';
          _minR.text = '${l['min_redeem'] ?? 20}';
        }
        final coupons = (snap.data!['coupons'] as List).cast<Map<String, dynamic>>();
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('التوصيل والعروض',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _Panel(
            title: 'رسوم التوصيل',
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: _fee,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'رسوم التوصيل (ج)'))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'أقل قيمة للطلب (0 = بدون)'))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _free,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'توصيل مجاني فوق (0 = لأ)'))),
            ]),
          ),
          _Panel(
            title: 'نقاط الولاء',
            child: Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _loyalty,
                onChanged: (v) => setState(() => _loyalty = v),
                title: const Text('تشغيل النقاط'),
              ),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _every,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'كل كام جنيه = نقطة'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: _pval,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'قيمة النقطة (ج)'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: _minR,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'أقل نقاط للاستبدال'))),
              ]),
            ]),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(onPressed: _save, child: const Text('حفظ الإعدادات')),
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(
                child: Text('الكوبونات',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            FilledButton.icon(
                onPressed: _addCoupon,
                icon: const Icon(Icons.add),
                label: const Text('كوبون جديد')),
          ]),
          const SizedBox(height: 8),
          if (coupons.isEmpty) const Text('مفيش كوبونات لسه.', style: TextStyle(color: cMuted)),
          for (final c in coupons)
            Card(
              child: ListTile(
                title: Text('${c['code']}  •  ${c['kind'] == 'pct' ? '${c['value']}%' : money(c['value'] as num)}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                    'استخدم ${c['used']}${c['max_uses'] == null ? '' : ' من ${c['max_uses']}'}'
                    ' • أقل طلب ${money(c['min_order'] as num)}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(value: c['active'] as bool, onChanged: (_) => _toggle(c)),
                  IconButton(
                      tooltip: 'مسح',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(c)),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ payroll

class _PayrollSection extends StatefulWidget {
  const _PayrollSection();
  @override
  State<_PayrollSection> createState() => _PayrollSectionState();
}

class _PayrollSectionState extends State<_PayrollSection> {
  DateTime _m = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await sb.rpc('owner_payroll', params: {'p_month': _ymd(_m)});
    return (r as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _f = _load());

  void _shift(int d) {
    _m = DateTime(_m.year, _m.month + d, 1);
    _reload();
  }

  double _net(Map r) =>
      _n(r['base_salary']).toDouble() +
      _n(r['bonuses']).toDouble() -
      _n(r['penalties']).toDouble() -
      _n(r['advances']).toDouble();

  Future<void> _editSalary(Map r) async {
    final c = TextEditingController(text: '${_n(r['base_salary'])}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('مرتب ${r['full_name']}'),
        content: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'المرتب الشهري الأساسي (ج)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    final v = double.tryParse(c.text.trim());
    if (ok != true || v == null) return;
    try {
      await sb.rpc('owner_set_salary', params: {'p_user': r['staff_id'], 'p_salary': v});
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _advance(Map r) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('سلفة لـ ${r['full_name']}'),
        content: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'مبلغ السلفة (ج)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('سجّل')),
        ],
      ),
    );
    final v = double.tryParse(c.text.trim());
    if (ok != true || v == null || v <= 0) return;
    try {
      await sb.from('staff_bonuses').insert({
        'staff_id': r['staff_id'],
        'amount': v,
        'kind': 'advance',
        'note': 'سلفة',
        'created_by': sb.auth.currentUser?.id,
      });
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _payslip(Map r) async {
    try {
      final regular = await PdfGoogleFonts.cairoRegular();
      final bold = await PdfGoogleFonts.cairoBold();
      pw.Widget t(String s, {bool b = false, double size = 13}) => pw.Text(s,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: b ? bold : regular, fontSize: size));
      pw.Widget row(String a, String b, {bool bd = false}) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [t(b, b: bd), t(a, b: bd)]),
          );
      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Center(child: t('BONNAYA', b: true, size: 24)),
          pw.Center(child: t('قسيمة مرتب • ${_m.month}/${_m.year}', size: 14)),
          pw.Divider(),
          row('الاسم', '${r['full_name']}'),
          row('الوظيفة', jobLabels['${r['staff_role']}'] ?? ''),
          row('أيام الحضور', '${r['days']}'),
          pw.Divider(),
          row('المرتب الأساسي', money(_n(r['base_salary']))),
          row('حوافز ومكافآت', '+${money(_n(r['bonuses']))}'),
          row('خصومات', '-${money(_n(r['penalties']))}'),
          row('سلف', '-${money(_n(r['advances']))}'),
          pw.Divider(),
          row('الصافي', money(_net(r)), bd: true),
          pw.SizedBox(height: 28),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            t('توقيع المستلم: ..........'),
            t('توقيع الإدارة: ..........'),
          ]),
        ]),
      ));
      await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'payslip');
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
        final total = rows.fold<double>(0, (s, r) => s + _net(r));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Expanded(
                child: Text('المرتبات',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_right)),
            Text('${_m.month}/${_m.year}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_left)),
          ]),
          const SizedBox(height: 8),
          _Kpi('إجمالي المرتبات الصافية للشهر', money(total)),
          const SizedBox(height: 12),
          if (rows.isEmpty) const Text('مفيش موظفين.', style: TextStyle(color: cMuted)),
          for (final r in rows)
            _Panel(
              title: '${r['full_name'] ?? ''}  •  ${jobLabels['${r['staff_role']}'] ?? ''}',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 18, runSpacing: 4, children: [
                  Text('أساسي: ${money(_n(r['base_salary']))}'),
                  Text('حضور: ${r['days']} يوم'),
                  Text('حوافز: +${money(_n(r['bonuses']))}',
                      style: const TextStyle(color: cGreen)),
                  Text('خصومات: -${money(_n(r['penalties']))}',
                      style: const TextStyle(color: cDanger)),
                  Text('سلف: -${money(_n(r['advances']))}',
                      style: const TextStyle(color: cDanger)),
                ]),
                const SizedBox(height: 6),
                Text('الصافي: ${money(_net(r))}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton(onPressed: () => _editSalary(r), child: const Text('تعديل المرتب')),
                  OutlinedButton(onPressed: () => _advance(r), child: const Text('سلفة')),
                  FilledButton.icon(
                      onPressed: () => _payslip(r),
                      icon: const Icon(Icons.print),
                      label: const Text('قسيمة مرتب')),
                ]),
              ]),
            ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- audit log

class _AuditSection extends StatefulWidget {
  const _AuditSection();
  @override
  State<_AuditSection> createState() => _AuditSectionState();
}

class _AuditSectionState extends State<_AuditSection> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await sb.from('audit_log').select().order('at', ascending: false).limit(200);
    return (r as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _f = _load());

  static const _tables = {
    'drinks': 'منتج',
    'drink_prices': 'سعر',
    'addons': 'إضافة',
    'menu_categories': 'قسم',
    'app_settings': 'إعداد',
    'coupons': 'كوبون',
    'staff_bonuses': 'حافز/خصم',
    'expenses': 'مصروف',
    'profiles': 'موظف',
    'auth': 'باسورد',
  };
  static const _acts = {
    'insert': 'إضافة',
    'update': 'تعديل',
    'delete': 'مسح',
    'reset_password': 'إعادة تعيين',
  };

  String _what(Map r) {
    final m = (r['new'] ?? r['old']) as Map?;
    final name = m == null ? '' : (m['name'] ?? m['title'] ?? m['code'] ?? m['key'] ?? m['full_name'] ?? '');
    return '$name';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError) return _problem(snap.error!, _reload);
        final rows = snap.data!;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Expanded(
                child: Text('سجل التعديلات',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
            IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          ]),
          const Text('آخر 200 تعديل تم على المنتجات والأسعار والإعدادات والموظفين والمصروفات.',
              style: TextStyle(color: cMuted)),
          const SizedBox(height: 10),
          if (rows.isEmpty) const Text('لسه مفيش تعديلات.', style: TextStyle(color: cMuted)),
          for (final r in rows)
            Card(
              child: ListTile(
                dense: true,
                title: Text(
                    '${_acts[r['action']] ?? r['action']} ${_tables[r['table_name']] ?? r['table_name']}'
                    '${_what(r).isEmpty ? '' : ' • ${_what(r)}'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${r['actor_name'] ?? ''} • ${fmtTime(r['at'] as String)}'),
              ),
            ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------ account panel

class _AccountPanel extends StatefulWidget {
  const _AccountPanel();
  @override
  State<_AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<_AccountPanel> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _rep = TextEditingController();
  bool _busy = false;
  List<Map<String, dynamic>> _staff = [];
  String? _who;
  final _staffPass = TextEditingController();

  @override
  void initState() {
    super.initState();
    sb.from('profiles').select('id, full_name').not('staff_role', 'is', null).then((r) {
      if (mounted) setState(() => _staff = (r as List).cast<Map<String, dynamic>>());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _rep.dispose();
    _staffPass.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_new.text.length < 8) {
      showError(context, 'password short');
      return;
    }
    if (_new.text != _rep.text) {
      showError(context, 'الباسورد الجديد مش متطابق في الخانتين.');
      return;
    }
    setState(() => _busy = true);
    try {
      final email = sb.auth.currentUser?.email;
      if (email == null) throw 'no email';
      await sb.auth.signInWithPassword(email: email, password: _cur.text);
      await sb.auth.updateUser(UserAttributes(password: _new.text));
      _cur.clear();
      _new.clear();
      _rep.clear();
      if (mounted) _toast(context, 'اتغيّر الباسورد. استخدم الجديد في الدخول الجاي.');
    } catch (e) {
      if (mounted) showError(context, 'الباسورد الحالي غلط أو حصلت مشكلة. جرّب تاني.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _resetStaff() async {
    if (_who == null) return;
    setState(() => _busy = true);
    try {
      await sb.rpc('owner_reset_password', params: {'p_user': _who, 'p_password': _staffPass.text});
      _staffPass.clear();
      if (mounted) _toast(context, 'اتغيّر باسورد الموظف.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Panel(
        title: 'تغيير باسوردك',
        child: Column(children: [
          TextField(
              controller: _cur,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'الباسورد الحالي')),
          TextField(
              controller: _new,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'الباسورد الجديد (8 حروف أو أكتر)')),
          TextField(
              controller: _rep,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'اكتبه تاني')),
          const SizedBox(height: 10),
          Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                  onPressed: _busy ? null : _change, child: const Text('غيّر الباسورد'))),
        ]),
      ),
      _Panel(
        title: 'إعادة تعيين باسورد موظف',
        child: Column(children: [
          DropdownButtonFormField<String>(
            value: _who,
            decoration: const InputDecoration(labelText: 'الموظف'),
            items: [
              for (final s in _staff)
                DropdownMenuItem(value: s['id'] as String, child: Text('${s['full_name'] ?? ''}')),
            ],
            onChanged: (v) => setState(() => _who = v),
          ),
          TextField(
              controller: _staffPass,
              decoration: const InputDecoration(labelText: 'الباسورد الجديد (8 حروف أو أكتر)')),
          const SizedBox(height: 10),
          Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                  onPressed: _busy || _who == null ? null : _resetStaff,
                  child: const Text('غيّر باسورد الموظف'))),
        ]),
      ),
    ]);
  }
}
