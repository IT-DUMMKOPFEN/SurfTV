import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// One TV programme (EPG entry).
class Programme {
  const Programme(this.start, this.stop, this.title, [this.desc]);

  final DateTime start;
  final DateTime stop;
  final String title;
  final String? desc;

  bool isOn(DateTime t) => !t.isBefore(start) && t.isBefore(stop);

  /// 0..1 - how much of the programme has run.
  double progress(DateTime t) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (t.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        's': start.millisecondsSinceEpoch,
        'e': stop.millisecondsSinceEpoch,
        't': title,
        if (desc != null) 'd': desc,
      };

  factory Programme.fromJson(Map<String, dynamic> j) => Programme(
        DateTime.fromMillisecondsSinceEpoch(j['s'] as int),
        DateTime.fromMillisecondsSinceEpoch(j['e'] as int),
        j['t'] as String,
        j['d'] as String?,
      );
}

/// What we know about a favorite when matching it to the EPG file.
class _Fav {
  _Fav(this.url, this.names);
  final String url;
  final List<String> names; // normalized
}

/// Program guide (EPG) for the channels in My Channels.
///
/// Source: epgshare01 - one free XMLTV file per country
/// (epg_ripper_<CC>1.xml.gz, about 4 days ahead). Channels are matched by
/// channel id and name.
class EpgService {
  static String countryUrl(String cc, int n) =>
      'https://epgshare01.online/epgshare01/epg_ripper_${cc.toUpperCase()}$n.xml.gz';

  /// Loads the guide for [favorites]. Returns channel URL -> programmes.
  static Future<Map<String, List<Programme>>> fetch(
    List<Channel> favorites,
    void Function(String status) onStatus,
  ) async {
    final result = <String, List<Programme>>{};
    final byCountry = <String, List<Channel>>{};
    for (final c in favorites) {
      if (c.countryCode == 'XX') continue;
      byCountry.putIfAbsent(c.countryCode, () => []).add(c);
    }
    for (final e in byCountry.entries) {
      final cc = e.key;
      var open = e.value;
      // Most countries have one file; some (e.g. US) have more.
      for (var n = 1; n <= 3 && open.isNotEmpty; n++) {
        onStatus('Loading guide for $cc ($n)...');
        String xml;
        try {
          xml = await _download(countryUrl(cc, n));
        } catch (_) {
          break; // no (more) file for this country
        }
        onStatus('Reading guide for $cc...');
        final favs = [
          for (final c in open) _Fav(c.url, _favNames(c)),
        ];
        final found = await Isolate.run(() => _parse(xml, favs));
        result.addAll(found);
        open = open.where((c) => !found.containsKey(c.url)).toList();
      }
    }
    onStatus('Guide loaded for ${result.length} of ${favorites.length} channels.');
    return result;
  }

  static Future<String> _download(String url) async {
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    List<int> bytes = res.bodyBytes;
    // .gz file (unless the server already unpacked it).
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = gzip.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Normalized names a favorite may have in the XMLTV file.
  static List<String> _favNames(Channel c) {
    final names = <String>{normalizeName(c.name)};
    final id = c.channelId;
    if (id != null && id.isNotEmpty) {
      names.add(normalizeName(id.split('@').first.split('.').first));
      names.add(id.toLowerCase());
    }
    names.removeWhere((n) => n.isEmpty);
    return names.toList();
  }

  /// "Das Erste HD (720p)" -> "daserste"
  static String normalizeName(String s) {
    var t = s.toLowerCase();
    t = t.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
    t = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (var i = 0; i < 3; i++) {
      final before = t;
      for (final suffix in ['fhd', 'uhd', 'hd', '4k', 'sd', 'hevc']) {
        if (t.length > suffix.length + 2 && t.endsWith(suffix)) {
          t = t.substring(0, t.length - suffix.length);
        }
      }
      if (t == before) break;
    }
    return t;
  }

  // ---------------------------------------------------------------------
  // XMLTV parsing (runs in a background isolate)
  // ---------------------------------------------------------------------

  static Map<String, List<Programme>> _parse(String xml, List<_Fav> favs) {
    // 1. channels: id -> normalized names
    final chanRe = RegExp(r'<channel\s+id="([^"]*)"[^>]*>(.*?)</channel>',
        dotAll: true);
    final nameRe = RegExp(r'<display-name[^>]*>(.*?)</display-name>',
        dotAll: true);
    final channels = <String, Set<String>>{};
    for (final m in chanRe.allMatches(xml)) {
      final id = _unescape(m.group(1)!);
      final names = <String>{
        id.toLowerCase(),
        normalizeName(id.split('.').first),
        normalizeName(id),
      };
      for (final n in nameRe.allMatches(m.group(2)!)) {
        names.add(normalizeName(_unescape(n.group(1)!)));
      }
      names.removeWhere((n) => n.isEmpty);
      channels[id] = names;
    }

    // 2. match favorites (exact first, then "starts with")
    final idToUrl = <String, String>{};
    for (final f in favs) {
      String? hit;
      for (final e in channels.entries) {
        if (f.names.any(e.value.contains)) {
          hit = e.key;
          break;
        }
      }
      if (hit == null) {
        for (final e in channels.entries) {
          final ok = f.names.any((fn) =>
              fn.length >= 4 &&
              e.value.any((cn) =>
                  cn.length >= 4 && (cn.startsWith(fn) || fn.startsWith(cn))));
          if (ok) {
            hit = e.key;
            break;
          }
        }
      }
      if (hit != null && !idToUrl.containsKey(hit)) idToUrl[hit] = f.url;
    }
    if (idToUrl.isEmpty) return {};

    // 3. programmes of the matched channels, from 3 hours ago to 2 days ahead
    final now = DateTime.now();
    final from = now.subtract(const Duration(hours: 3));
    final to = now.add(const Duration(days: 2));
    final progRe = RegExp(r'<programme\s+([^>]*)>(.*?)</programme>',
        dotAll: true);
    final titleRe = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true);
    final descRe = RegExp(r'<desc[^>]*>(.*?)</desc>', dotAll: true);
    final out = <String, List<Programme>>{};
    for (final m in progRe.allMatches(xml)) {
      final attrs = m.group(1)!;
      final ch = _attr(attrs, 'channel');
      final url = ch == null ? null : idToUrl[_unescape(ch)];
      if (url == null) continue;
      final start = _time(_attr(attrs, 'start'));
      final stop = _time(_attr(attrs, 'stop'));
      if (start == null || stop == null) continue;
      if (stop.isBefore(from) || start.isAfter(to)) continue;
      final body = m.group(2)!;
      final title = titleRe.firstMatch(body)?.group(1);
      if (title == null) continue;
      var desc = descRe.firstMatch(body)?.group(1);
      if (desc != null) {
        desc = _unescape(desc).trim();
        if (desc.length > 400) desc = '${desc.substring(0, 400)}...';
      }
      out.putIfAbsent(url, () => []).add(
          Programme(start, stop, _unescape(title).trim(), desc));
    }
    for (final l in out.values) {
      l.sort((a, b) => a.start.compareTo(b.start));
    }
    return out;
  }

  static String? _attr(String attrs, String key) =>
      RegExp('$key="([^"]*)"').firstMatch(attrs)?.group(1);

  /// "20261113201500 +0100" -> local DateTime
  static DateTime? _time(String? s) {
    if (s == null || s.length < 14) return null;
    try {
      final y = int.parse(s.substring(0, 4));
      final mo = int.parse(s.substring(4, 6));
      final d = int.parse(s.substring(6, 8));
      final h = int.parse(s.substring(8, 10));
      final mi = int.parse(s.substring(10, 12));
      final se = int.parse(s.substring(12, 14));
      var t = DateTime.utc(y, mo, d, h, mi, se);
      final tz = RegExp(r'([+-])(\d{2})(\d{2})').firstMatch(s.substring(14));
      if (tz != null) {
        final off = Duration(
            hours: int.parse(tz.group(2)!), minutes: int.parse(tz.group(3)!));
        t = tz.group(1) == '+' ? t.subtract(off) : t.add(off);
      }
      return t.toLocal();
    } catch (_) {
      return null;
    }
  }

  static String _unescape(String s) => s
      .replaceAll('<![CDATA[', '')
      .replaceAll(']]>', '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAll('&amp;', '&');

  // ---------------------------------------------------------------------
  // Cache
  // ---------------------------------------------------------------------

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}epg.json');
  }

  static Future<void> save(
      Map<String, List<Programme>> data, DateTime fetched) async {
    final f = await _file();
    await f.writeAsString(jsonEncode({
      'fetched': fetched.toIso8601String(),
      'data': data.map((k, v) => MapEntry(k, v.map((p) => p.toJson()).toList())),
    }));
  }

  static Future<(Map<String, List<Programme>>, DateTime)?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final data = (j['data'] as Map).map((k, v) => MapEntry(
          k as String,
          (v as List)
              .map((e) => Programme.fromJson(e as Map<String, dynamic>))
              .toList()));
      return (data, DateTime.parse(j['fetched'] as String));
    } catch (_) {
      return null;
    }
  }
}
