import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_state.dart';
import 'flag.dart';

/// The TV picture in the middle.
/// Always a 16:9 screen - 4:3 channels are shown centered with black bars,
/// just like on a real TV.
class TvScreen extends StatefulWidget {
  const TvScreen({super.key, required this.state});

  final AppState state;

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> {
  Timer? _osdTimer;
  bool _osd = false;
  int _lastIndex = -2;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    _onState();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _osdTimer?.cancel();
    super.dispose();
  }

  void _onState() {
    final i = widget.state.currentIndex;
    if (i != _lastIndex) {
      _lastIndex = i;
      if (i >= 0) {
        setState(() => _osd = true);
        _osdTimer?.cancel();
        _osdTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _osd = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.current;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onDoubleTap: () =>
                  s.videoOnly ? s.exitVideoOnly() : s.toggleFullscreen(),
              child: ClipRect(
                child: Stack(fit: StackFit.expand, children: [
                  // BoxFit.contain keeps 4:3 pictures centered in the 16:9 area.
                  Video(
                    controller: s.video,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                    fill: Colors.black,
                  ),
                  if (c == null || !s.firstFrameSeen) _startPicture(s),
                  if (c != null && s.buffering && s.playError == null)
                    const Center(
                        child: CircularProgressIndicator(color: Colors.white70)),
                  if (c != null && s.playError != null) _error(s),
                  if (c != null)
                    Positioned(
                      left: 16,
                      top: 16,
                      child: AnimatedOpacity(
                        opacity: _osd ? 1 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: _osdBox(s),
                      ),
                    ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: AnimatedOpacity(
                      opacity: _hover ? 1 : 0.45,
                      duration: const Duration(milliseconds: 200),
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: s.videoOnly
                              ? 'Back (Esc)'
                              : 'Fullscreen (F)',
                          color: Colors.white,
                          icon: Icon(s.videoOnly
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen),
                          onPressed: () => s.videoOnly
                              ? s.exitVideoOnly()
                              : s.toggleFullscreen(),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Start picture (SurfTV logo, 16:9) until the first video picture.
  Widget _startPicture(AppState s) => LayoutBuilder(
        builder: (context, box) => Stack(fit: StackFit.expand, children: [
          Image.asset('assets/tv_background.jpg', fit: BoxFit.cover),
          // The hint would cover the logo on small screens.
          if (s.current == null && box.maxWidth >= 560)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.channels.isEmpty
                        ? 'Press "Update" on the remote to search for channels.'
                        : 'Pick a channel from the list or zap with the remote.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
        ]),
      );

  Widget _error(AppState s) {
    final c = s.current!;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.signal_wifi_bad, color: Colors.white70, size: 40),
          const SizedBox(height: 8),
          const Text('No signal',
              style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            c.needsVpn
                ? 'This channel is probably geo-blocked.\n'
                    'Connect a VPN to ${s.countryName(c.countryCode)} and try again.'
                : 'The channel is offline right now or not reachable.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ]),
      ),
    );
  }

  Widget _osdBox(AppState s) {
    final c = s.current!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('P ${s.currentIndex + 1}  ',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7CFFB2))),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(c.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              FlagIcon(c.countryCode, width: 22),
              const SizedBox(width: 8),
              Text(s.countryName(c.countryCode)),
              if (s.aspectLabel != null) ...[
                const SizedBox(width: 10),
                Text(s.aspectLabel!,
                    style: const TextStyle(color: Colors.white70)),
              ],
              if (c.needsVpn) ...[
                const SizedBox(width: 10),
                const VpnBadge(),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}
