import 'package:flutter/material.dart';

import 'cashier.dart';
import 'core.dart';
import 'offline.dart';
import 'devprefs.dart';

// Cashier app (Windows EXE).
Future<void> main() async {
  await initNasya();
  await loadDevPrefs();
  pendingSales.start();
  runApp(const CashierApp());
}
