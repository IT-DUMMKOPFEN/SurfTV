import 'package:http/http.dart' as http;

import 'models.dart';

/// Finds the playable HLS address of a YouTube live stream.
///
/// Works with video links (watch?v=, /embed/, youtu.be, /live/ID) and with
/// channel links (youtube.com/@name, /channel/UC..., /c/...) - for those the
/// current live video of the channel is used.
class YouTubeResolver {
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.8',
    // Skips the cookie consent page in Europe.
    'Cookie': 'CONSENT=YES+1; SOCS=CAI',
  };

  /// Resolved addresses are valid for some hours - cache them for 1 hour.
  static final Map<String, (String, DateTime)> _cache = {};

  static Future<String> resolve(String url) async {
    final hit = _cache[url];
    if (hit != null && DateTime.now().difference(hit.$2).inMinutes < 60) {
      return hit.$1;
    }
    var id = youTubeVideoId(url);
    id ??= await _liveVideoOfChannel(url);
    if (id == null) {
      throw Exception('This YouTube channel is not live right now.');
    }
    final page = await _get('https://www.youtube.com/watch?v=$id');
    final m = RegExp(r'"hlsManifestUrl":"(https:[^"]+)"').firstMatch(page);
    if (m == null) {
      throw Exception('This YouTube video is not a live stream (or not live right now).');
    }
    final hls = m
        .group(1)!
        .replaceAll(r'&', '&')
        .replaceAll(r'\/', '/');
    _cache[url] = (hls, DateTime.now());
    return hls;
  }

  /// Video id of the live stream of a channel page.
  static Future<String?> _liveVideoOfChannel(String url) async {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.endsWith('/live')) u = '$u/live';
    final page = await _get(u);
    final canon = RegExp(
            r'<link rel="canonical" href="https://www\.youtube\.com/watch\?v=([A-Za-z0-9_-]{11})"')
        .firstMatch(page);
    if (canon != null) return canon.group(1);
    final vid = RegExp(r'"videoId":"([A-Za-z0-9_-]{11})"[^}]*"isLive":true')
        .firstMatch(page);
    return vid?.group(1);
  }

  static Future<String> _get(String url) async {
    final res = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('YouTube answered with HTTP ${res.statusCode}.');
    }
    return res.body;
  }
}
