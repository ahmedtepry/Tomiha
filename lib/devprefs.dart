import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'core.dart';

/// Settings that belong to this computer (printer, fingerprint).
class DevPrefs {
  String? printer; // url of the receipt printer; null = ask each time
  String? printerName;
  bool biometric = true;
}

final devPrefs = DevPrefs();

Future<File> _file() async {
  final d = await getApplicationSupportDirectory();
  return File('${d.path}${Platform.pathSeparator}device_prefs.json');
}

Future<void> loadDevPrefs() async {
  try {
    final f = await _file();
    if (!await f.exists()) return;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    devPrefs.printer = j['printer'] as String?;
    devPrefs.printerName = j['printer_name'] as String?;
    devPrefs.biometric = j['biometric'] != false;
  } catch (_) {}
}

Future<void> saveDevPrefs() async {
  try {
    final f = await _file();
    await f.writeAsString(jsonEncode({
      'printer': devPrefs.printer,
      'printer_name': devPrefs.printerName,
      'biometric': devPrefs.biometric,
    }));
  } catch (_) {}
}

// ------------------------------------------------------------------ fonts

pw.Font? _reg;
pw.Font? _bold;

/// Arabic fonts for receipts. Online: the Cairo family; offline: the copy
/// bundled with the app, so printing never depends on the internet.
Future<(pw.Font, pw.Font)> receiptFonts() async {
  if (_reg != null && _bold != null) return (_reg!, _bold!);
  if (net.online) {
    try {
      _reg = await PdfGoogleFonts.cairoRegular();
      _bold = await PdfGoogleFonts.cairoBold();
      return (_reg!, _bold!);
    } catch (_) {}
  }
  try {
    final data = await rootBundle.load('assets/fonts/Cairo.ttf');
    final f = pw.Font.ttf(data);
    return (f, f);
  } catch (_) {
    final f = pw.Font.helvetica();
    return (f, f);
  }
}

// --------------------------------------------------------------- printing

/// Prints straight to the chosen receipt printer (no dialog). When no printer
/// was chosen, or it is not reachable, the normal print dialog opens.
Future<void> printDoc(String name, pw.Document doc) async {
  final bytes = await doc.save();
  final url = devPrefs.printer;
  if (url != null && Platform.isWindows) {
    try {
      final printers = await Printing.listPrinters();
      for (final p in printers) {
        if (p.url == url) {
          final ok = await Printing.directPrintPdf(
              printer: p, name: name, onLayout: (PdfPageFormat f) async => bytes);
          if (ok) return;
          break;
        }
      }
    } catch (_) {}
  }
  await Printing.layoutPdf(name: name, onLayout: (PdfPageFormat f) async => bytes);
}

// ------------------------------------------------------------- fingerprint

/// Asks for fingerprint / Windows Hello. Where the computer has none,
/// or the check itself is broken, it lets the cashier through.
Future<bool> confirmPresence(String reason) async {
  if (!devPrefs.biometric) return true;
  try {
    final auth = LocalAuthentication();
    if (!await auth.isDeviceSupported()) return true;
    return await auth.authenticate(localizedReason: reason);
  } catch (_) {
    return true;
  }
}

// ----------------------------------------------------------------- dialog

Future<void> showDeviceSettings(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _DeviceDialog());
}

class _DeviceDialog extends StatefulWidget {
  const _DeviceDialog();
  @override
  State<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends State<_DeviceDialog> {
  List<Printer> _printers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (Platform.isWindows) _printers = await Printing.listPrinters();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إعدادات الجهاز ده'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('طابعة الفواتير',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const Text('لو اخترت طابعة، الفاتورة بتتطبع مباشرة من غير نافذة.',
                      style: TextStyle(color: cMuted, fontSize: 13)),
                  RadioListTile<String?>(
                    value: null,
                    groupValue: devPrefs.printer,
                    title: const Text('اسألني كل مرة'),
                    onChanged: (v) {
                      setState(() {
                        devPrefs.printer = null;
                        devPrefs.printerName = null;
                      });
                      saveDevPrefs();
                    },
                  ),
                  for (final p in _printers)
                    RadioListTile<String?>(
                      value: p.url,
                      groupValue: devPrefs.printer,
                      title: Text(p.name),
                      onChanged: (v) {
                        setState(() {
                          devPrefs.printer = p.url;
                          devPrefs.printerName = p.name;
                        });
                        saveDevPrefs();
                      },
                    ),
                  if (_printers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('مفيش طابعات ظاهرة على الجهاز ده.',
                          style: TextStyle(color: cMuted)),
                    ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: devPrefs.biometric,
                    title: const Text('بصمة / Windows Hello عند فتح الوردية'),
                    subtitle: const Text('لو الجهاز مفيهوش بصمة بيتخطّاها لوحده.'),
                    onChanged: (v) {
                      setState(() => devPrefs.biometric = v);
                      saveDevPrefs();
                    },
                  ),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('تمام')),
      ],
    );
  }
}
