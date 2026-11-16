import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'channel_scanner.dart';
import 'epg.dart';
import 'models.dart';
import 'storage.dart';
import 'stream_proxy.dart';

/// Channel list filter for geo-blocked channels.
enum VpnFilter { all, noVpn, vpnOnly }

/// One selectable video quality (HLS variant / video track).
class VideoQuality {
  const VideoQuality(this.id, this.height, this.bitrate);
  final int id;
  final int height;
  final int bitrate;

  /// Key to remember the choice per channel.
  String get key => height > 0 ? 'h$height' : 'b$bitrate';

  String get label {
    final mb = bitrate > 0 ? '${(bitrate / 1000000).toStringAsFixed(1)} Mbit/s' : '';
    if (height > 0) return mb.isEmpty ? '${height}p' : '${height}p  ($mb)';
    return mb.isEmpty ? 'Track $id' : mb;
  }

  String get short => height > 0
      ? '${height}p'
      : (bitrate > 0 ? '${(bitrate / 1000000).toStringAsFixed(1)}M' : '#$id');
}

/// The two user interfaces.
enum UiMode { classic, tvLike }

/// What the background job does.
enum JobKind { update, test }

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Central state of SlaxxTV: channels, player, favorites, settings.
class AppState extends ChangeNotifier {
  AppState() {
    video = VideoController(player);
    _configurePlayer();
    // Pluto & co: restart cleanly after a break (ad / logo clip).
    _subs.add(StreamProxy.instance.onBreak.listen((_) => _onStreamBreak()));
    // Video tracks (qualities) of the running stream.
    _subs.add(player.stream.tracks.listen((_) => _refreshQualities()));
    _stallTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkStall());
    _subs.addAll([
      player.stream.buffering.listen((b) {
        buffering = b;
        notifyListeners();
      }),
      player.stream.error.listen((e) {
        if ((videoWidth ?? 0) == 0) {
          // Direct playback failed: try the compatibility mode first.
          if (_tryCompatibility()) return;
          playError = e;
          notifyListeners();
        }
      }),
      player.stream.width.listen((w) {
        videoWidth = w;
        if ((w ?? 0) > 0) {
          playError = null;
          playStatus = null;
          firstFrameSeen = true;
          _watchdog?.cancel();
        }
        notifyListeners();
      }),
      player.stream.height.listen((h) {
        videoHeight = h;
        notifyListeners();
      }),
    ]);
  }

  final Player player = Player();
  late final VideoController video;
  final List<StreamSubscription> _subs = [];
  SharedPreferences? _prefs;

  // ---- Channels ----
  List<Channel> channels = [];
  /// Channels that pass the VPN + category filter (zapping uses this list).
  List<Channel> visible = [];

  /// [visible] grouped by country, for the channel list.
  List<CountryGroup> groups = [];

  // ---- Filters ----
  VpnFilter vpnFilter = VpnFilter.all;

  /// null = all channels, otherwise one of [kCategories].
  String? category;
  Map<String, String> countryNames = {};
  DateTime? listUpdated;
  final Map<String, int> _indexByUrl = {};

  // ---- Playback ----
  int currentIndex = -1;
  bool buffering = false;
  String? playError;
  int? videoWidth;
  int? videoHeight;

  /// False until the first video picture arrived (start picture is shown).
  bool firstFrameSeen = false;

  // ---- Background job (channel search / channel test) ----
  ChannelScanner? _scanner;
  JobKind? jobKind;
  TestMode jobMode = TestMode.quick;
  String? jobError;

  /// Live progress of the job - listened to by the progress widgets only.
  final ValueNotifier<ScanProgress?> jobProgress = ValueNotifier(null);
  bool get jobRunning => _scanner != null;

  // ---- Settings ----
  double volume = 70;
  bool muted = false;
  ThemeMode themeMode = ThemeMode.dark;
  bool fullscreen = false;

  /// Which user interface is shown (F1 / switch toggles).
  UiMode uiMode = UiMode.classic;

  /// "My Channels" - unlimited favorite list (channel URLs), separate from
  /// the remote keys 0..9.
  List<String> myChannels = [];

  /// "Watch Live": the picture fills the app window (not the monitor).
  bool watchLive = false;

  /// Last selected country - shown again (centered) in both UIs.
  String? lastCountry;

  /// TV like: open tab and selected category.
  int tvTab = 0;
  String tvCategory = 'movies';

  /// TV like, My Channels: show the program guide instead of the tiles.
  /// TV like, My Channels: 0 = tiles, 1 = program guide, 2 = sort.
  int myView = 0;

  void setMyView(int v) {
    myView = v;
    notifyListeners();
  }

  /// Drag & drop in My Channels: moves the channel at [oldIndex] of
  /// [myChannelList] to [newIndex] (ReorderableListView indexes).
  void moveMyChannel(int oldIndex, int newIndex) {
    final shown = myChannelList.map((c) => c.url).toList();
    if (oldIndex < 0 || oldIndex >= shown.length) return;
    if (newIndex > oldIndex) newIndex--;
    final url = shown.removeAt(oldIndex);
    shown.insert(newIndex.clamp(0, shown.length), url);
    // Channels that are not in the list right now keep their place at the end.
    myChannels = [...shown, ...myChannels.where((u) => !shown.contains(u))];
    _prefs?.setStringList('myChannels', myChannels);
    notifyListeners();
  }

  // ---- Program guide (EPG) for My Channels ----
  Map<String, List<Programme>> epg = {};
  DateTime? epgFetched;
  bool epgLoading = false;
  String? epgStatus;
  Timer? _clock;
  Timer? _epgDebounce;

  /// The user's own feeds (--own--), always on top of the list.
  List<Channel> ownFeeds = [];
  static const kDefaultOwnUrl =
      'https://daserste-live.ard-mcdn.de/daserste/live/hls/de/master.m3u8';

  /// Counts finished list updates (the UI asks for a quick test then).
  final ValueNotifier<int> updateDone = ValueNotifier(0);

  /// Channel URLs stored on the remote keys 0..9.
  List<String?> favorites = List.filled(10, null);

  Channel? get current =>
      (currentIndex >= 0 && currentIndex < channels.length)
          ? channels[currentIndex]
          : null;

  String countryName(String code) {
    if (code == 'XX') return 'International / Unknown';
    if (code == kOwnCountry) return '--own--';
    return countryNames[code] ?? code;
  }

  /// "16:9" or "4:3", detected from the running video.
  String? get aspectLabel {
    final w = videoWidth ?? 0, h = videoHeight ?? 0;
    if (w <= 0 || h <= 0) return null;
    return (w / h) < 1.55 ? '4:3' : '16:9';
  }

  int indexOfUrl(String url) => _indexByUrl[url] ?? -1;

  Channel? favoriteChannel(int slot) {
    final url = favorites[slot];
    if (url == null) return null;
    final i = indexOfUrl(url);
    return i < 0 ? null : channels[i];
  }

  // ================= Loading / saving =================

  /// True until settings and the channel list are loaded.
  bool loading = true;

  /// Loads settings and channels. Called AFTER runApp, so the window shows
  /// up at once. Never await the player here: media_kit only finishes its
  /// setup once the video widget is on screen.
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final p = _prefs!;
      volume = p.getDouble('volume') ?? 70;
      muted = p.getBool('muted') ?? false;
      themeMode =
          (p.getString('theme') == 'light') ? ThemeMode.light : ThemeMode.dark;
      _compatUrls.addAll(p.getStringList('compatUrls') ?? const []);
      bufferEnabled = p.getBool('bufferEnabled') ?? true;
      stallDetection = p.getBool('stallDetection') ?? false;
      hardwareDecoding = p.getBool('hardwareDecoding') ?? false;
      final qp = p.getString('qualities');
      if (qp != null) {
        _qualityPrefs = (jsonDecode(qp) as Map).cast<String, String>();
      }
      bufferSeconds = p.getInt('bufferSeconds') ?? 5;
      final own = p.getString('ownFeeds');
      ownFeeds = own == null
          ? [_ownChannel('Das Erste', kDefaultOwnUrl)]
          : [
              for (final e in jsonDecode(own) as List)
                _ownChannel((e as Map)['n'] as String, e['u'] as String),
            ];
      final fav = p.getString('favorites');
      if (fav != null) {
        final list = (jsonDecode(fav) as List).cast<String?>();
        for (var i = 0; i < 10 && i < list.length; i++) {
          favorites[i] = list[i];
        }
      }
      vpnFilter = VpnFilter.values.firstWhere(
          (f) => f.name == p.getString('vpnFilter'),
          orElse: () => VpnFilter.all);
      uiMode = p.getString('ui') == 'tv' ? UiMode.tvLike : UiMode.classic;
      myChannels = p.getStringList('myChannels') ?? [];
      lastCountry = p.getString('lastCountry');
      shownCountries = (p.getStringList('shownCountries') ?? const []).toSet();
      tvTab = p.getInt('tvTab') ?? 0;
      final tc = p.getString('tvCategory');
      if (kCategories.contains(tc)) tvCategory = tc!;
      final cat = p.getString('category');
      category = kCategories.contains(cat) ? cat : null;
    } catch (e) {
      debugPrint('SlaxxTV: settings not loaded: $e');
    }
    notifyListeners();
    unawaited(player.setVolume(muted ? 0 : volume));
    unawaited(_applyBuffering());

    // Saved list (from the last channel search) or the list shipped with
    // the app - whichever is newer.
    final saved = await Storage.loadDb();
    final shipped = await Storage.loadDefaultDb();
    ChannelDb? db = saved;
    if (shipped != null &&
        shipped.channels.isNotEmpty &&
        (db == null ||
            db.channels.isEmpty ||
            shipped.updated.isAfter(db.updated))) {
      db = shipped;
    }
    // Also without a list: the own feeds are shown.
    _setDb(db ??
        ChannelDb(channels: const [], countryNames: const {}, updated: DateTime.now()));
    if (db == null) listUpdated = null;
    loading = false;
    notifyListeners();

    // Program guide: cached data first, then refresh if needed.
    final cached = await EpgService.load();
    if (cached != null) {
      epg = cached.$1;
      epgFetched = cached.$2;
      notifyListeners();
    }
    // Keeps "now" / progress of the guide up to date.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (epg.isNotEmpty) notifyListeners();
    });
    unawaited(refreshEpg());

    final last = _prefs?.getString('lastChannel');
    final i = last == null ? -1 : indexOfUrl(last);
    if (i >= 0) unawaited(play(i));
  }

  /// URL of a removed duplicate -> URL of the kept channel (last clean up).
  Map<String, String> _replaced = {};

  void _setDb(ChannelDb db) {
    countryNames = db.countryNames;
    listUpdated = db.updated;
    // Clean up: only one channel per stream address.
    // Own feeds are not part of the clean up and win over list entries
    // with the same address.
    final ownUrls = {for (final c in ownFeeds) c.url};
    final clean = dedupeChannels([
      for (final c in db.channels)
        if (c.source != 'own' && !ownUrls.contains(c.url) && !isYouTubeUrl(c.url))
          c,
    ]);
    _replaced = clean.replaced;
    _remapFavorites();
    final list = <Channel>[
      ...clean.channels,
      ...ownFeeds,
    ];
    // --own-- always on top, "International / Unknown" at the end.
    String key(Channel c) =>
        '${c.countryCode == kOwnCountry ? '\u0000' : c.countryCode == 'XX' ? '~' : countryName(c.countryCode).toLowerCase()}'
        '|${c.name.toLowerCase()}';
    list.sort((a, b) => key(a).compareTo(key(b)));
    channels = list;

    _indexByUrl
      ..clear()
      ..addAll({for (var i = 0; i < list.length; i++) list[i].url: i});

    _rebuildVisible();
  }

  /// My Channels and keys 0-9 that pointed to a removed duplicate now point
  /// to the channel that was kept.
  void _remapFavorites() {
    if (_replaced.isEmpty) return;
    var changed = false;
    final my = <String>[];
    for (final u in myChannels) {
      final n = _replaced[u] ?? u;
      if (n != u) changed = true;
      if (!my.contains(n)) my.add(n);
    }
    myChannels = my;
    for (var i = 0; i < favorites.length; i++) {
      final u = favorites[i];
      if (u != null && _replaced.containsKey(u)) {
        favorites[i] = _replaced[u];
        changed = true;
      }
    }
    if (changed) {
      _prefs?.setStringList('myChannels', myChannels);
      _prefs?.setString('favorites', jsonEncode(favorites));
    }
  }

  /// Applies the VPN + category filter.
  void _rebuildVisible() {
    visibleAll = channels.where((c) {
      if (vpnFilter == VpnFilter.noVpn && c.needsVpn) return false;
      if (vpnFilter == VpnFilter.vpnOnly && !c.needsVpn) return false;
      return true;
    }).toList();
    _countryCache.clear();
    _channelCache.clear();
    visible = channels.where((c) {
      if (vpnFilter == VpnFilter.noVpn && c.needsVpn) return false;
      if (vpnFilter == VpnFilter.vpnOnly && !c.needsVpn) return false;
      if (category != null && !c.categories.contains(category)) return false;
      return true;
    }).toList();
    final map = <String, List<Channel>>{};
    for (final c in visible) {
      map.putIfAbsent(c.countryCode, () => []).add(c);
    }
    groups = [
      for (final e in map.entries)
        CountryGroup(e.key, countryName(e.key), e.value),
    ];
  }

  void setVpnFilter(VpnFilter f) {
    vpnFilter = f;
    _prefs?.setString('vpnFilter', f.name);
    _rebuildVisible();
    notifyListeners();
  }

  void setCategory(String? c) {
    category = c;
    if (c == null) {
      _prefs?.remove('category');
    } else {
      _prefs?.setString('category', c);
    }
    _rebuildVisible();
    notifyListeners();
  }

  /// Takes over a new channel list. The channel you are watching keeps
  /// running, even if it is not in the new list.
  /// [merge] = true keeps the old channels (used when a search was stopped).
  Future<void> applyScan(ChannelDb db, {bool merge = false}) async {
    final playing = current;
    var list = db.channels;
    var names = db.countryNames;
    if (merge && channels.isNotEmpty) {
      final byUrl = {for (final c in channels) c.url: c};
      for (final c in db.channels) {
        byUrl[c.url] = c;
      }
      list = byUrl.values.toList();
      names = {...countryNames, ...db.countryNames};
    }
    // Channels in My Channels, on the keys 0-9 and the one you are watching
    // always stay in the list.
    final urls = {for (final c in list) c.url};
    final keep = <String>{
      ...myChannels,
      for (final f in favorites)
        if (f != null) f,
      if (playing != null) playing.url,
    };
    final extra = <Channel>[
      for (final u in keep)
        if (!urls.contains(u) && indexOfUrl(u) >= 0) channels[indexOfUrl(u)],
    ];
    if (playing != null &&
        !urls.contains(playing.url) &&
        !extra.any((c) => c.url == playing.url)) {
      extra.add(playing);
    }
    list = [...list, ...extra];
    _setDb(ChannelDb(channels: list, countryNames: names, updated: db.updated));
    final result =
        ChannelDb(channels: channels, countryNames: names, updated: db.updated);
    // Only the index changes - the player is not touched, so TV keeps running.
    currentIndex = playing == null
        ? -1
        : indexOfUrl(_replaced[playing.url] ?? playing.url);
    notifyListeners();
    await Storage.saveDb(result);
  }

  // ================= Channel search / test (runs in background) =================

  /// Starts a channel search ([JobKind.update]) or a test of the current
  /// list ([JobKind.test]). TV keeps playing meanwhile.
  Future<void> startJob(JobKind kind, TestMode mode) async {
    if (_scanner != null) return;
    final scanner = ChannelScanner(mode: mode);
    _scanner = scanner;
    jobKind = kind;
    jobMode = mode;
    jobError = null;
    jobProgress.value = const ScanProgress(message: 'Starting...');
    notifyListeners();
    try {
      ChannelDb db;
      if (kind == JobKind.update) {
        db = await scanner.run((p) => jobProgress.value = p);
        if (db.channels.isNotEmpty) {
          // The complete list replaces the old one.
          await applyScan(db);
        }
      } else {
        final playing = current;
        // Own feeds are not tested (always kept).
        final keep = <String>{
          if (playing != null && (videoWidth ?? 0) > 0) playing.url,
          for (final c in channels)
            if (c.source == 'own') c.url,
        };
        db = await scanner.testExisting(
            List.of(channels), countryNames, (p) => jobProgress.value = p,
            keepUrls: keep);
        await applyScan(db);
      }
    } catch (e) {
      jobError = e.toString().replaceFirst('Exception: ', '');
    }
    _scanner = null;
    notifyListeners();
    // Update finished: the UI offers a quick test.
    if (kind == JobKind.update && jobError == null && !scanner.cancelled) {
      updateDone.value++;
    }
  }

  /// Stops the running job. Results so far are kept.
  void stopJob() {
    _scanner?.cancel();
    notifyListeners();
  }

  bool get jobStopping => _scanner?.cancelled ?? false;

  // ================= Playback =================

  /// Browser-like player settings, so streams that play in a web browser
  /// also play here:
  ///  * cookies from redirects are kept (some CDNs need them),
  ///  * a browser user agent instead of "libmpv" (some servers block it),
  ///  * no subtitle tracks (WebVTT tracks of live streams can stall the start),
  ///  * reconnect when the connection drops.
  static const browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  Future<void> _setProp(String name, String value) async {
    try {
      final p = player.platform as dynamic;
      await p.setProperty(name, value);
    } catch (e) {
      debugPrint('SlaxxTV: player option $name not set: $e');
    }
  }

  Future<void> _configurePlayer() async {
    await _setProp('cookies', 'yes');
    await _setProp('user-agent', browserUserAgent);
    await _setProp('sid', 'no');
    // Give up a dead connection after 12 s (then compatibility mode).
    await _setProp('network-timeout', '12');
    // A new connection for every HLS segment: persistent connections are a
    // known cause of "tcp: ffurl_read returned ..." stalls.
    await _setProp('demuxer-lavf-o', 'http_persistent=0');
  }

  // ---- Compatibility mode (stream goes through StreamProxy) ----

  /// Channels that only play in compatibility mode (remembered).
  final Set<String> _compatUrls = {};
  bool _usingCompat = false;
  Timer? _watchdog;

  // ---- Buffering (preload some seconds before playing) ----

  /// Preload before the picture starts and after short dropouts.
  bool bufferEnabled = true;

  /// Seconds that are loaded ahead.
  int bufferSeconds = 5;

  Future<void> _applyBuffering() async {
    if (bufferEnabled) {
      await _setProp('cache', 'yes');
      await _setProp('cache-pause', 'yes');
      await _setProp('cache-pause-initial', 'yes');
      await _setProp('cache-pause-wait', '$bufferSeconds');
      await _setProp('demuxer-readahead-secs', '${bufferSeconds + 10}');
      await _setProp('cache-secs', '${bufferSeconds + 30}');
    } else {
      await _setProp('cache-pause-initial', 'no');
      await _setProp('cache-pause-wait', '1');
      await _setProp('demuxer-readahead-secs', '1');
    }
  }

  void setBuffering({bool? enabled, int? seconds}) {
    if (enabled != null) bufferEnabled = enabled;
    if (seconds != null) bufferSeconds = seconds;
    _prefs?.setBool('bufferEnabled', bufferEnabled);
    _prefs?.setInt('bufferSeconds', bufferSeconds);
    unawaited(_applyBuffering());
    notifyListeners();
  }

  /// Stops the player cleanly before the app quits. Without this, the
  /// player could still send events while the app shuts down
  /// (crash "abort() called" in "mpv core" on macOS).
  bool _shutDown = false;
  Future<void> shutdown() async {
    if (_shutDown) return;
    _shutDown = true;
    _watchdog?.cancel();
    _stallTimer?.cancel();
    _scanner?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {}
  }

  /// Shown under the spinner, e.g. "Compatibility mode...".
  String? playStatus;

  /// Pluto TV: separate audio/video playlists and stitched-in ads and logo
  /// clips (breaks). Always played in compatibility mode with a clean
  /// restart after every break.
  static bool isPluto(Channel c) {
    final u = c.url.toLowerCase();
    return u.contains('pluto.tv') ||
        u.contains('plutotv') ||
        u.contains('jmp2.uk/plu-');
  }

  DateTime _lastBreakRestart = DateTime.fromMillisecondsSinceEpoch(0);

  void _onStreamBreak() {
    final c = current;
    if (c == null || !_usingCompat || !isPluto(c) || _shutDown) return;
    // Only once the picture is running - never while it is still starting
    // (that would restart the stream again and again).
    if ((videoWidth ?? 0) == 0 || player.state.position.inSeconds < 6) return;
    final now = DateTime.now();
    if (now.difference(_lastBreakRestart).inSeconds < 12) return;
    _lastBreakRestart = now;
    unawaited(_open(c, compat: true, quiet: true));
  }

  // ---- Hardware decoding (setting, off by default) ----

  /// Decode the video with the graphics chip instead of the processor.
  /// Less load, but some devices / streams show errors or a green picture.
  bool hardwareDecoding = false;

  String get _hwdecValue => !hardwareDecoding
      ? 'no'
      : (Platform.isAndroid ? 'mediacodec-copy' : 'auto-safe');

  Future<void> setHardwareDecoding(bool v) async {
    hardwareDecoding = v;
    _prefs?.setBool('hardwareDecoding', v);
    notifyListeners();
    await _setProp('hwdec', _hwdecValue);
    // Takes effect cleanly with a fresh start of the running stream.
    final c = current;
    if (c != null && !_shutDown) {
      unawaited(_open(c, compat: _usingCompat, quiet: true));
    }
  }

  // ---- Stall detection (setting, off by default) ----
  bool stallDetection = false;
  Timer? _stallTimer;
  Duration _lastPos = Duration.zero;
  DateTime _lastProgress = DateTime.now();

  void setStallDetection(bool v) {
    stallDetection = v;
    _prefs?.setBool('stallDetection', v);
    _lastProgress = DateTime.now();
    notifyListeners();
  }

  /// Picture stands still for 10 s (also endless buffering): restart.
  void _checkStall() {
    final c = current;
    if (!stallDetection || c == null || _shutDown || !firstFrameSeen) return;
    if ((videoWidth ?? 0) == 0 && playError != null) return;
    final pos = player.state.position;
    final now = DateTime.now();
    if (pos != _lastPos) {
      _lastPos = pos;
      _lastProgress = now;
      return;
    }
    if (now.difference(_lastProgress).inSeconds >= 10) {
      _lastProgress = now;
      playStatus = 'Stream stalled - restarting...';
      notifyListeners();
      unawaited(_open(c, compat: _usingCompat, quiet: false, status: playStatus));
    }
  }

  // ---- Quality (video tracks / HLS variants) per stream ----

  /// Selectable qualities of the running stream (empty = only one).
  List<VideoQuality> qualities = [];

  /// Selected quality (null = automatic).
  VideoQuality? quality;
  Map<String, String> _qualityPrefs = {};
  bool _qualityApplied = false;

  Future<void> _refreshQualities() async {
    try {
      final raw = await (player.platform as dynamic).getProperty('track-list');
      final list = jsonDecode(raw as String) as List;
      final q = <VideoQuality>[];
      int? selected;
      for (final t in list) {
        final m = t as Map;
        if (m['type'] != 'video' || m['albumart'] == true) continue;
        final id = (m['id'] as num).toInt();
        final h = (m['demux-h'] as num?)?.toInt() ?? 0;
        final br = ((m['hls-bitrate'] ?? m['demux-bitrate']) as num?)?.toInt() ?? 0;
        q.add(VideoQuality(id, h, br));
        if (m['selected'] == true) selected = id;
      }
      q.sort((a, b) =>
          b.height != a.height ? b.height.compareTo(a.height) : b.bitrate.compareTo(a.bitrate));
      qualities = q.length > 1 ? q : [];
      final c = current;
      // Apply the quality saved for this channel once.
      if (c != null && !_qualityApplied && qualities.isNotEmpty) {
        _qualityApplied = true;
        final pref = _qualityPrefs[c.url];
        final want = pref == null
            ? null
            : qualities.where((x) => x.key == pref).firstOrNull;
        if (want != null) {
          quality = want;
          await _setProp('vid', '${want.id}');
          notifyListeners();
          return;
        }
      }
      if (quality != null && selected != null && quality!.id != selected) {
        quality = qualities.where((x) => x.id == selected).firstOrNull;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// [q] null = automatic (best quality the connection allows).
  Future<void> selectQuality(VideoQuality? q) async {
    final c = current;
    quality = q;
    await _setProp('vid', q == null ? 'auto' : '${q.id}');
    if (c != null) {
      if (q == null) {
        _qualityPrefs.remove(c.url);
      } else {
        _qualityPrefs[c.url] = q.key;
      }
      _prefs?.setString('qualities', jsonEncode(_qualityPrefs));
    }
    notifyListeners();
  }

  /// The local proxy could not be started (compatibility mode off).
  bool _proxyBroken = false;

  bool _canCompat(Channel c) {
    if (_proxyBroken) return false;
    final u = c.url.toLowerCase();
    return u.startsWith('http://') || u.startsWith('https://');
  }

  /// Switches the running channel to compatibility mode (once).
  bool _tryCompatibility() {
    final c = current;
    if (c == null || _usingCompat || !_canCompat(c)) return false;
    _compatUrls.add(c.url);
    _prefs?.setStringList('compatUrls', _compatUrls.take(2000).toList());
    unawaited(_open(c, compat: true));
    return true;
  }

  Future<void> _open(Channel c,
      {required bool compat, bool quiet = false, String? status}) async {
    _usingCompat = compat;
    playStatus = status ?? (compat && !quiet && !isPluto(c) ? 'Compatibility mode...' : null);
    playError = null;
    _lastProgress = DateTime.now();
    if (!quiet) {
      qualities = [];
      quality = null;
      _qualityApplied = false;
    } else {
      _qualityApplied = false; // re-apply the chosen quality after restart
    }
    notifyListeners();
    await _setProp('hwdec', _hwdecValue);
    // Smooth timestamps over breaks (ads, logo clips).
    await _setProp('demuxer-lavf-linearize-timestamps', isPluto(c) ? 'yes' : 'auto');
    final ua =
        (c.userAgent?.isNotEmpty ?? false) ? c.userAgent! : browserUserAgent;
    String? proxied;
    if (compat) {
      try {
        proxied = await StreamProxy.instance
            .url(c.url, referer: c.referrer, userAgent: ua);
      } catch (e) {
        // Local proxy not available (e.g. blocked by the system):
        // play directly instead of not at all.
        debugPrint('SlaxxTV: compatibility mode not available: $e');
        _usingCompat = false;
        _proxyBroken = true;
        playStatus = null;
      }
    }
    if (current?.url != c.url) return; // zapped on meanwhile
    if (proxied != null) {
      await player.open(Media(proxied));
    } else {
      await _setProp('user-agent', ua);
      await player.open(Media(c.url, httpHeaders: c.httpHeaders));
    }
    await player.setVolume(muted ? 0 : volume);
    // No picture after 15 s (and no error)? Try the other way.
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 15), () {
      if (current?.url == c.url && (videoWidth ?? 0) == 0 && playError == null) {
        if (!_tryCompatibility() && _usingCompat) {
          playError = 'No picture from this channel (timeout).';
          notifyListeners();
        }
      }
    });
  }

  Future<void> play(int index) async {
    if (index < 0 || index >= channels.length) return;
    currentIndex = index;
    playError = null;
    videoWidth = null;
    videoHeight = null;
    notifyListeners();
    final c = channels[index];
    unawaited(_prefs?.setString('lastChannel', c.url));
    lastCountry = c.countryCode;
    unawaited(_prefs?.setString('lastCountry', c.countryCode));
    // Channels known to need it (and Pluto) start in compatibility mode.
    await _open(c,
        compat: (_compatUrls.contains(c.url) || isPluto(c)) && _canCompat(c));
  }

  // ================= Own feeds (--own--) =================

  static Channel _ownChannel(String name, String url) => Channel(
        name: name,
        countryCode: kOwnCountry,
        url: url.trim(),
        source: 'own',
      );

  void _saveOwn() {
    _prefs?.setString(
        'ownFeeds',
        jsonEncode([
          for (final c in ownFeeds) {'n': c.name, 'u': c.url},
        ]));
    final playing = current;
    _setDb(ChannelDb(
        channels: channels,
        countryNames: countryNames,
        updated: listUpdated ?? DateTime.now()));
    currentIndex = playing == null ? -1 : indexOfUrl(playing.url);
    notifyListeners();
  }

  void addOwnFeed(String name, String url) {
    ownFeeds.add(_ownChannel(name.trim().isEmpty ? url : name, url));
    _saveOwn();
  }

  void updateOwnFeed(int i, String name, String url) {
    ownFeeds[i] = _ownChannel(name.trim().isEmpty ? url : name, url);
    _saveOwn();
  }

  void removeOwnFeed(int i) {
    ownFeeds.removeAt(i);
    _saveOwn();
  }

  Future<void> playChannel(Channel c) => play(indexOfUrl(c.url));

  /// Zapping follows the filtered list (VPN filter + category).
  void nextChannel() => _zap(1);

  void previousChannel() => _zap(-1);

  void _zap(int step) {
    final list = visible.isNotEmpty ? visible : channels;
    if (list.isEmpty) return;
    final url = current?.url;
    var i = url == null ? -1 : list.indexWhere((c) => c.url == url);
    if (i < 0) {
      i = step > 0 ? 0 : list.length - 1;
    } else {
      i = (i + step) % list.length;
      if (i < 0) i += list.length;
    }
    playChannel(list[i]);
  }

  // ================= Volume =================

  void setVolume(double v) {
    volume = v.clamp(0, 100);
    if (volume > 0) muted = false;
    player.setVolume(muted ? 0 : volume);
    _prefs?.setDouble('volume', volume);
    _prefs?.setBool('muted', muted);
    notifyListeners();
  }

  void volumeStep(double delta) => setVolume(volume + delta);

  void toggleMute() {
    muted = !muted;
    player.setVolume(muted ? 0 : volume);
    _prefs?.setBool('muted', muted);
    notifyListeners();
  }

  // ================= Favorites (keys 0-9) =================

  bool storeFavorite(int slot) {
    final c = current;
    if (c == null) return false;
    favorites[slot] = c.url;
    _prefs?.setString('favorites', jsonEncode(favorites));
    notifyListeners();
    return true;
  }

  bool recallFavorite(int slot) {
    final c = favoriteChannel(slot);
    if (c == null) return false;
    playChannel(c);
    return true;
  }

  // ================= UI mode / My Channels / selection =================

  void setUiMode(UiMode m) {
    uiMode = m;
    _prefs?.setString('ui', m == UiMode.tvLike ? 'tv' : 'classic');
    notifyListeners();
  }

  void toggleUi() => setUiMode(
      uiMode == UiMode.classic ? UiMode.tvLike : UiMode.classic);

  bool isMyChannel(Channel c) => myChannels.contains(c.url);

  void toggleMyChannel(Channel c) {
    final added = !myChannels.remove(c.url);
    if (added) myChannels.add(c.url);
    _prefs?.setStringList('myChannels', myChannels);
    notifyListeners();
    if (added && !epg.containsKey(c.url)) {
      // Load the guide for the new favorite (a moment later, in case
      // more favorites are added).
      _epgDebounce?.cancel();
      _epgDebounce = Timer(const Duration(seconds: 3), () => refreshEpg(force: true));
    }
  }

  // ================= Program guide (EPG) =================

  List<Programme> programmesOf(Channel c) => epg[c.url] ?? const [];

  /// Programme running now on [c] (only for channels in My Channels).
  Programme? nowOn(Channel c) {
    final t = DateTime.now();
    for (final p in programmesOf(c)) {
      if (p.isOn(t)) return p;
    }
    return null;
  }

  Programme? nextOn(Channel c) {
    final t = DateTime.now();
    for (final p in programmesOf(c)) {
      if (p.start.isAfter(t)) return p;
    }
    return null;
  }

  /// Loads the guide for My Channels. Without [force] only when the data is
  /// older than 6 hours.
  Future<void> refreshEpg({bool force = false}) async {
    if (epgLoading) return;
    final favs = myChannelList;
    if (favs.isEmpty) return;
    final fresh = epgFetched != null &&
        DateTime.now().difference(epgFetched!) < const Duration(hours: 6);
    if (!force && fresh) return;
    epgLoading = true;
    epgStatus = 'Loading program guide...';
    notifyListeners();
    try {
      final data = await EpgService.fetch(favs, (s) {
        epgStatus = s;
        notifyListeners();
      });
      epg = data;
      epgFetched = DateTime.now();
      await EpgService.save(epg, epgFetched!);
    } catch (e) {
      epgStatus = 'Program guide could not be loaded.';
    }
    epgLoading = false;
    notifyListeners();
  }

  // ================= Favorites export / import =================

  /// My Channels and keys 0-9 as JSON (with full channel data, so they can
  /// be imported on another device).
  String exportFavorites() {
    Map<String, dynamic>? ch(String? url) {
      if (url == null) return null;
      final i = indexOfUrl(url);
      return i < 0 ? null : channels[i].toJson();
    }

    return const JsonEncoder.withIndent('  ').convert({
      'app': 'SlaxxTV',
      'type': 'favorites',
      'version': 1,
      'exported': DateTime.now().toIso8601String(),
      'myChannels': [
        for (final u in myChannels)
          if (ch(u) != null) ch(u),
      ],
      'keys': [for (final u in favorites) ch(u)],
    });
  }

  /// Adds the favorites of an exported file. Returns how many channels were
  /// added to My Channels. Throws [FormatException] for a wrong file.
  Future<int> importFavorites(String text) async {
    final j = jsonDecode(text);
    if (j is! Map ||
        !(j['app'] == 'SlaxxTV' || j['app'] == 'SurfTV') ||
        j['type'] != 'favorites') {
      throw const FormatException('This is not a SlaxxTV favorites file.');
    }
    final my = [
      for (final e in (j['myChannels'] as List? ?? const []))
        Channel.fromJson((e as Map).cast<String, dynamic>()),
    ];
    final keys = [
      for (final e in (j['keys'] as List? ?? const []))
        e == null ? null : Channel.fromJson((e as Map).cast<String, dynamic>()),
    ];
    // Channels that are not in the list yet are added to it.
    final known = {for (final c in channels) c.url};
    final extra = <Channel>[
      for (final c in [...my, ...keys.whereType<Channel>()])
        if (known.add(c.url)) c,
    ];
    if (extra.isNotEmpty) {
      final db = ChannelDb(
          channels: [...channels, ...extra],
          countryNames: countryNames,
          updated: listUpdated ?? DateTime.now());
      final playing = current;
      _setDb(db);
      currentIndex = playing == null ? -1 : indexOfUrl(playing.url);
      await Storage.saveDb(db);
    }
    var added = 0;
    for (final c in my) {
      final url = _replaced[c.url] ?? c.url;
      if (!myChannels.contains(url)) {
        myChannels.add(url);
        added++;
      }
    }
    for (var i = 0; i < 10 && i < keys.length; i++) {
      final k = keys[i];
      if (k != null) favorites[i] = _replaced[k.url] ?? k.url;
    }
    _prefs?.setStringList('myChannels', myChannels);
    _prefs?.setString('favorites', jsonEncode(favorites));
    notifyListeners();
    unawaited(refreshEpg(force: true));
    return added;
  }

  /// My Channels as channel objects (channels no longer in the list are skipped).
  List<Channel> get myChannelList => [
        for (final u in myChannels)
          if (indexOfUrl(u) >= 0) channels[indexOfUrl(u)],
      ];

  void setLastCountry(String code) {
    if (lastCountry == code) return;
    lastCountry = code;
    _prefs?.setString('lastCountry', code);
    notifyListeners();
  }

  void setTvTab(int i) {
    tvTab = i;
    _prefs?.setInt('tvTab', i);
    notifyListeners();
  }

  void setTvCategory(String c) {
    tvCategory = c;
    _prefs?.setString('tvCategory', c);
    notifyListeners();
  }

  /// All channels of one country (unfiltered by category, VPN filter applied).
  List<Channel> channelsOf(String country, {String? category}) =>
      _channelCache.putIfAbsent(
          '$country|${category ?? '*'}',
          () => visibleAll
              .where((c) =>
                  c.countryCode == country &&
                  (category == null || c.categories.contains(category)))
              .toList());

  final Map<String, List<Channel>> _channelCache = {};

  /// Channels after the VPN filter only (TV like ignores the Classic
  /// category filter and has its own Categories page).
  List<Channel> visibleAll = [];
  final Map<String, List<String>> _countryCache = {};

  /// Countries (sorted by name) that have channels, optionally in [category].
  List<String> countriesWith({String? category}) =>
      _countryCache.putIfAbsent(category ?? '*', () => _countries(category));

  List<String> _countries(String? category) {
    final set = <String>{};
    for (final c in visibleAll) {
      if (category == null || c.categories.contains(category)) {
        set.add(c.countryCode);
      }
    }
    // Countries chosen in the settings (none chosen = all). Own feeds
    // always stay.
    if (shownCountries.isNotEmpty) {
      set.removeWhere((c) => c != kOwnCountry && !shownCountries.contains(c));
    }
    final list = set.toList()
      ..sort((a, b) {
        if (a == kOwnCountry) return -1;
        if (b == kOwnCountry) return 1;
        if (a == 'XX') return 1;
        if (b == 'XX') return -1;
        return countryName(a).compareTo(countryName(b));
      });
    return list;
  }

  /// Countries shown in Discover and Categories (empty = all).
  Set<String> shownCountries = {};

  /// All countries in the channel list, for the settings (sorted by name).
  List<String> get allCountryCodes {
    final set = {for (final c in channels) c.countryCode}..remove(kOwnCountry);
    return set.toList()
      ..sort((a, b) {
        if (a == 'XX') return 1;
        if (b == 'XX') return -1;
        return countryName(a).compareTo(countryName(b));
      });
  }

  void setShownCountries(Set<String> codes) {
    shownCountries = {...codes};
    _prefs?.setStringList('shownCountries', shownCountries.toList());
    _countryCache.clear();
    notifyListeners();
  }

  /// True while only the picture is shown (fullscreen or Watch Live).
  bool get videoOnly => fullscreen || watchLive;

  void setWatchLive(bool v) {
    watchLive = v;
    notifyListeners();
  }

  /// Leaves fullscreen and Watch Live.
  void exitVideoOnly() {
    watchLive = false;
    setFullscreen(false);
    notifyListeners();
  }

  // ================= Theme / fullscreen =================

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _prefs?.setString('theme', themeMode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  Future<void> setFullscreen(bool value) async {
    if (fullscreen == value) return;
    fullscreen = value;
    notifyListeners();
    if (isDesktop) {
      await windowManager.setFullScreen(value);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
          value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  void toggleFullscreen() => setFullscreen(!fullscreen);

  @override
  void dispose() {
    _scanner?.cancel();
    _watchdog?.cancel();
    _stallTimer?.cancel();
    _clock?.cancel();
    _epgDebounce?.cancel();
    jobProgress.dispose();
    updateDone.dispose();
    if (!_shutDown) {
      for (final s in _subs) {
        s.cancel();
      }
      player.dispose();
    }
    super.dispose();
  }
}
