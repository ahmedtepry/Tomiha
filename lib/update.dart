import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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
          ? 'هننزّل النسخة الجديدة، والبرنامج هيتقفل ويفتح تاني لوحده.'
          : 'هننزّل النسخة الجديدة من هنا وتثبّتها فوق القديمة، وبياناتك هتفضل زي ما هي.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('بعدين')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حدّث دلوقتي')),
      ],
    ),
  );
  if (go == true && context.mounted) await installUpdate(context, i);
}

/// Downloads the new build inside the app and installs it.
Future<void> installUpdate(BuildContext context, UpdateInfo i) async {
  final progress = ValueNotifier<double?>(null);
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('بننزّل التحديث'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (ctx2, v, child) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v),
              const SizedBox(height: 12),
              Text(v == null ? 'استنى شوية...' : '${(v * 100).round()}%'),
            ],
          ),
        ),
      ),
    ),
  );
  late File file;
  try {
    final dir = await getTemporaryDirectory();
    file = File('${dir.path}${Platform.pathSeparator}'
        '${Platform.isWindows ? 'bonnaya-update.zip' : 'bonnaya-update.apk'}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final req = await client.getUrl(Uri.parse(i.url!));
    req.headers.set('User-Agent', 'bonnaya-app');
    final res = await req.close();
    if (res.statusCode != 200) throw HttpException('status ${res.statusCode}');
    final total = res.contentLength;
    var got = 0;
    final sink = file.openWrite();
    await for (final chunk in res) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) progress.value = got / total;
    }
    await sink.close();
    client.close();
  } catch (_) {
    nav.pop();
    messenger.showSnackBar(const SnackBar(
        content: Text('مقدرناش ننزّل التحديث. اتأكد من الإنترنت وجرّب تاني.')));
    return;
  }
  nav.pop();
  try {
    if (Platform.isWindows) {
      await _applyWindows(file);
    } else {
      final r = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) {
        messenger.showSnackBar(const SnackBar(
            content: Text('اسمح للأبلكيشن يثبّت التحديث من الإعدادات وجرّب تاني.')));
      }
    }
  } catch (_) {
    messenger.showSnackBar(
        const SnackBar(content: Text('مقدرناش نثبّت التحديث. جرّب تاني بعد شوية.')));
  }
}

/// Windows: unzip next to a small script that copies the files over the
/// running app once it has closed, then opens it again.
Future<void> _applyWindows(File zip) async {
  final exe = Platform.resolvedExecutable;
  final dst = File(exe).parent.path;
  final tmp = await getTemporaryDirectory();
  final src = Directory('${tmp.path}\\bonnaya-update');
  if (src.existsSync()) src.deleteSync(recursive: true);
  src.createSync(recursive: true);
  final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
  for (final f in archive) {
    final out = '${src.path}\\${f.name.replaceAll('/', '\\')}';
    if (f.isFile) {
      File(out)
        ..createSync(recursive: true)
        ..writeAsBytesSync(f.content as List<int>);
    } else {
      Directory(out).createSync(recursive: true);
    }
  }
  final bat = File('${tmp.path}\\bonnaya-update.bat');
  bat.writeAsStringSync('@echo off\r\n'
      'timeout /t 3 /nobreak >nul\r\n'
      'xcopy /E /Y /Q "${src.path}\\*" "$dst\\"\r\n'
      'start "" "$exe"\r\n');
  await Process.start('cmd', ['/c', bat.path], mode: ProcessStartMode.detached);
  exit(0);
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
