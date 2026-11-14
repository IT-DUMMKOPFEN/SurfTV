// SlaxxTV - free internet TV from all over the world.
// Written by IT-Dummkopfen with the help of an AI.

import 'dart:ui' show AppExitResponse, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'channel_scanner.dart';
import 'widgets/channel_list.dart';
import 'widgets/dialogs.dart';
import 'widgets/epg_view.dart';
import 'widgets/remote_control.dart';
import 'widgets/scan_dialog.dart';
import 'widgets/tv_like.dart';
import 'widgets/tv_screen.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1400, 820),
      minimumSize: Size(640, 420),
      center: true,
      title: 'SlaxxTV',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final state = AppState();
  // Show the window first, then load settings and channels.
  runApp(SurfTvApp(state: state));
  state.load();
}

class SurfTvApp extends StatelessWidget {
  const SurfTvApp({super.key, required this.state});
  final AppState state;

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: b,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'SlaxxTV',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: state.themeMode,
        // Rows and lists can be swiped with the mouse too.
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        home: HomePage(state: state),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});
  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _focus = FocusNode(debugLabel: 'SlaxxTV keys');
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  AppState get s => widget.state;

  /// Keys are taken directly from the keyboard, so they work no matter
  /// which button has the focus (e.g. after closing a dialog).
  bool _onHardwareKey(KeyEvent e) {
    if (!mounted) return false;
    // A dialog is open: let it have the keys.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    return _onKey(_focus, e) == KeyEventResult.handled;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _lifecycle.dispose();
    s.updateDone.removeListener(_askQuickTest);
    _focus.dispose();
    super.dispose();
  }

  /// Keyboard: Esc leaves fullscreen, F / F11 fullscreen, ↑↓ zap,
  /// +/- volume, M mute, 0-9 favorite keys.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Do not steal keys while typing in the search field.
    final typing = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    final k = e.logicalKey;

    if (k == LogicalKeyboardKey.escape) {
      if (s.videoOnly) {
        s.exitVideoOnly();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.f1) {
      s.toggleUi();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f11) {
      s.toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (typing) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.keyF) {
      s.toggleFullscreen();
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.pageUp) {
      s.nextChannel();
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.pageDown) {
      s.previousChannel();
    } else if (k == LogicalKeyboardKey.keyM) {
      s.toggleMute();
    } else if (k == LogicalKeyboardKey.keyG) {
      showGuide(context, s);
    } else if (k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd ||
        k == LogicalKeyboardKey.equal) {
      s.volumeStep(5);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      s.volumeStep(-5);
    } else {
      final digit = _digit(k);
      if (digit == null) return KeyEventResult.ignored;
      s.recallFavorite(digit);
    }
    return KeyEventResult.handled;
  }

  int? _digit(LogicalKeyboardKey k) {
    const top = [
      LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    const pad = [
      LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
    ];
    final a = top.indexOf(k);
    if (a >= 0) return a;
    final b = pad.indexOf(k);
    return b >= 0 ? b : null;
  }

  /// Quit (window closed, Cmd+Q, Alt+F4): stop the player first.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await s.shutdown();
      return AppExitResponse.exit;
    },
    onDetach: () => s.shutdown(),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle; // start listening
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    s.updateDone.addListener(_askQuickTest);
    // Show the info window when the app starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _about();
    });
  }

  /// After an update: offer a quick test to remove channels that do not work.
  Future<void> _askQuickTest() async {
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.fact_check_outlined),
          SizedBox(width: 10),
          Text('Channel list updated'),
        ]),
        content: Text(
            'The complete list was read in: ${s.channels.length} channels.\n\n'
            'Run a quick test now? Channels that do not answer are removed '
            '(own feeds and My Channels stay). '
            'You can keep watching TV meanwhile.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Later')),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.bolt),
            label: const Text('Quick test'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      s.startJob(JobKind.test, TestMode.quick);
      showJobProgress(context, s).then((_) => _focus.requestFocus());
    }
  }

  /// Update link in the info window: start the update right away.
  void _quickUpdate() {
    if (!s.jobRunning) s.startJob(JobKind.update, TestMode.quick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showJobProgress(context, s).then((_) => _focus.requestFocus());
    });
  }

  Future<void> _job(JobKind kind) async {
    await showJobStart(context, s, initial: kind);
    _focus.requestFocus();
  }

  /// Info window (also shown when the app starts).
  void _about() {
    showInfo(context, onUpdate: _quickUpdate).then((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final remote = RemoteControl(
      state: s,
      onUpdate: () => _job(JobKind.update),
      onTest: () => _job(JobKind.test),
      onAbout: _about,
      onSwitchUi: s.toggleUi,
      onSettings: () => showSettings(context, s,
          onUpdate: () => _job(JobKind.update),
          onTest: () => _job(JobKind.test)),
    );

    return Focus(
      focusNode: _focus,
      autofocus: true,
      child: LayoutBuilder(builder: (context, box) {
        // ---- Fullscreen / Watch Live: only the picture ----
        if (s.videoOnly) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: TvScreen(state: s),
          );
        }

        // ---- TV like interface ----
        if (s.uiMode == UiMode.tvLike) {
          return TvLikeScreen(
            state: s,
            remote: remote,
            onUpdate: () => _job(JobKind.update),
            onTest: () => _job(JobKind.test),
          );
        }

        final wide = box.maxWidth >= 980;
        final portrait = box.maxHeight > box.maxWidth;

        // ---- Desktop / tablet: list | TV | remote ----
        if (wide) {
          return Scaffold(
            body: Row(children: [
              SizedBox(width: 310, child: ChannelList(state: s)),
              Expanded(child: TvScreen(state: s)),
              SizedBox(width: 270, child: remote),
            ]),
          );
        }

        // ---- Phone: TV on top, list and remote as drawers ----
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('SlaxxTV'),
            toolbarHeight: portrait ? kToolbarHeight : 40,
            leading: IconButton(
              tooltip: 'Channels',
              icon: const Icon(Icons.list),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            actions: [
              if (!portrait)
                IconButton(
                  tooltip: 'Remote control',
                  icon: const Icon(Icons.settings_remote),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
            ],
          ),
          drawer: Drawer(
            width: 320,
            child: SafeArea(
              child: ChannelList(
                state: s,
                onPicked: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
            ),
          ),
          endDrawer: portrait
              ? null
              : Drawer(width: 280, child: SafeArea(child: remote)),
          body: portrait
              ? Column(children: [
                  AspectRatio(aspectRatio: 16 / 9, child: TvScreen(state: s)),
                  Expanded(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: Center(
                        child: SizedBox(width: 290, child: remote),
                      ),
                    ),
                  ),
                ])
              : TvScreen(state: s),
        );
      }),
    );
  }
}
