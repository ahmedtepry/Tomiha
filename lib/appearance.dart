import 'package:flutter/material.dart';

import 'core.dart';
import 'welcome.dart';

/// Owner-only: choose the welcome-screen cup and edit the coffee quotes.
class WelcomeSettingsDialog extends StatefulWidget {
  const WelcomeSettingsDialog({super.key});
  @override
  State<WelcomeSettingsDialog> createState() => _WelcomeSettingsDialogState();
}

class _WelcomeSettingsDialogState extends State<WelcomeSettingsDialog> {
  bool _loading = true;
  bool _manager = false;
  bool _saving = false;
  bool _failed = false;
  String _cup = 'finjan';
  bool _show = true;
  final _quotes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quotes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = sb.auth.currentUser!.id;
      final prof =
          await sb.from('profiles').select('role').eq('id', uid).maybeSingle();
      final isManager = prof?['role'] == 'manager';
      final row = await sb
          .from('app_settings')
          .select('value')
          .eq('key', 'welcome')
          .maybeSingle();
      final cfg = WelcomeConfig.fromJson(row?['value']);
      if (!mounted) return;
      setState(() {
        _manager = isManager;
        _cup = cfg.cup;
        _show = cfg.showQuote;
        _quotes.text = cfg.quotes.join('\n');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<String> _quoteList() => _quotes.text
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final list = _quoteList();
      await sb.from('app_settings').upsert({
        'key': 'welcome',
        'value': {
          'cup': _cup,
          'show_quote': _show,
          'quotes': list.isEmpty ? defaultQuotes : list,
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اتحفظ. الشكل الجديد هيظهر للعملاء أول ما يفتحوا الأبلكيشن.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  void _preview() {
    final list = _quoteList();
    final q = !_show
        ? null
        : (list.isEmpty ? defaultQuotes.first : list[DateTime.now().second % list.length]);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => WelcomeScreen(
        cup: _cup,
        quote: q,
        onDone: () {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        },
      ),
    ));
  }

  Widget _tile(String id) {
    final on = id == _cup;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _cup = id),
      child: Container(
        width: 128,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
        decoration: BoxDecoration(
          color: on ? cCream2 : cCream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? cBrand : cHair, width: on ? 2.5 : 1),
        ),
        child: Column(
          children: [
            SizedBox(
              width: 116,
              height: 145,
              child: CustomPaint(painter: CupPainter(id, 3.6)),
            ),
            const SizedBox(height: 4),
            Text(welcomeCups[id]!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    color: on ? cBrand : cInk)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading) {
      content = const SizedBox(
          height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_failed) {
      content = const Text('مقدرناش نحمّل الإعدادات. اتأكد من الإنترنت وجرّب تاني.');
    } else if (!_manager) {
      content = const Text('إعدادات المظهر للمالك فقط.');
    } else {
      content = SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الكوباية اللي بتظهر أول ما العميل يفتح الأبلكيشن',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final id in welcomeCups.keys) _tile(id)],
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار مقولة عن القهوة تحت الكوباية'),
              value: _show,
              onChanged: (v) => setState(() => _show = v),
            ),
            if (_show) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _quotes,
                minLines: 5,
                maxLines: 9,
                decoration: const InputDecoration(
                  labelText: 'المقولات (كل مقولة في سطر، وبتتغير كل مرة)',
                ),
              ),
            ],
          ],
        ),
      );
    }
    return AlertDialog(
      title: const Text('شاشة الترحيب'),
      content: SizedBox(width: 640, child: content),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('إغلاق')),
        if (!_loading && _manager && !_failed) ...[
          TextButton(
              onPressed: _saving ? null : _preview, child: const Text('معاينة')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'بنحفظ...' : 'حفظ')),
        ],
      ],
    );
  }
}
