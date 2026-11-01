import 'package:flutter/material.dart';

import 'cashier.dart';
import 'core.dart';

// Cashier app (Windows EXE).
Future<void> main() async {
  await initNasya();
  runApp(const CashierApp());
}
