import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _releasesApi =
    'https://api.github.com/repos/ahmedtepry/Tomiha/releases/latest';

class UpdateInfo {
  final int mine;
  final int latest;
  final String? url;
  const UpdateInfo(this.mine, this.latest, this.url);
  bool get available => latest > mine && url != null;
}

/// Asks GitHub for the newest published build. Returns null when it cannot
/// be reached (no internet, rate limit, anything else).
Future<UpdateInfo?> fetchUpdateInfo() async {
  HttpClient? client;
  try {
    final info = await PackageInfo.fromPlatform();
    final mine = int.tryParse(info.buildNumber) ?? 0;
    client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await client.getUrl(Uri.parse(_releasesApi));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'bonnaya-app');
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final latest =
        int.tryParse((json['tag_name'] as String).replaceAll('build-', '')) ?? 0;
    final want = Platform.isWindows ? '.zip' : '.apk';
    String? url;
    for (final a in (json['assets'] as List)) {
      final n = (a['name'] as String).toLowerCase();
      if (n.endsWith(want)) url = a['browser_download_url'] as String;
    }
    return UpdateInfo(mine, latest, url);
  } catch (_) {
    return null;
  } finally {
    client?.close();
  }
}

Future<void> promptUpdate(BuildContext context, UpdateInfo i) async {
  final go = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('فيه تحديث جديد'),
      content: Text(Platform.isWindows
          ? 'نزّل النسخة الجديدة وفكّ الضغط وشغّلها بدل القديمة.'
          : 'فيه نسخة أحدث من بنايه. نزّلها وثبّتها فوق القديمة، وبياناتك هتفضل زي ما هي.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('بعدين')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حدّث دلوقتي')),
      ],
    ),
  );
  if (go == true) {
    await launchUrl(Uri.parse(i.url!), mode: LaunchMode.externalApplication);
  }
}

/// Manual check, with a visible answer. Used by the "فحص التحديث" button.
Future<void> manualUpdateCheck(BuildContext context) async {
  final m = ScaffoldMessenger.of(context);
  m.showSnackBar(const SnackBar(content: Text('بنشوف لو فيه نسخة أحدث...')));
  final i = await fetchUpdateInfo();
  m.hideCurrentSnackBar();
  if (i == null) {
    m.showSnackBar(const SnackBar(
        content: Text('مقدرناش نوصل لسيرفر التحديثات. اتأكد من الإنترنت وجرّب تاني.')));
  } else if (i.available) {
    if (context.mounted) await promptUpdate(context, i);
  } else {
    m.showSnackBar(SnackBar(
        content: Text('إنت على آخر نسخة (نسخة ${i.mine}).')));
  }
}

/// Small "version + check for updates" button.
class VersionButton extends StatelessWidget {
  const VersionButton({super.key});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final v = snap.data?.buildNumber ?? '';
        return TextButton.icon(
          icon: const Icon(Icons.system_update_alt, size: 18),
          label: Text(v.isEmpty ? 'فحص التحديثات' : 'نسخة $v • فحص التحديثات'),
          onPressed: () => manualUpdateCheck(context),
        );
      },
    );
  }
}

/// Checks in the background and offers an update when a newer build exists.
/// Never shows errors: if anything fails it just tries again later.
class UpdateWatcher extends StatefulWidget {
  final Widget child;
  const UpdateWatcher({super.key, required this.child});
  @override
  State<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends State<UpdateWatcher>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _showing = false;
  int _dismissedBuild = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(seconds: 3), _check);
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_showing || !mounted) return;
    final i = await fetchUpdateInfo();
    if (i == null || !i.available || i.latest <= _dismissedBuild) return;
    if (!mounted) return;
    _showing = true;
    await promptUpdate(context, i);
    _showing = false;
    _dismissedBuild = i.latest;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
