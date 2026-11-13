import 'package:flutter/material.dart';

import '../app_state.dart';
import '../channel_scanner.dart';
import '../models.dart';
import 'flag.dart';
import 'scan_dialog.dart';

/// Display names of the category filters.
const kCategoryLabels = {
  'movies': 'Movies',
  'series': 'Series',
  'documentary': 'Docu',
  'music': 'Music',
  'news': 'News',
};

const kCategoryIcons = {
  'movies': Icons.movie_outlined,
  'series': Icons.video_library_outlined,
  'documentary': Icons.public_outlined,
  'music': Icons.music_note_outlined,
  'news': Icons.newspaper_outlined,
};

/// Left panel: all channels, grouped by country (flag + name),
/// with VPN filter and category filter.
class ChannelList extends StatefulWidget {
  const ChannelList({super.key, required this.state, this.onPicked});

  final AppState state;

  /// Called after a channel was tapped (used to close the drawer on phones).
  final VoidCallback? onPicked;

  @override
  State<ChannelList> createState() => _ChannelListState();
}

class _Row {
  _Row.header(this.group) : channel = null;
  _Row.channel(this.group, this.channel);
  final CountryGroup group;
  final Channel? channel;
}

class _ChannelListState extends State<ChannelList> {
  final _expanded = <String>{};
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _lastUrl;
  final _ctrl = ScrollController();
  static const _rowHeight = 40.0;

  @override
  void initState() {
    super.initState();
    final last = widget.state.lastCountry;
    if (last != null) _expanded.add(last);
    final cur = widget.state.current;
    if (cur != null) {
      _expanded.add(cur.countryCode);
      _lastUrl = cur.url;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _center(false));
  }

  /// Moves the playing channel (or the last selected country) to the middle.
  void _center(bool animate) {
    if (!_ctrl.hasClients) return;
    final rows = _rows;
    final url = widget.state.current?.url;
    var i = url == null ? -1 : rows.indexWhere((r) => r.channel?.url == url);
    if (i < 0) {
      final last = widget.state.lastCountry;
      i = rows.indexWhere((r) => r.channel == null && r.group.code == last);
    }
    if (i < 0) return;
    final pos = _ctrl.position;
    final target = (i * _rowHeight + _rowHeight / 2 - pos.viewportDimension / 2)
        .clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _ctrl.animateTo(target,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _ctrl.jumpTo(target);
    }
  }

  // Cache, so the list is not rebuilt on every player event.
  List<CountryGroup>? _cachedGroups;
  String _cachedKey = '';
  List<_Row> _rows = [];

  @override
  void dispose() {
    _ctrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_Row> _buildRows() {
    final groups = widget.state.groups;
    final key = '$_search|${_expanded.join(',')}';
    if (identical(groups, _cachedGroups) && key == _cachedKey) return _rows;
    _cachedGroups = groups;
    _cachedKey = key;

    final q = _search.trim().toLowerCase();
    final rows = <_Row>[];
    for (final g in groups) {
      final countryHit = q.isNotEmpty && g.name.toLowerCase().contains(q);
      final list = (q.isEmpty || countryHit)
          ? g.channels
          : g.channels.where((c) => c.name.toLowerCase().contains(q)).toList();
      if (list.isEmpty) continue;
      final shown = CountryGroup(g.code, g.name, list);
      rows.add(_Row.header(shown));
      // While searching, every country with hits is open.
      if (q.isNotEmpty || _expanded.contains(g.code)) {
        for (final c in list) {
          rows.add(_Row.channel(shown, c));
        }
      }
    }
    _rows = rows;
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final theme = Theme.of(context);
    // When zapping into another country, open that country.
    final cur = s.current;
    if (cur != null && cur.url != _lastUrl) {
      _lastUrl = cur.url;
      _expanded.add(cur.countryCode);
      WidgetsBinding.instance.addPostFrameCallback((_) => _center(true));
    }
    final rows = _buildRows();
    final currentUrl = cur?.url;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(children: [
        // ---- search ----
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search channel or country',
              border: const OutlineInputBorder(),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _searchCtrl.clear();
                        _search = '';
                      }),
                    ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),

        // ---- VPN filter ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<VpnFilter>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: VpnFilter.all, label: Text('All')),
                ButtonSegment(
                    value: VpnFilter.noVpn,
                    label: Text('No VPN'),
                    tooltip: 'Hide channels that need a VPN'),
                ButtonSegment(
                    value: VpnFilter.vpnOnly,
                    label: Text('VPN only'),
                    tooltip: 'Only channels that need a VPN'),
              ],
              selected: {s.vpnFilter},
              onSelectionChanged: (v) => s.setVpnFilter(v.first),
            ),
          ),
        ),

        // ---- categories ----
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            ChoiceChip(
              label: const Text('All'),
              visualDensity: VisualDensity.compact,
              selected: s.category == null,
              onSelected: (_) => s.setCategory(null),
            ),
            for (final c in kCategories)
              ChoiceChip(
                avatar: Icon(kCategoryIcons[c], size: 16),
                label: Text(kCategoryLabels[c]!),
                visualDensity: VisualDensity.compact,
                selected: s.category == c,
                onSelected: (sel) => s.setCategory(sel ? c : null),
              ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(children: [
            Expanded(
              child: Text(
                '${s.visible.length} of ${s.channels.length} channels · '
                '${s.groups.length} countries',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),

        // ---- running search / test ----
        if (s.jobRunning) _JobBar(state: s),

        const Divider(height: 10),
        Expanded(
          child: s.loading
              ? const Center(child: CircularProgressIndicator())
              : s.channels.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No channels yet.\nPress "Update" on the remote '
                          'control to start the channel search.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : rows.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No channels match this filter.',
                                textAlign: TextAlign.center),
                          ),
                        )
                      : ListView.builder(
                          controller: _ctrl,
                          itemExtent: _rowHeight,
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            if (r.channel == null) {
                              return _header(r.group, theme);
                            }
                            return _channelTile(r.channel!, r.group,
                                r.channel!.url == currentUrl, theme);
                          },
                        ),
        ),
      ]),
    );
  }

  Widget _header(CountryGroup g, ThemeData theme) {
    final open = _search.isNotEmpty || _expanded.contains(g.code);
    return InkWell(
      onTap: () => setState(() {
        if (!_expanded.remove(g.code)) {
          _expanded.add(g.code);
          widget.state.setLastCountry(g.code);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          FlagIcon(g.code, width: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(g.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
          ),
          Text('${g.channels.length}', style: theme.textTheme.bodySmall),
          Icon(open ? Icons.expand_less : Icons.expand_more, size: 20),
        ]),
      ),
    );
  }

  Widget _channelTile(
      Channel c, CountryGroup g, bool selected, ThemeData theme) {
    return Material(
      color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.state.playChannel(c);
          widget.onPicked?.call();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(50, 6, 12, 6),
          child: Row(children: [
            Expanded(
              child: Text(c.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.bold : null)),
            ),
            for (final k in c.categories)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Tooltip(
                  message: kCategoryLabels[k] ?? k,
                  child: Icon(kCategoryIcons[k], size: 14),
                ),
              ),
            if (c.notAlways)
              const Tooltip(
                message: 'Not on air 24/7',
                child: Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.schedule, size: 14),
                ),
              ),
            if (c.needsVpn)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: VpnBadge(countryName: g.name),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Small progress bar while a channel search / test runs in the background.
/// Tap it to open the full progress window.
class _JobBar extends StatelessWidget {
  const _JobBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<ScanProgress?>(
      valueListenable: state.jobProgress,
      builder: (context, p, _) {
        final value =
            (p != null && p.total > 0) ? p.checked / p.total : null;
        final title = state.jobKind == JobKind.test
            ? 'Testing channels'
            : 'Channel search';
        return InkWell(
          onTap: () => showJobProgress(context, state),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.radar, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p == null || p.total == 0
                        ? '$title...'
                        : '$title: ${p.checked}/${p.total} · ${p.found} ok',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.open_in_full, size: 14),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                  value: value, borderRadius: BorderRadius.circular(3)),
            ]),
          ),
        );
      },
    );
  }
}
