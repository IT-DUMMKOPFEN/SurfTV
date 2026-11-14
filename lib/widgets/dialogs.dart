import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'epg_view.dart';
import 'flag.dart';

const appVersion = '0.7b';

/// Info window (also shown when the app starts).
/// [onUpdate] shows an "Update channel list" link at the bottom left.
Future<void> showInfo(BuildContext context, {VoidCallback? onUpdate}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child:
                  Image.asset('assets/icon/icon.png', width: 110, height: 110),
            ),
            const SizedBox(height: 12),
            Text('SlaxxTV', style: Theme.of(ctx).textTheme.headlineSmall),
            Text('Version $appVersion',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 10),
            const Text('Written by IT-Dummkopfen with the help of an AI.',
                textAlign: TextAlign.center),
            const SizedBox(height: 14),
            const Text(
              'Free internet TV from all over the world.\n\n'
              'Channel lists: iptv-org, Free-TV, Famelack and the FreetuxTV '
              'database. SlaxxTV only plays streams '
              'that are publicly available on the internet. The "VPN" hint '
              'means the broadcaster probably limits the stream to its own '
              'country.',
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (onUpdate != null)
          TextButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              onUpdate();
            },
            icon: const Icon(Icons.radar),
            label: const Text('Update channel list'),
          )
        else
          const SizedBox.shrink(),
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
            onPressed: () => showLicensePage(
              context: ctx,
              applicationName: 'SlaxxTV',
              applicationVersion: appVersion,
            ),
            child: const Text('Licenses'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ]),
      ],
    ),
  );
}

/// English help.
Future<void> showHelp(BuildContext context) {
  Widget h(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );
  Widget p(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t),
      );
  Widget key(String k, String what) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 130,
              child: Text(k,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(what)),
        ]),
      );

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.help_outline),
        SizedBox(width: 10),
        Text('SlaxxTV Help'),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              p('SlaxxTV plays free internet TV channels from all over the '
                  'world. Channels are sorted by country.'),
              h('Two interfaces'),
              p('Classic: channel list left, TV in the middle, remote '
                  'control right.'),
              p('TV like: looks like a modern TV. Switch with F1, with the '
                  'switch in the settings (gear) or with the button on the '
                  'remote control.'),
              h('TV like'),
              p('Live TV: the current channel with "Watch Live" (picture '
                  'fills the window) and "+ Favorite" (adds the channel to My '
                  'Channels). Below: My Channels and the categories. '
                  'Swipe the rows with the mouse or your finger.'),
              p('Update: read in the complete channel list again or test '
                  'your channels. After every update, channels with the same '
                  'stream address are removed automatically (clean up). '
                  'Channels in My Channels and on the keys 0-9 always stay.'),
              p('Discover: pick a country, then a channel.'),
              p('My Channels: your favorites. Remove with the x. Switch to '
                  '"Program guide" to see what is on - the guide is loaded '
                  'for the channels in My Channels only (source: epgshare01, '
                  'not available for every channel). Export / Import saves '
                  'your favorites to a file and loads them again, e.g. on '
                  'another device.'),
              p('Categories: Movies, Series, Docu, News and Music - pick a '
                  'category, then a country, then a channel.'),
              p('--own--: your own stream addresses, always on top of the '
                  'list. Add, edit or delete them in the settings or with the '
                  'edit button next to --own--.'),
              p('Magnifier: search channels by name. Gear: settings. '
                  'Arrow on the left: channel list. Arrow on the right: '
                  'remote control.'),
              h('Remote control'),
              p('CH up/down zaps through the channels, VOL changes the '
                  'volume. Number keys 0-9: tap = switch to the stored '
                  'channel, hold = store the current channel on this key.'),
              h('VPN'),
              p('Channels with the orange VPN badge are probably '
                  'geo-blocked. You need a VPN into the country of the '
                  'channel. Use the filter All / No VPN / VPN only.'),
              h('Update and Test'),
              p('Channel sources: iptv-org, Free-TV, Famelack and the '
                  'FreetuxTV database (WebTV, status working).'),
              p('Update downloads the newest channel lists and builds the '
                  'complete channel list again (all channels, not tested). '
                  'Test checks the channels in your list and removes streams '
                  'that do not answer. Quick: streams must answer fast. '
                  'Intensive: streams get more time. Both run in the '
                  'background - you can keep watching TV.'),
              h('Keyboard'),
              key('F1', 'Switch Classic / TV like'),
              key('F / F11', 'Fullscreen (whole monitor)'),
              key('Esc', 'Leave fullscreen / Watch Live'),
              key('Up / Down', 'Next / previous channel'),
              key('+ / -', 'Volume'),
              key('M', 'Mute'),
              key('G', 'Program guide'),
              key('0 - 9', 'Stored channel'),
              key('Double-click', 'Picture: fullscreen on / off'),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Settings (gear button).
Future<void> showSettings(
  BuildContext context,
  AppState state, {
  required VoidCallback onUpdate,
  required VoidCallback onTest,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: state,
      builder: (ctx, _) {
        final updated = state.listUpdated;
        return AlertDialog(
          title: const Row(children: [
            Icon(Icons.settings),
            SizedBox(width: 10),
            Text('Settings'),
          ]),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SwitchListTile(
                  secondary: const Icon(Icons.tv),
                  title: const Text('TV like interface'),
                  subtitle: const Text('Off = Classic (F1 switches)'),
                  value: state.uiMode == UiMode.tvLike,
                  onChanged: (v) =>
                      state.setUiMode(v ? UiMode.tvLike : UiMode.classic),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode),
                  title: const Text('Night mode'),
                  value: state.themeMode == ThemeMode.dark,
                  onChanged: (_) => state.toggleTheme(),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.vpn_lock),
                  title: const Text('Channels with VPN'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SegmentedButton<VpnFilter>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: VpnFilter.all, label: Text('All')),
                        ButtonSegment(
                            value: VpnFilter.noVpn, label: Text('No VPN')),
                        ButtonSegment(
                            value: VpnFilter.vpnOnly, label: Text('VPN only')),
                      ],
                      selected: {state.vpnFilter},
                      onSelectionChanged: (v) => state.setVpnFilter(v.first),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: Text('${state.channels.length} channels'),
                  subtitle: Text(updated == null
                      ? 'No channel list yet'
                      : 'List from ${updated.toLocal().toString().substring(0, 16)}'),
                ),
                ListTile(
                  leading: const Icon(Icons.radar),
                  title: const Text('Update channel list'),
                  subtitle: const Text('Read in the complete newest lists'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onUpdate();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Test my channels'),
                  subtitle: const Text('Remove streams that do not answer'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onTest();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Image.asset('assets/own.png', width: 24),
                  title: const Text('--own-- feeds'),
                  subtitle: Text('${state.ownFeeds.length} own stream addresses'),
                  onTap: () => showOwnFeeds(ctx, state),
                ),
                ListTile(
                  leading: const Icon(Icons.event_note),
                  title: const Text('Program guide (My Channels)'),
                  subtitle: Text(state.epgLoading
                      ? (state.epgStatus ?? 'Loading...')
                      : '${state.epg.length} channels with guide data'),
                  onTap: () => showGuide(ctx, state),
                ),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Export favorites'),
                  subtitle: const Text('My Channels and keys 0-9 to a file'),
                  onTap: () => exportFavoritesFile(ctx, state),
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Import favorites'),
                  subtitle: const Text('Add favorites from a file'),
                  onTap: () => importFavoritesFile(ctx, state),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help'),
                  onTap: () => showHelp(ctx),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Info'),
                  onTap: () => showInfo(ctx),
                ),
              ]),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
}

/// Search channels by name (magnifier button).
Future<void> showNameSearch(BuildContext context, AppState state) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _NameSearch(state: state),
  );
}

class _NameSearch extends StatefulWidget {
  const _NameSearch({required this.state});
  final AppState state;

  @override
  State<_NameSearch> createState() => _NameSearchState();
}

class _NameSearchState extends State<_NameSearch> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final q = _q.trim().toLowerCase();
    final List<Channel> hits = q.isEmpty
        ? const []
        : s.visibleAll
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                s.countryName(c.countryCode).toLowerCase().contains(q))
            .take(300)
            .toList();
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Channel or country name',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Flexible(
            child: q.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Type a name to search all channels.'),
                  )
                : hits.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nothing found.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: hits.length,
                        itemBuilder: (ctx, i) {
                          final c = hits[i];
                          return ListTile(
                            leading: FlagIcon(c.countryCode, width: 32),
                            title: Text(c.name,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(s.countryName(c.countryCode)),
                            trailing: c.needsVpn ? const VpnBadge() : null,
                            onTap: () {
                              s.playChannel(c);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

/// --own--: the user's own stream addresses.
Future<void> showOwnFeeds(BuildContext context, AppState state) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _OwnFeeds(state: state),
  );
}

class _OwnFeeds extends StatefulWidget {
  const _OwnFeeds({required this.state});
  final AppState state;

  @override
  State<_OwnFeeds> createState() => _OwnFeedsState();
}

class _OwnFeedsState extends State<_OwnFeeds> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  int? _editing;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _save() {
    final url = _url.text.trim();
    final ok = RegExp(r'^(https?|rtmp|rtsp|mms|udp)://', caseSensitive: false)
        .hasMatch(url);
    if (!ok) {
      setState(() => _error = 'Please enter a stream address (http://... or https://...).');
      return;
    }
    final s = widget.state;
    if (_editing == null) {
      s.addOwnFeed(_name.text, url);
    } else {
      s.updateOwnFeed(_editing!, _name.text, url);
    }
    setState(() {
      _editing = null;
      _error = null;
      _name.clear();
      _url.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => AlertDialog(
        title: Row(children: [
          Image.asset('assets/own.png', width: 28, height: 28),
          const SizedBox(width: 10),
          const Text('--own-- feeds'),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your own stream addresses. They are always on top '
                    'of the channel list and stay after every update.'),
                const SizedBox(height: 10),
                if (s.ownFeeds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No own feeds yet.'),
                  ),
                for (var i = 0; i < s.ownFeeds.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Image.asset('assets/own.png', width: 26),
                    title: Text(s.ownFeeds[i].name,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.ownFeeds[i].url,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Watch',
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => s.playChannel(s.ownFeeds[i]),
                      ),
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit),
                        onPressed: () => setState(() {
                          _editing = i;
                          _name.text = s.ownFeeds[i].name;
                          _url.text = s.ownFeeds[i].url;
                        }),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => s.removeOwnFeed(i),
                      ),
                    ]),
                  ),
                const Divider(),
                Text(_editing == null ? 'Add a feed' : 'Edit feed',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _url,
                  decoration: InputDecoration(
                    labelText: 'Stream address (m3u8, mp4, ...)',
                    hintText: 'https://.../master.m3u8',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton.icon(
                    onPressed: _save,
                    icon: Icon(_editing == null ? Icons.add : Icons.save),
                    label: Text(_editing == null ? 'Add' : 'Save'),
                  ),
                  if (_editing != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() {
                        _editing = null;
                        _name.clear();
                        _url.clear();
                      }),
                      child: const Text('Cancel'),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
