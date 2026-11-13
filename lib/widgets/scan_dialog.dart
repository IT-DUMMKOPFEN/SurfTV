import 'package:flutter/material.dart';

import '../app_state.dart';
import '../channel_scanner.dart';
import 'flag.dart';

Future<void> showScanDialog(BuildContext context, AppState state) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ScanDialog(state: state),
  );
}

/// Channel search, styled like the channel search of a real TV.
class ScanDialog extends StatefulWidget {
  const ScanDialog({super.key, required this.state});
  final AppState state;

  @override
  State<ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<ScanDialog> {
  final _scanner = ChannelScanner();
  ScanProgress _p = const ScanProgress();
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final db = await _scanner.run((p) {
        if (mounted) setState(() => _p = p);
      });
      if (db.channels.isNotEmpty) {
        // Stopped early: add to the old list instead of replacing it.
        await widget.state.applyScan(db, merge: _scanner.cancelled);
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _scanner.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const lcd = Color(0xFF7CFFB2);
    final s = widget.state;
    final checking = _p.phase != ScanPhase.downloading;
    final progress = (_p.total > 0) ? _p.checked / _p.total : null;

    return Dialog(
      backgroundColor: const Color(0xFF0E1116),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Row(children: [
                Icon(Icons.radar, color: lcd),
                SizedBox(width: 10),
                Text('Channel search',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_error ?? _p.message,
                    style: TextStyle(
                        color: _error != null ? Colors.redAccent : Colors.white70)),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _done ? 1 : (checking ? progress : null),
                minHeight: 10,
                color: lcd,
                backgroundColor: Colors.white12,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  checking
                      ? 'Checked ${_p.checked} of ${_p.total} streams'
                          '${progress != null ? '  (${(progress * 100).toStringAsFixed(0)} %)' : ''}'
                      : '',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _counter('${_p.found}', 'channels found', lcd),
                  _counter('${_p.vpn}', 'need VPN', const Color(0xFFFFB74D)),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 230,
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _p.recent.isEmpty
                    ? const Center(
                        child: Text('Waiting for channels...',
                            style: TextStyle(color: Colors.white38)))
                    : ListView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (final c in _p.recent)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(children: [
                                FlagIcon(c.countryCode, width: 24),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(c.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 140),
                                  child: Text(
                                      _scanner.countryNames[c.countryCode] ??
                                          s.countryName(c.countryCode),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white60)),
                                ),
                                if (c.needsVpn) ...[
                                  const SizedBox(width: 6),
                                  const VpnBadge(),
                                ],
                              ]),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: _done
                    ? FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      )
                    : OutlinedButton.icon(
                        onPressed: () {
                          _scanner.cancel();
                          setState(() {});
                        },
                        icon: const Icon(Icons.stop),
                        label: Text(_scanner.cancelled
                            ? 'Stopping...'
                            : 'Stop (keep found channels)'),
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _counter(String value, String label, Color color) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 40, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]);
}
