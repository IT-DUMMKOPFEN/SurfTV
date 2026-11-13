// SurfTV - free internet TV from all over the world.
// Written by IT-Dummkopfen with the help of an AI.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'widgets/channel_list.dart';
import 'widgets/remote_control.dart';
import 'widgets/scan_dialog.dart';
import 'widgets/tv_screen.dart';

const appVersion = '0.1a';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1400, 820),
      minimumSize: Size(640, 420),
      center: true,
      title: 'SurfTV',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final state = AppState();
  await state.load();
  runApp(SurfTvApp(state: state));
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
        title: 'SurfTV',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: state.themeMode,
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
  final _focus = FocusNode(debugLabel: 'SurfTV keys');
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  AppState get s => widget.state;

  @override
  void dispose() {
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
      if (s.fullscreen) {
        s.setFullscreen(false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
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

  void _update() async {
    await showScanDialog(context, s);
    _focus.requestFocus();
  }

  void _about() {
    showAboutDialog(
      context: context,
      applicationName: 'SurfTV',
      applicationVersion: appVersion,
      applicationIcon: Image.asset('assets/icon/icon.png', width: 56, height: 56),
      applicationLegalese:
          'Written by IT-Dummkopfen with the help of an AI.',
      children: const [
        SizedBox(height: 12),
        Text('Channel lists: iptv-org (github.com/iptv-org/iptv) and '
            'Free-TV (github.com/Free-TV/IPTV).\n'
            'SurfTV only plays streams that are publicly available on the '
            'internet. The "VPN" hint means the broadcaster probably limits '
            'the stream to its own country.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final remote = RemoteControl(state: s, onUpdate: _update, onAbout: _about);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        // ---- Fullscreen: only the picture ----
        if (s.fullscreen) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: TvScreen(state: s),
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
            title: const Text('SurfTV'),
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
