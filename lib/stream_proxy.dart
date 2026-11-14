import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Compatibility mode: a small local HTTP server that loads a stream with
/// the app's own network stack (like a web browser does) and passes it on
/// to the player.
///
/// Helps with streams that play in a browser but not in the player, e.g.
/// "tcp: ffurl_read returned ..." errors: other TLS / IPv4-IPv6 handling,
/// cookies set on redirects, servers that dislike the player's requests.
/// HLS playlists are rewritten so that all variants and segments also go
/// through this server.
class StreamProxy {
  StreamProxy._();
  static final instance = StreamProxy._();

  static const defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  HttpServer? _server;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 20)
    ..autoUncompress = true;

  /// Cookies per host (also those set on redirects).
  final Map<String, Map<String, String>> _cookies = {};

  /// Address for the player that plays [target] through the proxy.
  Future<String> url(String target, {String? referer, String? userAgent}) async {
    await _start();
    return _proxied(target, referer, userAgent);
  }

  String _proxied(String target, String? referer, String? userAgent) => Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: _server!.port,
        path: '/s',
        queryParameters: {
          'u': target,
          if (referer != null && referer.isNotEmpty) 'r': referer,
          if (userAgent != null && userAgent.isNotEmpty) 'a': userAgent,
        },
      ).toString();

  Future<void> _start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final q = req.uri.queryParameters;
      final target = q['u'];
      if (target == null) {
        res.statusCode = HttpStatus.badRequest;
        await res.close();
        return;
      }
      final referer = q['r'];
      final ua = q['a'];

      final (up, finalUri) = await _fetch(Uri.parse(target), referer, ua,
          range: req.headers.value(HttpHeaders.rangeHeader));

      final mime = up.headers.contentType?.mimeType.toLowerCase() ?? '';
      final path = finalUri.path.toLowerCase();
      final isPlaylist = mime.contains('mpegurl') ||
          path.endsWith('.m3u8') ||
          path.endsWith('.m3u');

      if (isPlaylist && up.statusCode < 400) {
        final body = await utf8.decoder.bind(up).join();
        res.statusCode = up.statusCode;
        res.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        res.write(body.trimLeft().startsWith('#EXTM3U')
            ? _rewrite(body, finalUri, referer, ua)
            : body);
        await res.close();
        return;
      }

      res.statusCode = up.statusCode;
      final ct = up.headers.value(HttpHeaders.contentTypeHeader);
      if (ct != null) res.headers.set(HttpHeaders.contentTypeHeader, ct);
      for (final h in [
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final v = up.headers.value(h);
        if (v != null) res.headers.set(h, v);
      }
      // Length only when the body was not unpacked on the way.
      if (up.compressionState == HttpClientResponseCompressionState.notCompressed &&
          up.contentLength >= 0) {
        res.contentLength = up.contentLength;
      }
      await up.pipe(res);
    } catch (_) {
      try {
        res.statusCode = HttpStatus.badGateway;
        await res.close();
      } catch (_) {}
    }
  }

  /// GET with redirects followed by hand, so cookies of every step are kept.
  Future<(HttpClientResponse, Uri)> _fetch(
      Uri uri, String? referer, String? ua,
      {String? range}) async {
    var current = uri;
    for (var i = 0; i < 8; i++) {
      final rq = await _client.getUrl(current);
      rq.followRedirects = false;
      rq.headers.set(HttpHeaders.userAgentHeader, ua ?? defaultUserAgent);
      rq.headers.set(HttpHeaders.acceptHeader, '*/*');
      if (referer != null && referer.isNotEmpty) {
        rq.headers.set('Referer', referer);
        final r = Uri.tryParse(referer);
        if (r != null && r.hasScheme) {
          rq.headers.set('Origin', '${r.scheme}://${r.host}');
        }
      }
      if (range != null) rq.headers.set(HttpHeaders.rangeHeader, range);
      final jar = _cookies[current.host];
      if (jar != null && jar.isNotEmpty) {
        rq.headers.set(HttpHeaders.cookieHeader,
            jar.entries.map((e) => '${e.key}=${e.value}').join('; '));
      }
      final rs = await rq.close().timeout(const Duration(seconds: 20));
      try {
        for (final c in rs.cookies) {
          _cookies.putIfAbsent(current.host, () => {})[c.name] = c.value;
        }
      } catch (_) {}
      final loc = rs.headers.value(HttpHeaders.locationHeader);
      if (rs.isRedirect && loc != null) {
        await rs.drain<void>();
        current = current.resolve(loc);
        continue;
      }
      return (rs, current);
    }
    throw const HttpException('Too many redirects');
  }

  /// All addresses in an HLS playlist (variants, segments, keys, audio
  /// tracks) are made absolute and sent through the proxy.
  String _rewrite(String body, Uri base, String? referer, String? ua) {
    String prox(String u) =>
        _proxied(base.resolve(u.trim()).toString(), referer, ua);
    final uriAttr = RegExp(r'URI="([^"]+)"');
    final out = StringBuffer();
    for (final line in const LineSplitter().convert(body)) {
      final t = line.trim();
      if (t.isEmpty) {
        out.writeln(line);
      } else if (t.startsWith('#')) {
        out.writeln(t.replaceAllMapped(
            uriAttr, (m) => 'URI="${prox(m.group(1)!)}"'));
      } else {
        out.writeln(prox(t));
      }
    }
    return out.toString();
  }
}
