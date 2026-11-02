import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core.dart';

/// A delivery address: free text (street, building, floor) plus a map location.
class Address {
  final String text;
  final double? lat;
  final double? lng;
  final String? url;
  const Address({required this.text, this.lat, this.lng, this.url});

  Map<String, dynamic> toJson() =>
      {'text': text, 'lat': lat, 'lng': lng, 'url': mapsLink};

  static Address? fromJson(dynamic j) {
    if (j is! Map) return null;
    final t = (j['text'] as String?)?.trim() ?? '';
    if (t.isEmpty) return null;
    return Address(
      text: t,
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      url: j['url'] as String?,
    );
  }

  /// A Google Maps link for this address (from coordinates when we have them).
  String? get mapsLink {
    if (lat != null && lng != null) {
      return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
    return (url == null || url!.trim().isEmpty) ? null : url!.trim();
  }

  bool get hasLocation => mapsLink != null;
}

Future<void> openMaps(BuildContext context, String? url) async {
  try {
    final ok = await launchUrl(
        Uri.parse(url ?? 'https://www.google.com/maps'),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مقدرناش نفتح جوجل مابس.')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مقدرناش نفتح جوجل مابس.')));
    }
  }
}

/// Pulls "lat,lng" out of a pasted Google Maps link or plain coordinates.
({double lat, double lng})? parseLatLng(String s) {
  final r = RegExp(r'(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})');
  final m = r.firstMatch(Uri.decodeFull(s));
  if (m == null) return null;
  final lat = double.tryParse(m.group(1)!);
  final lng = double.tryParse(m.group(2)!);
  if (lat == null || lng == null) return null;
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  return (lat: lat, lng: lng);
}

/// Wallet number the customer should transfer to (set by the owner).
Future<({String number, String name})> loadWallet() async {
  try {
    final r = await sb
        .from('app_settings')
        .select('value')
        .eq('key', 'payment')
        .maybeSingle();
    final v = (r?['value'] as Map?) ?? {};
    return (
      number: ((v['wallet_number'] as String?) ?? '').trim(),
      name: ((v['wallet_name'] as String?) ?? '').trim()
    );
  } catch (_) {
    return (number: '', name: '');
  }
}

Future<Address?> loadSavedAddress() async {
  final u = sb.auth.currentUser;
  if (u == null) return null;
  try {
    final r = await sb
        .from('profiles')
        .select('default_address')
        .eq('id', u.id)
        .maybeSingle();
    return Address.fromJson(r?['default_address']);
  } catch (_) {
    return null;
  }
}

Future<void> saveDefaultAddress(Address a) async {
  final u = sb.auth.currentUser;
  if (u == null) return;
  await sb.from('profiles').update({'default_address': a.toJson()}).eq('id', u.id);
}

/// Bottom sheet to choose where the order goes.
class AddressSheet extends StatefulWidget {
  final Address? initial;
  const AddressSheet({super.key, this.initial});
  @override
  State<AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<AddressSheet> {
  late final _text = TextEditingController(text: widget.initial?.text ?? '');
  final _link = TextEditingController();
  double? _lat;
  double? _lng;
  String? _url;
  bool _locating = false;
  bool _openedMaps = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _lat = widget.initial?.lat;
    _lng = widget.initial?.lng;
    _url = widget.initial?.url;
  }

  @override
  void dispose() {
    _text.dispose();
    _link.dispose();
    super.dispose();
  }

  bool get _hasLocation =>
      (_lat != null && _lng != null) || (_url != null && _url!.isNotEmpty);

  Future<void> _useCurrent() async {
    setState(() {
      _locating = true;
      _msg = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _msg = 'شغّل الموقع (GPS) في تليفونك وجرّب تاني.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _msg =
            'محتاجين إذن الموقع عشان نحدد مكانك. اسمح بيه من إعدادات التطبيق، أو اختار عنوان من جوجل مابس.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 20));
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
        _url = null;
        _msg = 'تم تحديد موقعك الحالي ✓';
      });
    } catch (_) {
      setState(() => _msg = 'مقدرناش نحدد موقعك. جرّب تاني أو اختار من جوجل مابس.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickOnMaps() async {
    await openMaps(context, null);
    if (mounted) setState(() => _openedMaps = true);
  }

  void _applyLink() {
    final s = _link.text.trim();
    if (s.isEmpty) return;
    final ll = parseLatLng(s);
    setState(() {
      if (ll != null) {
        _lat = ll.lat;
        _lng = ll.lng;
        _url = null;
      } else {
        _lat = null;
        _lng = null;
        _url = s;
      }
      _msg = 'تم حفظ الموقع من جوجل مابس ✓';
    });
  }

  void _confirm() {
    if (_link.text.trim().isNotEmpty) _applyLink();
    if (_text.text.trim().isEmpty) {
      setState(() => _msg = 'اكتب تفاصيل العنوان (الشارع، العمارة، الدور).');
      return;
    }
    if (!_hasLocation) {
      setState(() => _msg = 'حدّد موقعك الأول: الموقع الحالي أو من جوجل مابس.');
      return;
    }
    Navigator.pop(
        context, Address(text: _text.text.trim(), lat: _lat, lng: _lng, url: _url));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('فين العنوان؟',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: _locating ? null : _useCurrent,
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
                label: Text(_locating ? 'بنحدد مكانك...' : 'تحديد العنوان الحالي'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: _pickOnMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('عنوان آخر من جوجل مابس'),
              ),
              if (_openedMaps) ...[
                const SizedBox(height: 8),
                const Text(
                    'اختار المكان في جوجل مابس، دوس مشاركة، انسخ اللينك وارجع هنا والصقه.',
                    style: TextStyle(color: cMuted, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _link,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'الصق لينك المكان هنا',
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.check), onPressed: _applyLink),
                  ),
                ),
              ],
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_msg!,
                      style: TextStyle(
                          color: _msg!.contains('✓') ? cGreen : cGold,
                          fontWeight: FontWeight.w600)),
                ),
              if (_hasLocation && (_msg == null || !_msg!.contains('✓')))
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('الموقع متحدد ✓',
                      style: TextStyle(color: cGreen, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'تفاصيل العنوان',
                  hintText: 'الشارع، رقم العمارة، الدور، علامة مميزة',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54)),
                onPressed: _confirm,
                child: const Text('تأكيد العنوان'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
