import 'package:flutter/material.dart';

import 'core.dart';
import 'customer.dart';

// Customer app (Android APK).
Future<void> main() async {
  await initNasya();
  runApp(const CustomerApp());
}
