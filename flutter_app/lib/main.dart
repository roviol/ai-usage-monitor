import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_controller.dart';
import 'config/store.dart';
import 'platform/interfaces.dart';
import 'platform/io_impl.dart';
import 'platform/secrets.dart';
import 'platform/single_instance.dart';
import 'ui/dashboard.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  // The data root is resolved first so the single-instance files live next to
  // the settings and cache.
  final paths = resolveDataPaths(ExecutableLocator.resolve());
  final controller = AppController(
    clock: SystemClock(),
    http: IoHttpTransport(),
    process: IoProcessRunner(),
    secrets: createPlatformSecretStore(),
    instanceSignal: IoSingleInstanceSignal.create(paths.root),
    executablePath: ExecutableLocator.resolve(),
  );
  runApp(AiUsageMonitorApp(controller: controller));
}

class AiUsageMonitorApp extends StatelessWidget {
  const AiUsageMonitorApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeOverride.maybeOf(context) ?? View.of(context).platformDispatcher.platformBrightness;
    return MaterialApp(
      title: 'AI Usage Monitor',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: DashboardHost(controller: controller),
    );
  }
}

class DashboardHost extends StatefulWidget {
  const DashboardHost({super.key, required this.controller});

  final AppController controller;

  @override
  State<DashboardHost> createState() => _DashboardHostState();
}

class _DashboardHostState extends State<DashboardHost> with WindowListener {
  bool _alwaysOnTop = false;
  final bool _trayUnavailable = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _configureWindow();
    widget.controller.addListener(_onControllerChanged);
    widget.controller.startup();
  }

  Future<void> _configureWindow() async {
    await windowManager.waitUntilReadyToShow(null, () async {
      await windowManager.setTitle('AI Usage Monitor');
      await windowManager.setMinimumSize(const Size(420, 320));
      await windowManager.show();
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final enabled = widget.controller.settings.alwaysOnTop;
    if (enabled != _alwaysOnTop) {
      setState(() {
        _alwaysOnTop = enabled;
      });
      _applyAlwaysOnTop(enabled);
    }
  }

  Future<void> _applyAlwaysOnTop(bool enabled) async {
    await windowManager.setAlwaysOnTop(enabled);
  }

  @override
  void onWindowClose() async {
    // Close-to-tray: hide instead of exiting while background work continues.
    await windowManager.hide();
  }

  void _refresh() => widget.controller.refreshAll();

  Future<void> _openSettings() async {
    final tester = ConnectionTester(http: IoHttpTransport(), process: IoProcessRunner(), secrets: createPlatformSecretStore());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsPage(
          initial: widget.controller.settings,
          secrets: widget.controller.secrets,
          tester: tester,
          onSave: (settings) {
            widget.controller.applySettings(settings);
            Navigator.of(context).pop();
          },
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return DashboardPage(
          snapshots: widget.controller.orderedSnapshots(),
          onRefresh: _refresh,
          onSettings: _openSettings,
          trayUnavailable: _trayUnavailable,
        );
      },
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.dispose();
    super.dispose();
  }
}