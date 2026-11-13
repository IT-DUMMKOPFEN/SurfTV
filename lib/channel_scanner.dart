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

enum ScanPhase { downloading, checking, done }

/// Snapshot of the running channel search, shown in the scan dialog.
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
  final int found;
  final int vpn;

  /// The last channels found, newest first.
  final List<Channel> recent;
}

enum _Result { ok, vpn, dead }

/// Downloads the public channel lists and tests every stream,
/// like the channel search of a real TV.
class ChannelScanner {
  static const _concurrency = 32;
  static const _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  /// Country code -> name, filled while downloading.
  final Map<String, String> countryNames = {};

  bool _cancelled = false;
  bool get cancelled => _cancelled;

  /// Stops the search. Channels found so far are kept.
  void cancel() => _cancelled = true;

  Future<ChannelDb> run(void Function(ScanProgress) onProgress) async {
    onProgress(const ScanProgress());

    final candidates = <Channel>[];
    final seenUrls = <String>{};
    var sourcesOk = 0;

    // ---- 1. iptv-org (main source, has the geo-blocked label) ----
    try {
      onProgress(const ScanProgress(message: 'Downloading iptv-org lists...'));
      final results = await Future.wait([
        _getJson('${Sources.iptvOrgApi}/countries.json'),
        _getJson('${Sources.iptvOrgApi}/channels.json'),
        _getJson('${Sources.iptvOrgApi}/streams.json'),
        _getJson('${Sources.iptvOrgApi}/blocklist.json'),
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
        ));
      }
      sourcesOk++;
    } catch (_) {
      // Continue with the other source.
    }
    if (_cancelled) return _empty(countryNames);

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
    if (_cancelled) return _empty(countryNames);

    // ---- 3. Test every stream ----
    final found = <Channel>[];
    final recent = <Channel>[];
    var checked = 0;
    var vpnCount = 0;
    var next = 0;
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

    void emit({bool force = false}) {
      final now = DateTime.now();
      if (!force && now.difference(lastEmit).inMilliseconds < 80) return;
      lastEmit = now;
      onProgress(ScanProgress(
        phase: ScanPhase.checking,
        message: 'Searching channels...',
        total: candidates.length,
        checked: checked,
        found: found.length,
        vpn: vpnCount,
        recent: List.unmodifiable(recent),
      ));
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..idleTimeout = const Duration(seconds: 2);

    Future<void> worker() async {
      while (!_cancelled) {
        final i = next++;
        if (i >= candidates.length) return;
        final c = candidates[i];
        final r = await _check(client, c);
        checked++;
        if (r != _Result.dead) {
          final ch = r == _Result.vpn ? c.copyWith(vpnLikely: true) : c;
          found.add(ch);
          if (ch.needsVpn) vpnCount++;
          recent.insert(0, ch);
          if (recent.length > 8) recent.removeLast();
          emit(force: found.length % 25 == 1);
        } else {
          emit();
        }
      }
    }

    emit(force: true);
    await Future.wait(List.generate(_concurrency, (_) => worker()));
    client.close(force: true);

    onProgress(ScanProgress(
      phase: ScanPhase.done,
      message: _cancelled ? 'Search stopped.' : 'Search finished.',
      total: candidates.length,
      checked: checked,
      found: found.length,
      vpn: vpnCount,
      recent: List.unmodifiable(recent),
    ));

    return ChannelDb(
      channels: found,
      countryNames: Map.of(countryNames),
      updated: DateTime.now(),
    );
  }

  ChannelDb _empty(Map<String, String> names) =>
      ChannelDb(channels: [], countryNames: names, updated: DateTime.now());

  /// Opens the stream and looks at the first bytes.
  Future<_Result> _check(HttpClient client, Channel c) async {
    HttpClientRequest? req;
    try {
      final uri = Uri.parse(c.url);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        // rtmp/rtsp etc. cannot be tested with HTTP - let the player try.
        return _Result.ok;
      }
      req = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.userAgentHeader,
          (c.userAgent?.isNotEmpty ?? false) ? c.userAgent! : _defaultUserAgent);
      if (c.referrer?.isNotEmpty ?? false) {
        req.headers.set('Referer', c.referrer!);
      }
      final res = await req.close().timeout(const Duration(seconds: 8));
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
      final first = await res.first.timeout(const Duration(seconds: 6));
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
