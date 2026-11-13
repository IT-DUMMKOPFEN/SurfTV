import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'flag.dart';

/// Left panel: all channels, grouped by country (flag + name).
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
  bool _vpnFreeOnly = false;
  String? _lastUrl;

  // Cache, so the list is not rebuilt on every player event.
  List<CountryGroup>? _cachedGroups;
  String _cachedKey = '';
  List<_Row> _rows = [];

  @override
  void initState() {
    super.initState();
    final c = widget.state.current;
    if (c != null) _expanded.add(c.countryCode);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_Row> _buildRows() {
    final groups = widget.state.groups;
    final key = '$_search|$_vpnFreeOnly|${_expanded.join(',')}';
    if (identical(groups, _cachedGroups) && key == _cachedKey) return _rows;
    _cachedGroups = groups;
    _cachedKey = key;

    final q = _search.trim().toLowerCase();
    final rows = <_Row>[];
    for (final g in groups) {
      final countryHit = q.isNotEmpty && g.name.toLowerCase().contains(q);
      final list = g.channels.where((c) {
        if (_vpnFreeOnly && c.needsVpn) return false;
        if (q.isEmpty || countryHit) return true;
        return c.name.toLowerCase().contains(q);
      }).toList();
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
    }
    final rows = _buildRows();
    final currentUrl = s.current?.url;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Text('${s.channels.length} channels · ${s.groups.length} countries',
                style: theme.textTheme.bodySmall),
            const Spacer(),
            FilterChip(
              label: const Text('No VPN'),
              visualDensity: VisualDensity.compact,
              selected: _vpnFreeOnly,
              onSelected: (v) => setState(() => _vpnFreeOnly = v),
            ),
          ]),
        ),
        const Divider(height: 8),
        Expanded(
          child: s.channels.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No channels yet.\nPress "Update" on the remote control '
                      'to start the channel search.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    if (r.channel == null) return _header(r.group, theme);
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
        if (!_expanded.remove(g.code)) _expanded.add(g.code);
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
