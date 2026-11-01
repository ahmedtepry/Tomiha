import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core.dart';

const _releasesApi =
    'https://api.github.com/repos/ahmedtepry/Tomiha/releases/latest';

/// Checks the latest published build; when it is newer than the installed
/// one, offers an update. Never shows errors: if anything fails it just
/// tries again later.
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
    Future.delayed(const Duration(seconds: 6), _check);
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
    try {
      final info = await PackageInfo.fromPlatform();
      final mine = int.tryParse(info.buildNumber) ?? 0;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(_releasesApi));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'bonnaya-app');
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        client.close();
        return;
      }
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final latest =
          int.tryParse((json['tag_name'] as String).replaceAll('build-', '')) ??
              0;
      if (latest <= mine || latest <= _dismissedBuild) return;
      final want = Platform.isWindows ? '.zip' : '.apk';
      String? url;
      for (final a in (json['assets'] as List)) {
        final n = (a['name'] as String).toLowerCase();
        if (n.endsWith(want)) url = a['browser_download_url'] as String;
      }
      if (url == null || !mounted) return;
      _showing = true;
      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('فيه تحديث جديد'),
          content: Text(Platform.isWindows
              ? 'نزّل النسخة الجديدة وفكّ الضغط وشغّلها بدل القديمة.'
              : 'فيه نسخة أحدث من بنايه. نزّلها وثبّتها فوق القديمة، وبياناتك هتفضل زي ما هي.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('بعدين')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حدّث دلوقتي')),
          ],
        ),
      );
      _showing = false;
      if (go == true) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _dismissedBuild = latest;
      }
    } catch (_) {
      _showing = false; // silent: try again later
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
