import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Public channel sources.
class Sources {
  static const iptvOrgApi = 'https://iptv-org.github.io/api';
  static const freeTv =
      'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8';
}

/// Categories SurfTV offers as filters (iptv-org category ids).
const kCategories = ['movies', 'series', 'documentary', 'news', 'music'];

/// How long streams may take to answer.
enum TestMode {
  /// Streams must answer quickly (about 3-4 seconds).
  quick,

  /// Streams get more time (up to about 15 seconds).
  intensive,
}

class _Timing {
  const _Timing(this.connect, this.response, this.data, this.parallel);
  final Duration connect, response, data;
  final int parallel;

  static _Timing of(TestMode m) => m == TestMode.quick
      ? const _Timing(Duration(seconds: 3), Duration(seconds: 4),
          Duration(seconds: 3), 48)
      : const _Timing(Duration(seconds: 10), Duration(seconds: 15),
          Duration(seconds: 12), 24);
}

enum ScanPhase { downloading, checking, done }

/// Snapshot of a running channel search / channel test.
class ScanProgress {
  const ScanProgress({
    this.phase = ScanPhase.downloading,
    this.message = 'Downloading channel lists...',
    this.total = 0,
    this.checked = 0,
    this.found = 0,
    this.vpn = 0,
    this.recent = const [],
  });

  final ScanPhase phase;
  final String message;
  final int total;
  final int checked;

  /// Working channels so far.
  final int found;
  final int vpn;

  /// The last working channels, newest first.
  final List<Channel> recent;

  /// Streams that did not answer.
  int get dead => checked - found;
}

enum _Result { ok, vpn, dead }

/// Downloads the public channel lists and tests streams,
/// like the channel search of a real TV.
class ChannelScanner {
  ChannelScanner({this.mode = TestMode.quick});

  final TestMode mode;

  static const _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  /// Country code -> name.
  final Map<String, String> countryNames = {};

  bool _cancelled = false;
  bool get cancelled => _cancelled;

  /// Stops the search / test. Results so far are kept.
  void cancel() => _cancelled = true;

  // ===================================================================
  // Update: download the newest lists and test them
  // ===================================================================

  Future<ChannelDb> run(void Function(ScanProgress) onProgress) async {
    onProgress(const ScanProgress());

    final candidates = <Channel>[];
    final seenUrls = <String>{};
    var sourcesOk = 0;

    // ---- 1. iptv-org (main source, has geo-blocked label + categories) ----
    try {
      onProgress(const ScanProgress(message: 'Downloading iptv-org lists...'));
      final results = await Future.wait([
        _getJson('${Sources.iptvOrgApi}/countries.json'),
        _getJson('${Sources.iptvOrgApi}/channels.json'),
        _getJson('${Sources.iptvOrgApi}/streams.json'),
        _getJson('${Sources.iptvOrgApi}/blocklist.json'),
        _getJson('${Sources.iptvOrgApi}/logos.json')
            .catchError((_) => <dynamic>[]),
      ]);
      for (final c in results[0] as List) {
        final m = c as Map<String, dynamic>;
        countryNames[(m['code'] as String).toUpperCase()] = m['name'] as String;
      }
      final channelInfo = <String, Map<String, dynamic>>{};
      for (final c in results[1] as List) {
        final m = c as Map<String, dynamic>;
        channelInfo[m['id'] as String] = m;
      }
      // Channel logos - SVG cannot be shown, so they are skipped.
      final logos = <String, String>{};
      for (final l in results[4] as List) {
        final m = l as Map<String, dynamic>;
        final ch = m['channel'] as String?;
        final url = m['url'] as String?;
        if (ch == null || url == null) continue;
        if ((m['format'] as String?)?.toUpperCase() == 'SVG' ||
            url.toLowerCase().endsWith('.svg')) {
          continue;
        }
        // Prefer the logo without feed (the main logo).
        if (!logos.containsKey(ch) || m['feed'] == null) logos[ch] = url;
      }
      final blocked = <String>{
        for (final b in results[3] as List)
          (b as Map<String, dynamic>)['channel'] as String,
      };

      for (final s in results[2] as List) {
        final m = s as Map<String, dynamic>;
        final url = (m['url'] as String?)?.trim() ?? '';
        if (url.isEmpty || !seenUrls.add(url)) continue;

        final chId = m['channel'] as String?;
        final info = chId == null ? null : channelInfo[chId];
        if (chId != null && blocked.contains(chId)) continue;
        if (info != null) {
          if (info['is_nsfw'] == true) continue;
          if (info['closed'] != null) continue;
        }

        final labels = <String>[
          if (m['label'] is String) m['label'] as String,
          if (m['labels'] is List) ...(m['labels'] as List).cast<String>(),
        ];
        final title = (m['title'] as String?)?.trim();
        final name = (title != null && title.isNotEmpty)
            ? title
            : (info?['name'] as String?) ?? chId ?? 'Unknown';
        var country = (info?['country'] as String?)?.toUpperCase() ?? '';
        if (country.isEmpty && chId != null && chId.contains('.')) {
          // Channel ids look like "BBCOne.uk" - the suffix is the country.
          country = chId.split('.').last.split('@').first.toUpperCase();
        }
        final cats = ((info?['categories'] as List?) ?? const [])
            .whereType<String>()
            .where(kCategories.contains)
            .toList();

        candidates.add(Channel(
          name: name,
          countryCode: country.isEmpty ? 'XX' : country,
          url: url,
          referrer: m['referrer'] as String?,
          userAgent: m['user_agent'] as String?,
          quality: m['quality'] as String?,
          geoBlocked: labels.any((l) => l.toLowerCase().contains('geo')),
          notAlways: labels.any((l) => l.contains('24/7')),
          source: 'iptv-org',
          categories: cats,
          logo: chId == null ? null : logos[chId],
        ));
      }
      sourcesOk++;
    } catch (_) {
      // Continue with the other source.
    }
    if (_cancelled) return _db([]);

    // ---- 2. Free-TV/IPTV (curated, smaller) ----
    try {
      onProgress(const ScanProgress(message: 'Downloading Free-TV list...'));
      final text = await _getText(Sources.freeTv);
      for (final c in _parseFreeTv(text)) {
        if (seenUrls.add(c.url)) candidates.add(c);
      }
      sourcesOk++;
    } catch (_) {
      // Ignore - iptv-org alone is fine.
    }

    if (sourcesOk == 0) {
      throw Exception('Could not download any channel list. '
          'Please check your internet connection.');
    }
    if (_cancelled) return _db([]);

    // ---- 3. Read in the complete list (no test - use "Test" afterwards) ----
    // Counted up in steps, like the channel search of a TV.
    final recent = <Channel>[];
    var vpn = 0;
    const step = 250;
    for (var i = 0; i < candidates.length; i += step) {
      final end = (i + step).clamp(0, candidates.length);
      for (var j = i; j < end; j++) {
        if (candidates[j].needsVpn) vpn++;
      }
      recent
        ..clear()
        ..addAll(candidates.sublist((end - 8).clamp(0, end), end).reversed);
      onProgress(ScanProgress(
        phase: ScanPhase.checking,
        message: 'Reading in all channels...',
        total: candidates.length,
        checked: end,
        found: end,
        vpn: vpn,
        recent: List.unmodifiable(recent),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    onProgress(ScanProgress(
      phase: ScanPhase.done,
      message: 'Complete list read in: ${candidates.length} channels. '
          'Use "Test" to keep only working channels.',
      total: candidates.length,
      checked: candidates.length,
      found: candidates.length,
      vpn: vpn,
      recent: List.unmodifiable(recent),
    ));
    return _db(candidates);
  }

  // ===================================================================
  // Test: check the channels of the current list
  // ===================================================================

  /// Tests [channels]. Streams that do not answer are left out.
  /// [keepUrls] are kept without testing (e.g. the channel you are watching).
  /// If the test is stopped, untested channels are kept.
  Future<ChannelDb> testExisting(
    List<Channel> channels,
    Map<String, String> names,
    void Function(ScanProgress) onProgress, {
    Set<String> keepUrls = const {},
  }) async {
    countryNames.addAll(names);
    final tested = <String>{};
    final found = await _testAll(channels, onProgress, 'Testing channels',
        keepUrls: keepUrls, testedUrls: tested);
    if (_cancelled) {
      // Keep everything that was not tested yet.
      final foundUrls = {for (final c in found) c.url};
      for (final c in channels) {
        if (!tested.contains(c.url) && !foundUrls.contains(c.url)) found.add(c);
      }
    }
    return _db(found);
  }

  // ===================================================================

  ChannelDb _db(List<Channel> channels) => ChannelDb(
        channels: channels,
        countryNames: Map.of(countryNames),
        updated: DateTime.now(),
      );

  Future<List<Channel>> _testAll(
    List<Channel> candidates,
    void Function(ScanProgress) onProgress,
    String label, {
    Set<String> keepUrls = const {},
    Set<String>? testedUrls,
  }) async {
    final timing = _Timing.of(mode);
    final modeText = mode == TestMode.quick ? 'quick' : 'intensive';
    final found = <Channel>[];
    final recent = <Channel>[];
    var checked = 0;
    var vpnCount = 0;
    var next = 0;
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

    ScanProgress snapshot(ScanPhase phase, String msg) => ScanProgress(
          phase: phase,
          message: msg,
          total: candidates.length,
          checked: checked,
          found: found.length,
          vpn: vpnCount,
          recent: List.unmodifiable(recent),
        );

    void emit({bool force = false}) {
      final now = DateTime.now();
      if (!force && now.difference(lastEmit).inMilliseconds < 100) return;
      lastEmit = now;
      onProgress(snapshot(ScanPhase.checking, '$label ($modeText test)...'));
    }

    final client = HttpClient()
      ..connectionTimeout = timing.connect
      ..idleTimeout = const Duration(seconds: 2);

    Future<void> worker() async {
      while (!_cancelled) {
        final i = next++;
        if (i >= candidates.length) return;
        final c = candidates[i];
        final r = keepUrls.contains(c.url)
            ? (c.vpnLikely ? _Result.vpn : _Result.ok)
            : await _check(client, c, timing);
        checked++;
        testedUrls?.add(c.url);
        if (r != _Result.dead) {
          final ch = c.copyWith(vpnLikely: r == _Result.vpn);
          found.add(ch);
          if (ch.needsVpn) vpnCount++;
          recent.insert(0, ch);
          if (recent.length > 8) recent.removeLast();
        }
        emit();
      }
    }

    emit(force: true);
    await Future.wait(List.generate(timing.parallel, (_) => worker()));
    client.close(force: true);

    onProgress(snapshot(ScanPhase.done,
        _cancelled ? 'Stopped. Results so far are kept.' : 'Finished.'));
    return found;
  }

  /// Opens the stream and waits for the first bytes.
  Future<_Result> _check(HttpClient client, Channel c, _Timing t) async {
    HttpClientRequest? req;
    try {
      final uri = Uri.parse(c.url);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        // rtmp/rtsp etc. cannot be tested with HTTP - let the player try.
        return _Result.ok;
      }
      req = await client.getUrl(uri).timeout(t.connect);
      req.headers.set(HttpHeaders.userAgentHeader,
          (c.userAgent?.isNotEmpty ?? false) ? c.userAgent! : _defaultUserAgent);
      if (c.referrer?.isNotEmpty ?? false) {
        req.headers.set('Referer', c.referrer!);
      }
      final res = await req.close().timeout(t.response);
      final code = res.statusCode;
      if (code == 401 || code == 403 || code == 451) {
        unawaited(res.drain<void>().catchError((_) {}));
        return _Result.vpn;
      }
      if (code < 200 || code >= 400) {
        unawaited(res.drain<void>().catchError((_) {}));
        return _Result.dead;
      }
      // Some data must arrive, otherwise the stream is dead.
      final first = await res.first.timeout(t.data);
      return first.isEmpty ? _Result.dead : _Result.ok;
    } catch (_) {
      req?.abort();
      return _Result.dead;
    }
  }

  static Future<dynamic> _getJson(String url) async {
    final text = await _getText(url);
    return Isolate.run(() => jsonDecode(text));
  }

  static Future<String> _getText(String url) async {
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  /// Parses the Free-TV M3U playlist.
  /// Name markers (Free-TV legend): Ⓖ = GeoIP-blocked, Ⓢ = not HD,
  /// Ⓨ = YouTube. YouTube/Twitch/Dailymotion entries are skipped
  /// (they need extra tools to play).
  static List<Channel> _parseFreeTv(String text) {
    final out = <Channel>[];
    String? info;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.startsWith('#EXTINF')) {
        info = line;
        continue;
      }
      if (line.isEmpty || line.startsWith('#') || info == null) continue;
      final url = line;
      final inf = info;
      info = null;

      final lower = url.toLowerCase();
      if (lower.contains('youtube.com') ||
          lower.contains('youtu.be') ||
          lower.contains('twitch.tv') ||
          lower.contains('dailymotion.com')) {
        continue;
      }

      final q = inf.lastIndexOf('",');
      var name =
          q >= 0 ? inf.substring(q + 2) : inf.substring(inf.lastIndexOf(',') + 1);
      final geo = name.contains('Ⓖ');
      final sd = name.contains('Ⓢ');
      name = name.replaceAll(RegExp('[ⓎⓉⒹⓈⒼ]'), '').trim();
      if (name.isEmpty) name = _attr(inf, 'tvg-name') ?? 'Unknown';

      final country = (_attr(inf, 'tvg-country') ?? '').toUpperCase();
      out.add(Channel(
        name: name,
        countryCode: country.length == 2 ? country : 'XX',
        url: url,
        quality: sd ? 'SD' : null,
        geoBlocked: geo,
        source: 'Free-TV',
      ));
    }
    return out;
  }

  static String? _attr(String info, String key) {
    final m = RegExp('$key="([^"]*)"').firstMatch(info);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}
