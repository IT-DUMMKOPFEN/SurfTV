import 'package:flutter/material.dart';

import '../app_state.dart';
import 'dialogs.dart';
import 'flag.dart';

/// Right panel: a symbolic TV remote control.
///
/// Number keys: tap = switch to the stored channel,
/// hold = store the current channel on this key.
class RemoteControl extends StatelessWidget {
  const RemoteControl({
    super.key,
    required this.state,
    required this.onUpdate,
    required this.onTest,
    required this.onAbout,
    required this.onSwitchUi,
  });

  final AppState state;
  final VoidCallback onUpdate;
  final VoidCallback onTest;
  final VoidCallback onSwitchUi;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = state;

    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF353A42), Color(0xFF17191D)]
              : const [Color(0xFFF2F4F7), Color(0xFFC7CCD4)],
        ),
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          BoxShadow(blurRadius: 14, color: Colors.black38, offset: Offset(0, 6)),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('SurfTV',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: dark ? Colors.white70 : Colors.black54)),
            const Spacer(),
            // Switch Classic <-> TV like (F1 on the keyboard).
            Text('TV like',
                style: TextStyle(
                    fontSize: 12,
                    color: dark ? Colors.white70 : Colors.black54)),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: s.uiMode == UiMode.tvLike,
                onChanged: (_) => onSwitchUi(),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _Display(state: s),
          const SizedBox(height: 14),

          // Mute / day-night / fullscreen
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _RoundKey(
              icon: s.muted ? Icons.volume_off : Icons.volume_up,
              tooltip: s.muted ? 'Unmute (M)' : 'Mute (M)',
              color: s.muted ? const Color(0xFFE53935) : null,
              onTap: s.toggleMute,
            ),
            _RoundKey(
              icon: dark ? Icons.light_mode : Icons.dark_mode,
              tooltip: dark ? 'Day mode' : 'Night mode',
              onTap: s.toggleTheme,
            ),
            _RoundKey(
              icon: Icons.fullscreen,
              tooltip: 'Fullscreen (F)',
              onTap: s.toggleFullscreen,
            ),
          ]),
          const SizedBox(height: 14),

          // CH and VOL rockers
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _Rocker(
              label: 'CH',
              upIcon: Icons.keyboard_arrow_up,
              downIcon: Icons.keyboard_arrow_down,
              upTooltip: 'Next channel (↑)',
              downTooltip: 'Previous channel (↓)',
              onUp: s.nextChannel,
              onDown: s.previousChannel,
            ),
            _Rocker(
              label: 'VOL',
              upIcon: Icons.add,
              downIcon: Icons.remove,
              upTooltip: 'Louder (+)',
              downTooltip: 'Quieter (-)',
              onUp: () => s.volumeStep(5),
              onDown: () => s.volumeStep(-5),
            ),
          ]),
          Row(children: [
            Icon(Icons.volume_down,
                size: 18, color: dark ? Colors.white54 : Colors.black45),
            Expanded(
              child: Slider(
                value: s.volume,
                min: 0,
                max: 100,
                onChanged: s.setVolume,
              ),
            ),
            SizedBox(
              width: 30,
              child: Text(s.muted ? '--' : s.volume.round().toString(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 6),

          // Number pad 1-9, 0
          _NumberPad(state: s),
          const SizedBox(height: 6),
          Text('Tap = recall · Hold = store',
              style: TextStyle(
                  fontSize: 11,
                  color: dark ? Colors.white54 : Colors.black54)),
          const SizedBox(height: 14),

          Row(children: [
            Expanded(
              child: Tooltip(
                message: 'Download and test the newest channel lists',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: onUpdate,
                  icon: const Icon(Icons.radar, size: 18),
                  label: const Text('Update'),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Tooltip(
                message: 'Test my channels, remove streams that do not answer',
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: onTest,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Test'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Wrap(alignment: WrapAlignment.center, children: [
            Tooltip(
              message: 'Switch Classic / TV like (F1)',
              child: TextButton.icon(
                onPressed: onSwitchUi,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text(state.uiMode == UiMode.tvLike
                    ? 'Classic'
                    : 'TV like'),
              ),
            ),
            IconButton(
              tooltip: 'Help',
              onPressed: () => showHelp(context),
              icon: const Icon(Icons.help_outline, size: 20),
            ),
            IconButton(
              tooltip: 'About SurfTV',
              onPressed: onAbout,
              icon: const Icon(Icons.info_outline, size: 20),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// LCD-style display at the top of the remote.
class _Display extends StatelessWidget {
  const _Display({required this.state});
  final AppState state;

  static const _lcd = Color(0xFF7CFFB2);

  @override
  Widget build(BuildContext context) {
    final c = state.current;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1712),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
            color: _lcd, fontFamily: 'monospace', fontSize: 13),
        child: c == null
            ? const Center(child: Text('NO SIGNAL', style: TextStyle(fontSize: 16)))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('P${(state.currentIndex + 1).toString().padLeft(4, '0')}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (state.aspectLabel != null) Text(state.aspectLabel!),
                  if (c.quality != null) Text('  ${c.quality}'),
                ]),
                const SizedBox(height: 4),
                Text(c.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  FlagIcon(c.countryCode, width: 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(state.countryName(c.countryCode),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                if (c.needsVpn) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.vpn_lock, size: 15, color: Color(0xFFFFB74D)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'VPN to ${state.countryName(c.countryCode)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFFFB74D)),
                      ),
                    ),
                  ]),
                ],
              ]),
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    Widget key(int n) => _NumberKey(state: state, slot: n);
    return Column(children: [
      for (final row in const [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
      ])
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (final n in row) key(n)],
        ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [key(0)]),
    ]);
  }
}

class _NumberKey extends StatelessWidget {
  const _NumberKey({required this.state, required this.slot});
  final AppState state;
  final int slot;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stored = state.favoriteChannel(slot);
    final messenger = ScaffoldMessenger.maybeOf(context);

    void show(String text) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
          content: Text(text), duration: const Duration(seconds: 2)));
    }

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Tooltip(
        message: stored == null
            ? 'Key $slot is empty - hold to store the current channel'
            : '$slot: ${stored.name} (${state.countryName(stored.countryCode)})',
        child: Material(
          color: dark ? const Color(0xFF4A505A) : Colors.white,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              if (!state.recallFavorite(slot)) {
                show('Key $slot is empty. Hold the key to store the current channel.');
              }
            },
            onLongPress: () {
              if (state.storeFavorite(slot)) {
                show('Stored "${state.current!.name}" on key $slot');
              } else {
                show('Play a channel first, then hold the key to store it.');
              }
            },
            child: SizedBox(
              width: 50,
              height: 50,
              child: Stack(alignment: Alignment.center, children: [
                Text('$slot',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                if (stored != null)
                  const Positioned(
                    bottom: 6,
                    child: CircleAvatar(
                        radius: 3, backgroundColor: Color(0xFF7CFFB2)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundKey extends StatelessWidget {
  const _RoundKey({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color ?? (dark ? const Color(0xFF4A505A) : Colors.white),
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 46, height: 46, child: Icon(icon)),
        ),
      ),
    );
  }
}

/// Long CH / VOL key with up and down half.
class _Rocker extends StatelessWidget {
  const _Rocker({
    required this.label,
    required this.upIcon,
    required this.downIcon,
    required this.upTooltip,
    required this.downTooltip,
    required this.onUp,
    required this.onDown,
  });

  final String label;
  final IconData upIcon, downIcon;
  final String upTooltip, downTooltip;
  final VoidCallback onUp, onDown;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
    return Material(
      color: dark ? const Color(0xFF4A505A) : Colors.white,
      shape: shape,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 64,
        child: Column(children: [
          Tooltip(
            message: upTooltip,
            child: InkWell(
              onTap: onUp,
              child: SizedBox(height: 44, width: 64, child: Icon(upIcon)),
            ),
          ),
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          Tooltip(
            message: downTooltip,
            child: InkWell(
              onTap: onDown,
              child: SizedBox(height: 44, width: 64, child: Icon(downIcon)),
            ),
          ),
        ]),
      ),
    );
  }
}
