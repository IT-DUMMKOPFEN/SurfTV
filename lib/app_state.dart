import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'storage.dart';

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
        if ((w ?? 0) > 0) playError = null;
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
  List<CountryGroup> groups = [];
  Map<String, String> countryNames = {};
  DateTime? listUpdated;
  final Map<String, int> _indexByUrl = {};

  // ---- Playback ----
  int currentIndex = -1;
  bool buffering = false;
  String? playError;
  int? videoWidth;
  int? videoHeight;

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

    final map = <String, List<Channel>>{};
    for (final c in list) {
      map.putIfAbsent(c.countryCode, () => []).add(c);
    }
    groups = [
      for (final e in map.entries)
        CountryGroup(e.key, countryName(e.key), e.value),
    ];
  }

  /// Takes over the result of a channel search.
  /// [merge] = true keeps the old channels (used when the search was stopped).
  Future<void> applyScan(ChannelDb db, {bool merge = false}) async {
    final playingUrl = current?.url;
    ChannelDb result = db;
    if (merge && channels.isNotEmpty) {
      final byUrl = {for (final c in channels) c.url: c};
      for (final c in db.channels) {
        byUrl[c.url] = c;
      }
      result = ChannelDb(
        channels: byUrl.values.toList(),
        countryNames: {...countryNames, ...db.countryNames},
        updated: db.updated,
      );
    }
    _setDb(result);
    currentIndex = playingUrl == null ? -1 : indexOfUrl(playingUrl);
    notifyListeners();
    await Storage.saveDb(result);
  }

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

  void nextChannel() {
    if (channels.isEmpty) return;
    play(currentIndex < 0 ? 0 : (currentIndex + 1) % channels.length);
  }

  void previousChannel() {
    if (channels.isEmpty) return;
    play(currentIndex <= 0 ? channels.length - 1 : currentIndex - 1);
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
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
