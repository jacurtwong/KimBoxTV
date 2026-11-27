import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'core/app_controller.dart';
import 'core/app_logger.dart';
import 'core/boss_key_service.dart';
import 'core/db/tvbox_db.dart';
import 'core/jvm_bridge.dart';
import 'core/local_http_server.dart';
import 'core/paths.dart';
import 'ui/home_view.dart';
import 'ui/player_view.dart';
import 'ui/theme.dart';
import 'ui/widgets/common_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 500;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  MediaKit.ensureInitialized();

  await AppPaths.init();
  TvboxDb.open();
  await LocalHttpServer.start();

  FlutterError.onError = (details) {
    AppLogger.log('flutter', details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (err, stack) {
    AppLogger.log('dart', '$err\n$stack');
    return false;
  };

  await windowManager.ensureInitialized();
  final ws = WindowStateService.load();

  final windowOptions = WindowOptions(
    size: Size(ws.width, ws.height),
    minimumSize: const Size(
      WindowStateService.minWidth,
      WindowStateService.minHeight,
    ),
    center: ws.x == null || ws.y == null,
    backgroundColor: KimTheme.deepBg,
    title: 'KimBoxTV',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (ws.x != null && ws.y != null) {
      await windowManager.setPosition(Offset(ws.x!, ws.y!));
    }
    if (ws.maximized) {
      await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
  });

  var appVersion = '3.18.23';
  try {
    final pkg = await PackageInfo.fromPlatform();
    if (pkg.version.isNotEmpty) appVersion = pkg.version;
  } catch (_) {}

  runApp(
    ProviderScope(
      child: KimBoxApp(appVersion: appVersion),
    ),
  );
}

class KimBoxApp extends ConsumerStatefulWidget {
  final String appVersion;

  const KimBoxApp({super.key, required this.appVersion});

  @override
  ConsumerState<KimBoxApp> createState() => _KimBoxAppState();
}

class _KimBoxAppState extends ConsumerState<KimBoxApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    Future.microtask(() async {
      if (!mounted) return;
      await ref.read(appControllerProvider.notifier).init(widget.appVersion);
      await WindowStateService.saveNow();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowResize() => WindowStateService.scheduleSave();

  @override
  void onWindowMove() => WindowStateService.scheduleSave();

  @override
  void onWindowMaximize() => WindowStateService.scheduleSave();

  @override
  void onWindowUnmaximize() => WindowStateService.scheduleSave();

  @override
  void onWindowClose() async {
    final ctrl = mounted ? ref.read(appControllerProvider.notifier) : null;
    ctrl?.saveHistory(force: true);
    await WindowStateService.saveNow();
    if (ctrl != null) {
      await ctrl.mpvService.dispose();
    }
    JvmBridge.stop();
    await LocalHttpServer.stop();
    TvboxDb.close();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KimBoxTV',
      debugShowCheckedModeBanner: false,
      theme: KimTheme.buildTheme(),
      home: const _RootShell(),
    );
  }
}

class _RootShell extends ConsumerWidget {
  const _RootShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(appControllerProvider);
    return Scaffold(
      backgroundColor: KimTheme.bg,
      body: Stack(
        children: [
          const HomeView(),
          if (st.playerOpen)
            const Positioned.fill(
              child: PlayerView(),
            ),
          GlobalToastOverlay(
            text: st.playerOpen ? null : st.toastText,
          ),
        ],
      ),
    );
  }
}
