import 'package:flutter/material.dart';

import '../app_state.dart';
import '../channel_scanner.dart';
import 'flag.dart';

const _lcd = Color(0xFF7CFFB2);

/// Asks what to do (update list / test channels, quick / intensive),
/// then starts the job in the background and shows its progress.
Future<void> showJobStart(BuildContext context, AppState state,
    {JobKind initial = JobKind.update}) async {
  if (state.jobRunning) {
    return showJobProgress(context, state);
  }
  final choice = await showDialog<(JobKind, TestMode)>(
    context: context,
    builder: (_) => _StartDialog(initial: initial, hasChannels: state.channels.isNotEmpty),
  );
  if (choice == null || !context.mounted) return;
  state.startJob(choice.$1, choice.$2);
  return showJobProgress(context, state);
}

class _StartDialog extends StatefulWidget {
  const _StartDialog({required this.initial, required this.hasChannels});
  final JobKind initial;
  final bool hasChannels;

  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  late JobKind _kind =
      widget.hasChannels ? widget.initial : JobKind.update;
  TestMode _mode = TestMode.quick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.radar),
        SizedBox(width: 10),
        Text('Channels'),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioListTile<JobKind>(
              value: JobKind.update,
              groupValue: _kind,
              onChanged: (v) => setState(() => _kind = v!),
              title: const Text('Update channel list'),
              subtitle: const Text(
                  'Download the newest lists from the internet and test every stream.'),
            ),
            RadioListTile<JobKind>(
              value: JobKind.test,
              groupValue: _kind,
              onChanged: widget.hasChannels
                  ? (v) => setState(() => _kind = v!)
                  : null,
              title: const Text('Test my channels'),
              subtitle: const Text(
                  'Test the channels in your list. Streams that do not answer are removed.'),
            ),
            const SizedBox(height: 12),
            Text('Test', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<TestMode>(
                segments: const [
                  ButtonSegment(
                      value: TestMode.quick,
                      icon: Icon(Icons.bolt),
                      label: Text('Quick')),
                  ButtonSegment(
                      value: TestMode.intensive,
                      icon: Icon(Icons.hourglass_bottom),
                      label: Text('Intensive')),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _mode == TestMode.quick
                  ? 'Streams must answer within a few seconds. Fast, '
                      'but slow servers are removed too.'
                  : 'Streams get up to 15 seconds to answer. Takes longer, '
                      'keeps slow but working channels.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text('You can keep watching TV while this runs.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, (_kind, _mode)),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      ],
    );
  }
}

/// Progress window, styled like the channel search of a real TV.
/// "Hide" closes it - the job keeps running and TV keeps playing.
Future<void> showJobProgress(BuildContext context, AppState state) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (_) => _ProgressDialog(state: state),
  );
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xEE0E1116),
      alignment: Alignment.bottomCenter,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: JobProgressPanel(
            state: state,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

/// Live view of the running channel search / test (also used on the
/// "Search" page of the TV like interface).
class JobProgressPanel extends StatelessWidget {
  const JobProgressPanel({super.key, required this.state, this.onClose});
  final AppState state;

  /// "Hide" / "Done" button. Not shown when null.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([state, state.jobProgress]),
      builder: (context, _) {
        final p = state.jobProgress.value ?? const ScanProgress();
        final running = state.jobRunning;
        final checking = p.phase != ScanPhase.downloading;
        final progress = (p.total > 0) ? p.checked / p.total : null;
        final isTest = state.jobKind == JobKind.test;
        final modeText =
            state.jobMode == TestMode.quick ? 'Quick test' : 'Intensive test';

        return DefaultTextStyle(
                style: const TextStyle(color: Colors.white),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Icon(Icons.radar, color: _lcd),
                    const SizedBox(width: 10),
                    Text(isTest ? 'Channel test' : 'Channel search',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(modeText,
                        style: const TextStyle(color: Colors.white54)),
                  ]),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(state.jobError ?? p.message,
                        style: TextStyle(
                            color: state.jobError != null
                                ? Colors.redAccent
                                : Colors.white70)),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: !running ? 1 : (checking ? progress : null),
                    minHeight: 10,
                    color: _lcd,
                    backgroundColor: Colors.white12,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      checking && p.total > 0
                          ? 'Checked ${p.checked} of ${p.total} streams  '
                              '(${(progress! * 100).toStringAsFixed(0)} %)'
                          : '',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _counter('${p.found}', 'working', _lcd),
                      _counter('${p.vpn}', 'need VPN', const Color(0xFFFFB74D)),
                      _counter('${p.dead}', 'removed', const Color(0xFFEF5350)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 200,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: p.recent.isEmpty
                        ? const Center(
                            child: Text('Waiting for channels...',
                                style: TextStyle(color: Colors.white38)))
                        : ListView(
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              for (final c in p.recent)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 3),
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
                                          const BoxConstraints(maxWidth: 150),
                                      child: Text(
                                          state.countryName(c.countryCode),
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
                  const SizedBox(height: 14),
                  Row(children: [
                    if (running)
                      OutlinedButton.icon(
                        onPressed: state.jobStopping ? null : state.stopJob,
                        icon: const Icon(Icons.stop),
                        label: Text(state.jobStopping
                            ? 'Stopping...'
                            : 'Stop (keep results)'),
                      ),
                    const Spacer(),
                    if (onClose != null)
                      FilledButton(
                        onPressed: onClose,
                        child: Text(running ? 'Hide' : 'Done'),
                      ),
                  ]),
                ]),
        );
      },
    );
  }

  Widget _counter(String value, String label, Color color) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 34, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]);
}
