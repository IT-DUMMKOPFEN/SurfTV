import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'flag.dart';

const kAccent = Color(0xFF2E8BEA);

/// Channel tile: logo (if it loads), name, country flag, VPN badge.
class ChannelTile extends StatefulWidget {
  const ChannelTile({
    super.key,
    required this.state,
    required this.channel,
    this.onTap,
    this.onRemove,
    this.showFavorite = false,
  });

  final AppState state;
  final Channel channel;
  final VoidCallback? onTap;

  /// Shows a small "remove" button (My Channels).
  final VoidCallback? onRemove;

  /// Shows a small "+" button to add the channel to My Channels
  /// (Discover, Categories).
  final bool showFavorite;

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  bool _hover = false;
  bool _logoFailed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    final s = widget.state;
    final scheme = Theme.of(context).colorScheme;
    final current = s.current?.url == c.url;
    final logo = c.logo;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hover ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: current
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          elevation: _hover ? 8 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: current ? kAccent : Colors.transparent,
              width: 3,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap ?? () => s.playChannel(c),
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 28),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (logo != null && !_logoFailed)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Image.network(
                            logo,
                            height: 46,
                            fit: BoxFit.contain,
                            // Logo cannot be loaded -> leave it out.
                            errorBuilder: (_, __, ___) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && !_logoFailed) {
                                  setState(() => _logoFailed = true);
                                }
                              });
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ),
                    Text(
                      c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: (logo == null || _logoFailed) ? 17 : 13,
                      ),
                    ),
                    // Programme running now (program guide, My Channels).
                    if (s.nowOn(c) != null)
                      Text(
                        '▶ ${s.nowOn(c)!.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: kAccent),
                      ),
                  ]),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 6,
                child: FlagIcon(c.countryCode, width: 22),
              ),
              if (c.needsVpn)
                const Positioned(right: 6, bottom: 6, child: VpnBadge()),
              if (widget.showFavorite)
                Positioned(
                  right: 4,
                  top: 4,
                  child: _FavButton(state: s, channel: c),
                ),
              if (widget.onRemove != null)
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    tooltip: 'Remove from My Channels',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    onPressed: widget.onRemove,
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Small round "+" / "✓" button: add to / remove from My Channels.
class _FavButton extends StatelessWidget {
  const _FavButton({required this.state, required this.channel});
  final AppState state;
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final inMy = state.isMyChannel(channel);
    return Tooltip(
      message: inMy
          ? 'In My Channels - tap to remove'
          : 'Add to My Channels',
      child: Material(
        color: inMy ? kAccent : Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            state.toggleMyChannel(channel);
            ScaffoldMessenger.maybeOf(context)
              ?..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                duration: const Duration(seconds: 2),
                content: Text(state.isMyChannel(channel)
                    ? '"${channel.name}" added to My Channels'
                    : '"${channel.name}" removed from My Channels'),
              ));
          },
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(inMy ? Icons.check : Icons.add,
                size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Country tile: big flag, name, number of channels.
class CountryTile extends StatefulWidget {
  const CountryTile({
    super.key,
    required this.code,
    required this.name,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String name;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<CountryTile> createState() => _CountryTileState();
}

class _CountryTileState extends State<CountryTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hover ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: widget.selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          elevation: _hover ? 8 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: widget.selected ? kAccent : Colors.transparent,
                width: 3),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FlagIcon(widget.code, width: 54),
                  const SizedBox(height: 6),
                  Text(widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${widget.count} channels',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal row that can be swiped with mouse or finger.
/// The tile at [centerIndex] (last selection) is moved to the middle.
class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.itemWidth = 210,
    this.height = 124,
    this.centerIndex,
    this.spacing = 14,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemWidth;
  final double height;
  final int? centerIndex;
  final double spacing;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow> {
  final _ctrl = ScrollController();
  static const _pad = 24.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _center(false));
  }

  @override
  void didUpdateWidget(SwipeRow old) {
    super.didUpdateWidget(old);
    if (old.centerIndex != widget.centerIndex ||
        old.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _center(true));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _center(bool animate) {
    final i = widget.centerIndex;
    if (i == null || i < 0 || !_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final extent = widget.itemWidth + widget.spacing;
    final target = (_pad + i * extent + widget.itemWidth / 2 -
            pos.viewportDimension / 2)
        .clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _ctrl.animateTo(target,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    } else {
      _ctrl.jumpTo(target);
    }
  }

  void _page(int dir) {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final target = (pos.pixels + dir * pos.viewportDimension * 0.8)
        .clamp(0.0, pos.maxScrollExtent);
    _ctrl.animateTo(target,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height + 16,
      child: Stack(children: [
        ListView.builder(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: 8),
          itemExtent: widget.itemWidth + widget.spacing,
          itemCount: widget.itemCount,
          itemBuilder: (context, i) => Padding(
            padding: EdgeInsets.only(right: widget.spacing),
            child: widget.itemBuilder(context, i),
          ),
        ),
        Positioned(
            left: 0, top: 0, bottom: 0, child: _arrow(Icons.chevron_left, -1)),
        Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _arrow(Icons.chevron_right, 1)),
      ]),
    );
  }

  Widget _arrow(IconData icon, int dir) => Center(
        child: Material(
          color: Colors.black45,
          shape: const CircleBorder(),
          child: IconButton(
            color: Colors.white,
            icon: Icon(icon),
            onPressed: () => _page(dir),
          ),
        ),
      );
}

/// Grid of tiles (vertical scrolling). The tile at [centerIndex] is moved
/// to the middle.
class TileGrid extends StatefulWidget {
  const TileGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.tileWidth = 210,
    this.tileHeight = 124,
    this.centerIndex,
    this.spacing = 14,
    this.shrink = false,
  });

  /// Grid inside a page that scrolls as a whole (small screens).
  final bool shrink;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double tileWidth;
  final double tileHeight;
  final int? centerIndex;
  final double spacing;

  /// The same grid as a sliver (for pages that scroll as a whole).
  /// Only the visible tiles are built.
  Widget buildSliver(double width) {
    const pad = 24.0;
    final cols = ((width - 2 * pad + spacing) / (tileWidth + spacing))
        .floor()
        .clamp(1, 50);
    return SliverPadding(
      padding: const EdgeInsets.all(pad),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(itemBuilder, childCount: itemCount),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisExtent: tileHeight,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
        ),
      ),
    );
  }

  @override
  State<TileGrid> createState() => _TileGridState();
}

class _TileGridState extends State<TileGrid> {
  final _ctrl = ScrollController();
  int _cols = 1;
  static const _pad = 24.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _center(false));
  }

  @override
  void didUpdateWidget(TileGrid old) {
    super.didUpdateWidget(old);
    if (old.centerIndex != widget.centerIndex ||
        old.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _center(old.itemCount == widget.itemCount));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _center(bool animate) {
    if (!_ctrl.hasClients) return;
    final i = widget.centerIndex;
    final pos = _ctrl.position;
    if (i == null || i < 0) {
      if (!animate) _ctrl.jumpTo(0);
      return;
    }
    final row = i ~/ _cols;
    final target = (_pad +
            row * (widget.tileHeight + widget.spacing) +
            widget.tileHeight / 2 -
            pos.viewportDimension / 2)
        .clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _ctrl.animateTo(target,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    } else {
      _ctrl.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _cols = ((box.maxWidth - 2 * _pad + widget.spacing) /
              (widget.tileWidth + widget.spacing))
          .floor()
          .clamp(1, 50);
      return GridView.builder(
        controller: widget.shrink ? null : _ctrl,
        shrinkWrap: widget.shrink,
        physics: widget.shrink ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(_pad),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _cols,
          mainAxisExtent: widget.tileHeight,
          crossAxisSpacing: widget.spacing,
          mainAxisSpacing: widget.spacing,
        ),
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      );
    });
  }
}
