import 'package:flutter/material.dart';

import 'core.dart';

/// "9:30 صباحاً", "12 بالليل" from minutes since midnight (1440 = midnight).
String fmtMinutes(int m) {
  final h24 = (m ~/ 60) % 24;
  final min = m % 60;
  final period = h24 == 0
      ? 'بالليل'
      : h24 < 12
          ? 'صباحاً'
          : h24 == 12
              ? 'ضهراً'
              : h24 < 18
                  ? 'العصر'
                  : 'بالليل';
  var h = h24 % 12;
  if (h == 0) h = 12;
  return min == 0 ? '$h $period' : '$h:${min.toString().padLeft(2, '0')} $period';
}

class StoreStatus {
  final bool open;
  final int openMin;
  final int closeMin;
  final bool forceClosed;
  const StoreStatus(this.open, this.openMin, this.closeMin, this.forceClosed);

  String get hoursText => 'من ${fmtMinutes(openMin)} لحد ${fmtMinutes(closeMin)}';
  String get message => forceClosed
      ? 'إحنا مقفولين دلوقتي. هنفتح قريب.'
      : 'إحنا مقفولين دلوقتي. مواعيدنا $hoursText.';
}

/// Asks the server whether the cart is taking orders right now. Null when unreachable.
Future<StoreStatus?> loadStoreStatus() async {
  try {
    final r = await sb.rpc('store_status') as Map<String, dynamic>;
    return StoreStatus(
      r['open'] as bool,
      (r['open_min'] as num).toInt(),
      (r['close_min'] as num).toInt(),
      (r['force_closed'] as bool?) ?? false,
    );
  } catch (_) {
    return null;
  }
}

class ClosedBanner extends StatelessWidget {
  final StoreStatus status;
  const ClosedBanner({super.key, required this.status});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cCream2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cGold, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.nightlight_round, color: cGold),
          const SizedBox(width: 10),
          Expanded(
              child: Text(status.message,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

/// Owner only: working hours, closing switch and early-arrival bonus range.
class OpsSettingsDialog extends StatefulWidget {
  const OpsSettingsDialog({super.key});
  @override
  State<OpsSettingsDialog> createState() => _OpsSettingsDialogState();
}

class _OpsSettingsDialogState extends State<OpsSettingsDialog> {
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  int _open = 570;
  int _close = 1440;
  bool _enforce = true;
  bool _forceClosed = false;
  bool _bonusOn = true;
  final _bMin = TextEditingController(text: '10');
  final _bMax = TextEditingController(text: '20');
  final _bTh = TextEditingController(text: '5');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bMin.dispose();
    _bMax.dispose();
    _bTh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await sb
          .from('app_settings')
          .select('key, value')
          .inFilter('key', ['hours', 'incentives']);
      final m = {for (final r in rows) r['key'] as String: (r['value'] as Map)};
      final h = m['hours'] ?? {};
      final i = m['incentives'] ?? {};
      if (!mounted) return;
      setState(() {
        _open = (h['open_min'] as num?)?.toInt() ?? 570;
        _close = (h['close_min'] as num?)?.toInt() ?? 1440;
        _enforce = (h['enforce'] as bool?) ?? true;
        _forceClosed = (h['force_closed'] as bool?) ?? false;
        _bonusOn = (i['enabled'] as bool?) ?? true;
        _bMin.text = '${(i['early_bonus_min'] as num?)?.toInt() ?? 10}';
        _bMax.text = '${(i['early_bonus_max'] as num?)?.toInt() ?? 20}';
        _bTh.text = '${(i['early_threshold_min'] as num?)?.toInt() ?? 5}';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _pick(bool isOpen) async {
    final cur = isOpen ? _open : _close;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (cur ~/ 60) % 24, minute: cur % 60),
    );
    if (t == null) return;
    var m = t.hour * 60 + t.minute;
    if (!isOpen && m == 0) m = 1440;
    setState(() => isOpen ? _open = m : _close = m);
  }

  Future<void> _save() async {
    final mn = int.tryParse(_bMin.text.trim()) ?? 10;
    final mx = int.tryParse(_bMax.text.trim()) ?? 20;
    final th = int.tryParse(_bTh.text.trim()) ?? 5;
    if (mx < mn) {
      showError(context, 'أقل مكافأة لازم تكون أصغر من أكبر مكافأة.');
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await sb.from('app_settings').upsert([
        {
          'key': 'hours',
          'value': {
            'open_min': _open,
            'close_min': _close,
            'enforce': _enforce,
            'force_closed': _forceClosed,
          },
          'updated_at': now,
        },
        {
          'key': 'incentives',
          'value': {
            'enabled': _bonusOn,
            'early_bonus_min': mn,
            'early_bonus_max': mx,
            'early_threshold_min': th,
          },
          'updated_at': now,
        },
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اتحفظت الإعدادات.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  Widget _num(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading) {
      content = const SizedBox(
          height: 100, child: Center(child: CircularProgressIndicator()));
    } else if (_failed) {
      content = const Text('مقدرناش نحمّل الإعدادات. اتأكد من الإنترنت وجرّب تاني.');
    } else {
      content = SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مواعيد الشغل', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => _pick(true),
                      child: Text('بنفتح: ${fmtMinutes(_open)}'))),
              const SizedBox(width: 10),
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => _pick(false),
                      child: Text('بنقفل: ${fmtMinutes(_close)}'))),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('التزم بالمواعيد دي'),
              subtitle: const Text('لو مقفول، الطلبات الجديدة بتتقفل برا المواعيد.'),
              value: _enforce,
              onChanged: (v) => setState(() => _enforce = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اقفل الطلبات دلوقتي'),
              subtitle: const Text('يقفل الاستقبال فوراً لحد ما تفتحه.'),
              value: _forceClosed,
              onChanged: (v) => setState(() => _forceClosed = v),
            ),
            const Divider(color: cHair),
            const Text('مكافأة الحضور المبكر',
                style: TextStyle(fontWeight: FontWeight.w800)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مفعّلة'),
              value: _bonusOn,
              onChanged: (v) => setState(() => _bonusOn = v),
            ),
            Row(children: [
              _num(_bMin, 'أقل (ج)'),
              const SizedBox(width: 8),
              _num(_bMax, 'أكبر (ج)'),
              const SizedBox(width: 8),
              _num(_bTh, 'قبل الميعاد بـ (د)'),
            ]),
          ],
        ),
      );
    }
    return AlertDialog(
      title: const Text('إعدادات التشغيل'),
      content: SizedBox(width: 520, child: content),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('إغلاق')),
        if (!_loading && !_failed)
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'بنحفظ...' : 'حفظ')),
      ],
    );
  }
}
