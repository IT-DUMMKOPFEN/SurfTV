import 'package:flutter/material.dart';

import '../app_state.dart';
import '../channel_scanner.dart';
import '../models.dart';
import 'channel_list.dart';
import 'dialogs.dart';
import 'flag.dart';
import 'scan_dialog.dart';
import 'tiles.dart';
import 'tv_screen.dart';

/// Tabs of the TV like interface.
class TvTab {
  static const live = 0, search = 1, discover = 2, my = 3, categories = 4;
}

/// "TV like" interface - looks and feels like a modern smart TV.
class TvLikeScreen extends StatefulWidget {
  const TvLikeScreen({
    super.key,
    required this.state,
    required this.remote,
    required this.onUpdate,
    required this.onTest,
  });

  final AppState state;

  /// The remote control (slides in from the right).
  final Widget remote;
  final VoidCallback onUpdate;
  final VoidCallback onTest;

  @override
  State<TvLikeScreen> createState() => _TvLikeScreenState();
}

class _TvLikeScreenState extends State<TvLikeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  AppState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: scheme.surface,
      drawer: Drawer(
        width: 330,
        child: SafeArea(
          child: ChannelList(
            state: s,
            onPicked: () => _scaffoldKey.currentState?.closeDrawer(),
          ),
        ),
      ),
      endDrawer: Drawer(
        width: 290,
        backgroundColor: scheme.surface,
        child: SafeArea(child: widget.remote),
      ),
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            _TopBar(
              state: s,
              onSettings: () => showSettings(context, s,
                  onUpdate: widget.onUpdate, onTest: widget.onTest),
            ),
            Expanded(child: _page()),
          ]),
          // Arrow left: channel list.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: _EdgeButton(
                icon: Icons.chevron_right,
                tooltip: 'Channel list',
                left: true,
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
              ),
            ),
          ),
          // Arrow right: remote control.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: _EdgeButton(
                icon: Icons.chevron_left,
                tooltip: 'Remote control',
                left: false,
                onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _page() {
    switch (s.tvTab) {
      case TvTab.search:
        return _SearchPage(state: s);
      case TvTab.discover:
        return _DiscoverPage(state: s);
      case TvTab.my:
        return _MyChannelsPage(state: s);
      case TvTab.categories:
        return _CategoriesPage(state: s);
      default:
        return _LivePage(state: s);
    }
  }
}

// =====================================================================
// Top bar
// =====================================================================

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, required this.onSettings});
  final AppState state;
  final VoidCallback onSettings;

  static const _nav = [
    ('Search', TvTab.search),
    ('Discover', TvTab.discover),
    ('Live TV', TvTab.live),
    ('My Channels', TvTab.my),
    ('Categories', TvTab.categories),
  ];

  @override
  Widget build(BuildContext context) {
    final s = state;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 1100;
      final logo = InkWell(
        onTap: () => s.setTvTab(TvTab.live),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                  fontSize: narrow ? 24 : 32, fontWeight: FontWeight.w900),
              children: [
                TextSpan(
                    text: 'Surf',
                    style: TextStyle(
                        color: dark ? Colors.white : Colors.black87)),
                const TextSpan(text: 'TV', style: TextStyle(color: kAccent)),
              ],
            ),
          ),
        ),
      );

      final nav = Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (label, tab) in _nav)
          TextButton(
            onPressed: () => s.setTvTab(tab),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 10 : 18, vertical: 8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: narrow ? 15 : 21,
                fontWeight:
                    s.tvTab == tab ? FontWeight.bold : FontWeight.w400,
                color: s.tvTab == tab
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
      ]);

      final volume = <Widget>[
        IconButton(
          tooltip: 'Quieter',
          icon: const Icon(Icons.volume_down),
          onPressed: () => s.volumeStep(-5),
        ),
        InkWell(
          onTap: s.toggleMute,
          child: Tooltip(
            message: s.muted ? 'Unmute' : 'Mute',
            child: SizedBox(
              width: 52,
              child: Text(
                s.muted ? 'Mute' : '${s.volume.round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: s.muted ? Colors.redAccent : null,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Louder',
          icon: const Icon(Icons.volume_up),
          onPressed: () => s.volumeStep(5),
        ),
        IconButton(
          tooltip: 'Fullscreen (F)',
          icon: const Icon(Icons.fullscreen),
          onPressed: () => s.setFullscreen(true),
        ),
      ];
      final tools = <Widget>[
        IconButton(
          tooltip: 'Search by name',
          icon: const Icon(Icons.search),
          onPressed: () => showNameSearch(context, s),
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings),
          onPressed: onSettings,
        ),
      ];
      final actions =
          Row(mainAxisSize: MainAxisSize.min, children: [...volume, ...tools]);
      final tiny = box.maxWidth < 640;

      return Container(
        color: scheme.surfaceContainer,
        padding: EdgeInsets.fromLTRB(narrow ? 10 : 40, 6, narrow ? 6 : 30, 6),
        child: tiny
            ? Column(children: [
                Row(children: [logo, const Spacer(), ...tools]),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [nav, const SizedBox(width: 8), ...volume]),
                ),
              ])
            : narrow
            ? Column(children: [
                Row(children: [logo, const Spacer(), actions]),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal, child: nav),
              ])
            : Row(children: [
                logo,
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal, child: nav),
                  ),
                ),
                actions,
              ]),
      );
    });
  }
}

class _EdgeButton extends StatelessWidget {
  const _EdgeButton({
    required this.icon,
    required this.tooltip,
    required this.left,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final bool left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = const Radius.circular(14);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black54,
        borderRadius: left
            ? BorderRadius.only(topRight: r, bottomRight: r)
            : BorderRadius.only(topLeft: r, bottomLeft: r),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 90,
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

Widget _title(BuildContext context, String text, {String? sub}) => Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(text,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        if (sub != null) ...[
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(sub, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ]),
    );

Widget _hint(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.all(28),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: Theme.of(context).hintColor)),
    );

/// Headers on top, grid below. On low screens (phones) the whole page
/// scrolls, so the grid gets enough room.
Widget _pageLayout(List<Widget> header, Widget Function(bool shrink) grid) =>
    LayoutBuilder(builder: (context, box) {
      if (box.maxHeight < 700) {
        return SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [...header, grid(true)]),
        );
      }
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [...header, Expanded(child: grid(false))]);
    });

const _categoryNames = {
  'movies': 'Movies',
  'series': 'Series',
  'documentary': 'Docs',
  'news': 'News',
};
const _categoryIcons = {
  'movies': Icons.movie_outlined,
  'series': Icons.video_library_outlined,
  'documentary': Icons.public_outlined,
  'news': Icons.newspaper_outlined,
};

// =====================================================================
// Live TV (home)
// =====================================================================

class _LivePage extends StatefulWidget {
  const _LivePage({required this.state});
  final AppState state;

  @override
  State<_LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<_LivePage> {
  final _scroll = ScrollController();
  final _catKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toCategories() {
    final ctx = _catKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final my = s.myChannelList;
    final curUrl = s.current?.url;

    return SingleChildScrollView(
      controller: _scroll,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Hero(state: s),
        _title(context, 'My Channels', sub: '${my.length}'),
        if (my.isEmpty)
          _hint(context,
              'No favorites yet. Press "+ Favorite" to add the channel you are watching.')
        else
          SwipeRow(
            itemCount: my.length,
            centerIndex: my.indexWhere((c) => c.url == curUrl),
            itemBuilder: (_, i) => ChannelTile(state: s, channel: my[i]),
          ),
        Center(
          child: IconButton(
            tooltip: 'Categories',
            iconSize: 40,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _toCategories,
          ),
        ),
        Container(key: _catKey),
        for (final cat in kCategories) _categoryRow(context, s, cat),
        const SizedBox(height: 30),
      ]),
    );
  }

  /// One category: channels of the last selected country first.
  Widget _categoryRow(BuildContext context, AppState s, String cat) {
    final all = s.visibleAll.where((c) => c.categories.contains(cat));
    final home = s.lastCountry;
    final list = <Channel>[
      ...all.where((c) => c.countryCode == home),
      ...all.where((c) => c.countryCode != home),
    ].take(40).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    final count = all.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 20, 0),
        child: Row(children: [
          Icon(_categoryIcons[cat]),
          const SizedBox(width: 8),
          Text(_categoryNames[cat]!,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text('$count', style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              s.setTvCategory(cat);
              s.setTvTab(TvTab.categories);
            },
            icon: const Icon(Icons.chevron_right),
            label: const Text('All countries'),
          ),
        ]),
      ),
      SwipeRow(
        itemCount: list.length,
        centerIndex: list.indexWhere((c) => c.url == s.current?.url),
        itemBuilder: (_, i) => ChannelTile(state: s, channel: list[i]),
      ),
    ]);
  }
}

/// Big area at the top: channel info left, picture right.
class _Hero extends StatelessWidget {
  const _Hero({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.current;
    final scheme = Theme.of(context).colorScheme;

    final info = Padding(
      padding: const EdgeInsets.fromLTRB(36, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c == null ? Colors.grey : kAccent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(c == null ? 'NO SIGNAL' : 'LIVE',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          const SizedBox(height: 12),
          Text(
            c?.name.toUpperCase() ?? 'SURFTV',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900, height: 1.05),
          ),
          const SizedBox(height: 12),
          Container(
            height: 4,
            width: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                  colors: [kAccent, Color(0x332E8BEA)]),
            ),
          ),
          const SizedBox(height: 14),
          if (c != null)
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FlagIcon(c.countryCode, width: 34),
                Text(s.countryName(c.countryCode),
                    style: Theme.of(context).textTheme.titleMedium),
                for (final k in c.categories)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(_categoryIcons[k], size: 16),
                    label: Text(_categoryNames[k] ?? k),
                  ),
                if (s.aspectLabel != null) Text(s.aspectLabel!),
                if (c.quality != null) Text(c.quality!),
                if (c.needsVpn) const VpnBadge(large: true),
              ],
            )
          else
            Text('Pick a channel below or in Discover.',
                style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 22),
          Wrap(spacing: 14, runSpacing: 10, children: [
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              onPressed: c == null ? null : () => s.setWatchLive(true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Watch Live'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  textStyle: const TextStyle(fontSize: 18)),
              onPressed: c == null ? null : () => s.toggleMyChannel(c),
              icon: Icon(c != null && s.isMyChannel(c)
                  ? Icons.check
                  : Icons.add),
              label: Text(c != null && s.isMyChannel(c)
                  ? 'In My Channels'
                  : 'Favorite'),
            ),
          ]),
        ],
      ),
    );

    final picture = Stack(fit: StackFit.expand, children: [
      TvScreen(state: s),
      // Soft fade from the info side into the picture, like on a TV.
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: 90,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                scheme.surfaceContainerLow,
                scheme.surfaceContainerLow.withValues(alpha: 0),
              ]),
            ),
          ),
        ),
      ),
    ]);

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 800) {
        return Container(
          color: scheme.surfaceContainerLow,
          child: Column(children: [
            AspectRatio(aspectRatio: 16 / 9, child: TvScreen(state: s)),
            info,
          ]),
        );
      }
      final h = (box.maxWidth * 0.36).clamp(320.0, 620.0);
      return Container(
        height: h,
        color: scheme.surfaceContainerLow,
        child: Row(children: [
          Expanded(flex: 4, child: info),
          Expanded(flex: 6, child: picture),
        ]),
      );
    });
  }
}

// =====================================================================
// Search = channel search (update / test)
// =====================================================================

class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.state});
  final AppState state;

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  TestMode _mode = TestMode.quick;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final showProgress = s.jobRunning || s.jobProgress.value != null;

    Widget card(IconData icon, String title, String text, JobKind kind) =>
        SizedBox(
          width: 330,
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: s.jobRunning ||
                      (kind == JobKind.test && s.channels.isEmpty)
                  ? null
                  : () => s.startJob(kind, _mode),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 40, color: kAccent),
                      const SizedBox(height: 10),
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(text),
                    ]),
              ),
            ),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, 'Channel search',
            sub: '${s.channels.length} channels in your list'),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<TestMode>(
                  segments: const [
                    ButtonSegment(
                        value: TestMode.quick,
                        icon: Icon(Icons.bolt),
                        label: Text('Quick test')),
                    ButtonSegment(
                        value: TestMode.intensive,
                        icon: Icon(Icons.hourglass_bottom),
                        label: Text('Intensive test')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() => _mode = v.first),
                ),
                const SizedBox(height: 6),
                Text(_mode == TestMode.quick
                    ? 'Streams must answer within a few seconds.'
                    : 'Streams get up to 15 seconds to answer.'),
                const SizedBox(height: 16),
                Wrap(spacing: 16, runSpacing: 16, children: [
                  card(
                      Icons.radar,
                      'Update channel list',
                      'Download the newest lists from the internet and test every stream.',
                      JobKind.update),
                  card(
                      Icons.fact_check_outlined,
                      'Test my channels',
                      'Test the channels in your list. Streams that do not answer are removed.',
                      JobKind.test),
                ]),
                const SizedBox(height: 8),
                const Text('You can keep watching TV while this runs.',
                    style: TextStyle(fontStyle: FontStyle.italic)),
                const SizedBox(height: 20),
                if (showProgress)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 680),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1116),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: JobProgressPanel(state: s),
                  ),
              ]),
        ),
      ]),
    );
  }
}

// =====================================================================
// Discover: countries, then channels
// =====================================================================

class _DiscoverPage extends StatelessWidget {
  const _DiscoverPage({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final countries = s.countriesWith();
    if (countries.isEmpty) {
      return _hint(context, 'No channels yet. Open "Search" to update the list.');
    }
    final country = countries.contains(s.lastCountry)
        ? s.lastCountry!
        : countries.first;
    final list = s.channelsOf(country);
    return _pageLayout([
      _title(context, 'Discover', sub: '${countries.length} countries'),
      _CountryRow(
        state: s,
        countries: countries,
        selected: country,
      ),
      _title(context, s.countryName(country), sub: '${list.length} channels'),
    ], (shrink) => TileGrid(
          shrink: shrink,
          itemCount: list.length,
          centerIndex: list.indexWhere((c) => c.url == s.current?.url),
          itemBuilder: (_, i) => ChannelTile(state: s, channel: list[i]),
        ));
  }
}

/// Swipeable row of country tiles; the selected country is in the middle.
class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.state,
    required this.countries,
    required this.selected,
    this.category,
  });

  final AppState state;
  final List<String> countries;
  final String selected;
  final String? category;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return SwipeRow(
      itemCount: countries.length,
      itemWidth: 150,
      height: 118,
      centerIndex: countries.indexOf(selected),
      itemBuilder: (_, i) {
        final code = countries[i];
        return CountryTile(
          code: code,
          name: s.countryName(code),
          count: s.channelsOf(code, category: category).length,
          selected: code == selected,
          onTap: () => s.setLastCountry(code),
        );
      },
    );
  }
}

// =====================================================================
// My Channels
// =====================================================================

class _MyChannelsPage extends StatelessWidget {
  const _MyChannelsPage({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final my = s.myChannelList;
    if (my.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, 'My Channels', sub: '0'),
        _hint(context,
            'No favorites yet. Watch a channel and press "+ Favorite" on Live TV.'),
      ]);
    }
    return _pageLayout([
      _title(context, 'My Channels', sub: '${my.length}'),
    ], (shrink) => TileGrid(
          shrink: shrink,
          itemCount: my.length,
          centerIndex: my.indexWhere((c) => c.url == s.current?.url),
          itemBuilder: (_, i) => ChannelTile(
            state: s,
            channel: my[i],
            onRemove: () => s.toggleMyChannel(my[i]),
          ),
        ));
  }
}

// =====================================================================
// Categories: category -> country -> channels
// =====================================================================

class _CategoriesPage extends StatelessWidget {
  const _CategoriesPage({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final cat = s.tvCategory;
    final countries = s.countriesWith(category: cat);
    final country = countries.contains(s.lastCountry)
        ? s.lastCountry
        : (countries.isEmpty ? null : countries.first);
    final list =
        country == null ? <Channel>[] : s.channelsOf(country, category: cat);

    final header = <Widget>[
      _title(context, 'Categories'),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        child: Wrap(spacing: 12, runSpacing: 10, children: [
          for (final k in kCategories)
            ChoiceChip(
              avatar: Icon(_categoryIcons[k]),
              label: Text(_categoryNames[k]!,
                  style: const TextStyle(fontSize: 17)),
              selected: k == cat,
              onSelected: (_) => s.setTvCategory(k),
            ),
        ]),
      ),
    ];
    if (country == null) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [...header, _hint(context, 'No channels in this category.')]);
    }
    return _pageLayout([
      ...header,
      _CountryRow(
        state: s,
        countries: countries,
        selected: country,
        category: cat,
      ),
      _title(context, '${_categoryNames[cat]} · ${s.countryName(country)}',
          sub: '${list.length} channels'),
    ], (shrink) => TileGrid(
          shrink: shrink,
          itemCount: list.length,
          centerIndex: list.indexWhere((c) => c.url == s.current?.url),
          itemBuilder: (_, i) => ChannelTile(state: s, channel: list[i]),
        ));
  }
}
