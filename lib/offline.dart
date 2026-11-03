import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core.dart';

Future<File> _store(String name) async {
  final d = await getApplicationSupportDirectory();
  return File('${d.path}${Platform.pathSeparator}$name');
}

// ------------------------------------------------------------- menu cache

Future<void> saveMenuCache(List drinks, List addons) async {
  try {
    final f = await _store('menu_cache.json');
    await f.writeAsString(jsonEncode({
      'drinks': drinks,
      'addons': addons,
      'cats': [
        for (final c in menuCategories) {'id': c.id, 'name': c.name, 'icon': c.icon}
      ],
    }));
  } catch (_) {}
}

/// The last menu this device saw. Lets the cashier keep selling offline.
Future<Menu?> loadMenuCache() async {
  try {
    final f = await _store('menu_cache.json');
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final cats = (j['cats'] as List?) ?? [];
    if (cats.isNotEmpty) {
      menuCategories = [
        for (final c in cats)
          MenuCategory(c['id'] as String, c['name'] as String, (c['icon'] as String?) ?? 'restaurant')
      ];
    }
    return Menu(
      [for (final d in (j['drinks'] as List)) Drink.from(Map<String, dynamic>.from(d as Map))],
      [for (final a in (j['addons'] as List)) Addon.from(Map<String, dynamic>.from(a as Map))],
    );
  } catch (_) {
    return null;
  }
}

// ------------------------------------------------------------ pending sales

/// Sales made while the internet was down. They live on the device until
/// they reach the server, and each one carries a unique reference, so a
/// retry can never record the same sale twice.
class PendingSales extends ChangeNotifier {
  final List<Map<String, dynamic>> items = [];
  bool _syncing = false;
  bool _started = false;
  Timer? _timer;

  int get count => items.length;
  int get failed => items.where((s) => s['error'] != null).length;

  Future<void> _save() async {
    try {
      final f = await _store('pending_sales.json');
      await f.writeAsString(jsonEncode(items));
    } catch (_) {}
  }

  void start() {
    if (_started) return;
    _started = true;
    () async {
      try {
        final f = await _store('pending_sales.json');
        if (await f.exists()) {
          final l = jsonDecode(await f.readAsString()) as List;
          items.addAll(l.map((e) => Map<String, dynamic>.from(e as Map)));
          notifyListeners();
        }
      } catch (_) {}
      sync();
    }();
    net.addListener(() {
      if (net.online) sync();
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
  }

  Future<void> add(Map<String, dynamic> sale) async {
    items.add(sale);
    await _save();
    notifyListeners();
  }

  Future<void> discard(Map<String, dynamic> sale) async {
    items.remove(sale);
    await _save();
    notifyListeners();
  }

  Future<void> retry(Map<String, dynamic> sale) async {
    sale.remove('error');
    await _save();
    notifyListeners();
    sync();
  }

  Future<void> sync() async {
    if (_syncing || items.isEmpty || !net.online || sb.auth.currentSession == null) return;
    _syncing = true;
    try {
      for (final s in List<Map<String, dynamic>>.from(items)) {
        if (s['error'] != null) continue;
        try {
          await sb.rpc('pos_sale', params: {
            'p_ref': s['ref'],
            'p_items': s['items'],
            'p_payment': s['payment'],
            'p_seller': s['seller'],
            'p_discount': s['discount'],
            'p_reason': s['reason'],
            'p_note': s['note'],
            'p_at': s['at'],
          });
          items.remove(s);
          await _save();
          notifyListeners();
        } catch (e) {
          if (isNetworkError(e)) {
            net.markOffline();
            break;
          }
          s['error'] = errorText(e);
          await _save();
          notifyListeners();
        }
      }
    } finally {
      _syncing = false;
    }
  }
}

final pendingSales = PendingSales();

/// Strip with the number of sales waiting to reach the server.
class PendingBanner extends StatelessWidget {
  const PendingBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pendingSales,
      builder: (context, _) {
        if (pendingSales.count == 0) return const SizedBox.shrink();
        final bad = pendingSales.failed;
        return Material(
          color: bad > 0 ? cDanger : cGold,
          child: InkWell(
            onTap: () => showPendingDialog(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                Icon(net.online ? Icons.sync : Icons.cloud_off, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    bad > 0
                        ? '$bad فاتورة محتاجة مراجعة (دوس هنا)'
                        : (net.online
                            ? 'بنبعت ${pendingSales.count} فاتورة للسيرفر...'
                            : 'مفيش نت • ${pendingSales.count} فاتورة محفوظة وهتتبعت لوحدها'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showPendingDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: pendingSales,
      builder: (ctx, _) => AlertDialog(
        title: const Text('فواتير مستنية'),
        content: SizedBox(
          width: 420,
          child: pendingSales.items.isEmpty
              ? const Text('كله اتبعت. مفيش فواتير مستنية.')
              : ListView(shrinkWrap: true, children: [
                  for (final s in pendingSales.items)
                    Card(
                      child: ListTile(
                        title: Text('${money((s['total'] as num))} • ${s['payment'] == 'visa' ? 'فيزا' : 'كاش'}'),
                        subtitle: Text(s['error'] != null
                            ? '${s['label']}\nمتسجّلتش: ${s['error']}'
                            : '${s['label']}\nمستنية النت'),
                        isThreeLine: true,
                        trailing: s['error'] != null
                            ? Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                    tooltip: 'جرّب تاني',
                                    onPressed: () => pendingSales.retry(s),
                                    icon: const Icon(Icons.refresh)),
                                IconButton(
                                    tooltip: 'امسحها',
                                    onPressed: () => pendingSales.discard(s),
                                    icon: const Icon(Icons.delete_outline)),
                              ])
                            : null,
                      ),
                    ),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
        ],
      ),
    ),
  );
}
