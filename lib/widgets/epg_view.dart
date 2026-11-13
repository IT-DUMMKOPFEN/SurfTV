import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../epg.dart';
import '../models.dart';
import 'flag.dart';
import 'tiles.dart';

String hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Program guide for My Channels: one row per channel, programmes as
/// swipeable cards, the programme running now in the middle.
class EpgGuide extends StatelessWidget {
  const EpgGuide({super.key, required this.state, this.shrink = false});

  final AppState state;

  /// Inside a page that scrolls as a whole.
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final my = s.myChannelList;
    final theme = Theme.of(context);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (s.epgLoading)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          Text(
            s.epgLoading
                ? (s.epgStatus ?? 'Loading program guide...')
                : s.epgFetched == null
                    ? 'No program guide loaded yet.'
                    : 'Guide from ${hm(s.epgFetched!)} · '
                        '${s.epg.length} of ${my.length} channels with data',
            style: theme.textTheme.bodyMedium,
          ),
          TextButton.icon(
            onPressed: s.epgLoading ? null : () => s.refreshEpg(force: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Update guide'),
          ),
        ],
      ),
    );

    if (my.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Add channels to My Channels to see their program guide.',
            style: theme.textTheme.bodyLarge),
      );
    }

    final rows = [
      for (final c in my) _ChannelGuideRow(state: s, channel: c),
    ];
    if (shrink) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, ...rows]);
    }
    return ListView(children: [header, ...rows, const SizedBox(height: 20)]);
  }
}

class _ChannelGuideRow extends StatelessWidget {
  const _ChannelGuideRow({required this.state, required this.channel});
  final AppState state;
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = channel;
    final list = s.programmesOf(c);
    final now = DateTime.now();
    final nowIndex = list.indexWhere((p) => p.isOn(now));
    final playing = s.current?.url == c.url;
    final theme = Theme.of(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
        child: Row(children: [
          FlagIcon(c.countryCode, width: 26),
          const SizedBox(width: 10),
          Flexible(
            child: Text(c.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: playing ? kAccent : null)),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Watch',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => s.playChannel(c),
          ),
        ]),
      ),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
          child: Text(
              s.epgLoading ? 'Loading...' : 'No program guide for this channel.',
              style: TextStyle(color: theme.hintColor)),
        )
      else
        SwipeRow(
          itemCount: list.length,
          itemWidth: 250,
          height: 96,
          centerIndex: nowIndex >= 0 ? nowIndex : 0,
          itemBuilder: (_, i) => _ProgrammeCard(
            programme: list[i],
            onTap: () => showProgramme(context, s, c, list[i]),
          ),
        ),
    ]);
  }
}

class _ProgrammeCard extends StatelessWidget {
  const _ProgrammeCard({required this.programme, required this.onTap});
  final Programme programme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = programme;
    final now = DateTime.now();
    final on = p.isOn(now);
    final past = p.stop.isBefore(now);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: on ? kAccent : Colors.transparent, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: past ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${hm(p.start)} – ${hm(p.stop)}${on ? '  ·  NOW' : ''}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: on ? kAccent : null)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(p.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  if (on)
                    LinearProgressIndicator(
                      value: p.progress(now),
                      borderRadius: BorderRadius.circular(2),
                    ),
                ]),
          ),
        ),
      ),
    );
  }
}

/// Details of one programme.
Future<void> showProgramme(
    BuildContext context, AppState s, Channel c, Programme p) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(p.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                FlagIcon(c.countryCode, width: 24),
                const SizedBox(width: 8),
                Flexible(child: Text(c.name)),
              ]),
              const SizedBox(height: 6),
              Text('${hm(p.start)} – ${hm(p.stop)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (p.desc != null && p.desc!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(p.desc!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            s.playChannel(c);
            Navigator.of(ctx).pop();
          },
          child: const Text('Watch channel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Program guide as a window (Classic interface, key G).
Future<void> showGuide(BuildContext context, AppState s) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
        child: ListenableBuilder(
          listenable: s,
          builder: (ctx, _) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
              child: Row(children: [
                const Icon(Icons.event_note),
                const SizedBox(width: 10),
                Text('Program guide · My Channels',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ]),
            ),
            Expanded(child: EpgGuide(state: s)),
          ]),
        ),
      ),
    ),
  );
}

/// "Now" line for tiles and displays.
Widget? nowLine(AppState s, Channel c, {TextStyle? style, int maxLines = 1}) {
  final p = s.nowOn(c);
  if (p == null) return null;
  return Text('▶ ${p.title}',
      maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
}

// =====================================================================
// Favorites export / import
// =====================================================================

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Saves My Channels and keys 0-9 to a JSON file.
Future<void> exportFavoritesFile(BuildContext context, AppState s) async {
  final bytes = Uint8List.fromList(utf8.encode(s.exportFavorites()));
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export favorites',
      fileName: 'surftv-favorites.json',
      bytes: bytes,
    );
    if (path == null) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(path).writeAsBytes(bytes);
    }
    if (context.mounted) {
      _snack(context, 'Favorites exported (${s.myChannels.length} channels).');
    }
  } catch (e) {
    if (context.mounted) _snack(context, 'Export failed: $e');
  }
}

/// Loads favorites from a JSON file and adds them.
Future<void> importFavoritesFile(BuildContext context, AppState s) async {
  try {
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import favorites',
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : const ['json'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final data = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (data == null) return;
    final added = await s.importFavorites(utf8.decode(data));
    if (context.mounted) {
      _snack(context, '$added channels added to My Channels.');
    }
  } on FormatException catch (e) {
    if (context.mounted) _snack(context, e.message);
  } catch (e) {
    if (context.mounted) _snack(context, 'Import failed: $e');
  }
}
