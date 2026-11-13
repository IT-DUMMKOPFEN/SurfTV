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
import 'models.dart';
import 'storage.dart';

/// Channel list filter for geo-blocked channels.
enum VpnFilter { all, noVpn, vpnOnly }

/// What the background job does.
enum JobKind { update, test }

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Central state of SurfTV: channels, player, favorites, settings.
class AppState extends ChangeNotifier {
  AppState() {
    video = VideoController(player);
    _subs.addAll([
      player.stream.buffering.listen((b) {
        buffering = b;
        notifyListeners();
      }),
      player.stream.error.listen((e) {
        if ((videoWidth ?? 0) == 0) {
          playError = e;
          notifyListeners();
        }
      }),
      player.stream.width.listen((w) {
        videoWidth = w;
        if ((w ?? 0) > 0) {
          playError = null;
          firstFrameSeen = true;
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

  /// Channel URLs stored on the remote keys 0..9.
  List<String?> favorites = List.filled(10, null);

  Channel? get current =>
      (currentIndex >= 0 && currentIndex < channels.length)
          ? channels[currentIndex]
          : null;

  String countryName(String code) {
    if (code == 'XX') return 'International / Unknown';
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
      final cat = p.getString('category');
      category = kCategories.contains(cat) ? cat : null;
    } catch (e) {
      debugPrint('SurfTV: settings not loaded: $e');
    }
    notifyListeners();
    unawaited(player.setVolume(muted ? 0 : volume));

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
    if (db != null) _setDb(db);
    loading = false;
    notifyListeners();

    final last = _prefs?.getString('lastChannel');
    final i = last == null ? -1 : indexOfUrl(last);
    if (i >= 0) unawaited(play(i));
  }

  void _setDb(ChannelDb db) {
    countryNames = db.countryNames;
    listUpdated = db.updated;
    final list = List<Channel>.from(db.channels);
    String key(Channel c) =>
        '${c.countryCode == 'XX' ? '~' : countryName(c.countryCode).toLowerCase()}'
        '|${c.name.toLowerCase()}';
    list.sort((a, b) => key(a).compareTo(key(b)));
    channels = list;

    _indexByUrl
      ..clear()
      ..addAll({for (var i = 0; i < list.length; i++) list[i].url: i});

    _rebuildVisible();
  }

  /// Applies the VPN + category filter.
  void _rebuildVisible() {
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
    if (playing != null && !list.any((c) => c.url == playing.url)) {
      list = [...list, playing];
    }
    final result =
        ChannelDb(channels: list, countryNames: names, updated: db.updated);
    _setDb(result);
    // Only the index changes - the player is not touched, so TV keeps running.
    currentIndex = playing == null ? -1 : indexOfUrl(playing.url);
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
          await applyScan(db, merge: scanner.cancelled);
        }
      } else {
        final playing = current;
        final keep = <String>{
          if (playing != null && (videoWidth ?? 0) > 0) playing.url,
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
  }

  /// Stops the running job. Results so far are kept.
  void stopJob() {
    _scanner?.cancel();
    notifyListeners();
  }

  bool get jobStopping => _scanner?.cancelled ?? false;

  // ================= Playback =================

  Future<void> play(int index) async {
    if (index < 0 || index >= channels.length) return;
    currentIndex = index;
    playError = null;
    videoWidth = null;
    videoHeight = null;
    notifyListeners();
    final c = channels[index];
    unawaited(_prefs?.setString('lastChannel', c.url));
    await player.open(Media(c.url, httpHeaders: c.httpHeaders));
    await player.setVolume(muted ? 0 : volume);
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
    jobProgress.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
