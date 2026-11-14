/// Data models for SlaxxTV.
library;

/// Country code of the user's own feeds (--own--).
const kOwnCountry = 'OWN';

/// Country code of YouTube live channels.
const kYouTubeCountry = 'YT';

/// True for YouTube links (watch, embed, live, channel pages).
bool isYouTubeUrl(String url) {
  final u = url.toLowerCase();
  return u.contains('youtube.com/') ||
      u.contains('youtube-nocookie.com/') ||
      u.contains('youtu.be/');
}

/// Video id from a YouTube link, or null (e.g. for channel pages).
String? youTubeVideoId(String url) {
  final m = RegExp(
          r'(?:youtu\.be/|/embed/|/live/|/shorts/|[?&]v=)([A-Za-z0-9_-]{11})')
      .firstMatch(url);
  return m?.group(1);
}

/// One playable TV stream.
class Channel {
  const Channel({
    required this.name,
    required this.countryCode,
    required this.url,
    this.referrer,
    this.userAgent,
    this.quality,
    this.geoBlocked = false,
    this.notAlways = false,
    this.vpnLikely = false,
    this.source = '',
    this.categories = const [],
    this.logo,
    this.channelId,
  });

  final String name;

  /// ISO 3166-1 alpha-2 code in upper case ("DE", "UK", ...). "XX" = unknown.
  final String countryCode;
  final String url;
  final String? referrer;
  final String? userAgent;
  final String? quality;

  /// Marked as geo-blocked by the channel list.
  final bool geoBlocked;

  /// Marked as "Not 24/7" by the channel list.
  final bool notAlways;

  /// The scan got "access denied" (HTTP 401/403/451) - typical for geo-blocking.
  final bool vpnLikely;

  /// Which list the channel came from ("iptv-org" or "Free-TV").
  final String source;

  /// iptv-org categories, e.g. "movies", "series", "documentary", "news".
  final List<String> categories;

  /// Channel logo URL (iptv-org), if known.
  final String? logo;

  /// Channel id (iptv-org id like "DasErste.de" or tvg-id), used for the EPG.
  final String? channelId;

  /// True if you most likely need a VPN into [countryCode] to watch it.
  bool get needsVpn => geoBlocked || vpnLikely;

  Map<String, String> get httpHeaders => {
        if (referrer != null && referrer!.isNotEmpty) 'Referer': referrer!,
        if (userAgent != null && userAgent!.isNotEmpty) 'User-Agent': userAgent!,
      };

  Channel copyWith({bool? vpnLikely}) => Channel(
        name: name,
        countryCode: countryCode,
        url: url,
        referrer: referrer,
        userAgent: userAgent,
        quality: quality,
        geoBlocked: geoBlocked,
        notAlways: notAlways,
        vpnLikely: vpnLikely ?? this.vpnLikely,
        source: source,
        categories: categories,
        logo: logo,
        channelId: channelId,
      );

  /// Keeps this channel, but takes over logo, categories and flags of a
  /// duplicate of the same stream.
  Channel mergedWith(Channel o) => Channel(
        name: name,
        countryCode: countryCode == 'XX' ? o.countryCode : countryCode,
        url: url,
        referrer: referrer ?? o.referrer,
        userAgent: userAgent ?? o.userAgent,
        quality: quality ?? o.quality,
        geoBlocked: geoBlocked || o.geoBlocked,
        notAlways: notAlways,
        vpnLikely: vpnLikely,
        source: source,
        categories: {...categories, ...o.categories}.toList(),
        logo: logo ?? o.logo,
        channelId: channelId ?? o.channelId,
      );

  Map<String, dynamic> toJson() => {
        'n': name,
        'c': countryCode,
        'u': url,
        if (referrer != null) 'r': referrer,
        if (userAgent != null) 'a': userAgent,
        if (quality != null) 'q': quality,
        if (geoBlocked) 'g': true,
        if (notAlways) 'na': true,
        if (vpnLikely) 'v': true,
        's': source,
        if (categories.isNotEmpty) 'k': categories,
        if (logo != null) 'l': logo,
        if (channelId != null) 'i': channelId,
      };

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        name: j['n'] as String,
        countryCode: j['c'] as String,
        url: j['u'] as String,
        referrer: j['r'] as String?,
        userAgent: j['a'] as String?,
        quality: j['q'] as String?,
        geoBlocked: j['g'] == true,
        notAlways: j['na'] == true,
        vpnLikely: j['v'] == true,
        source: (j['s'] as String?) ?? '',
        categories: (j['k'] as List?)?.cast<String>() ?? const [],
        logo: j['l'] as String?,
        channelId: j['i'] as String?,
      );
}

/// All channels of one country, used by the channel list.
class CountryGroup {
  CountryGroup(this.code, this.name, this.channels);
  final String code;
  final String name;
  final List<Channel> channels;
}

/// The saved channel database.
class ChannelDb {
  ChannelDb({
    required this.channels,
    required this.countryNames,
    required this.updated,
  });

  final List<Channel> channels;

  /// Country code -> English country name.
  final Map<String, String> countryNames;
  final DateTime updated;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'updated': updated.toIso8601String(),
        'countries': countryNames,
        'channels': channels.map((c) => c.toJson()).toList(),
      };

  factory ChannelDb.fromJson(Map<String, dynamic> j) => ChannelDb(
        channels: (j['channels'] as List)
            .map((e) => Channel.fromJson(e as Map<String, dynamic>))
            .toList(),
        countryNames: (j['countries'] as Map)
            .map((k, v) => MapEntry(k as String, v as String)),
        updated: DateTime.tryParse(j['updated'] as String? ?? '') ??
            DateTime.now(),
      );
}

// =====================================================================
// Clean up: remove channels that point to the same stream
// =====================================================================

/// Host + path of a stream URL, lower-case host, without trailing "/"
/// and without default ports. "http" and "https" count as the same.
String streamPath(String url) {
  try {
    final u = Uri.parse(url.trim());
    var path = u.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final port = (u.hasPort && u.port != 80 && u.port != 443) ? ':${u.port}' : '';
    return '${u.host.toLowerCase()}$port$path';
  } catch (_) {
    return url.trim().toLowerCase();
  }
}

/// Result of [dedupeChannels].
class DedupeResult {
  DedupeResult(this.channels, this.replaced);

  /// The list without duplicates (order kept, first one wins).
  final List<Channel> channels;

  /// URL of a removed duplicate -> URL of the channel that was kept.
  final Map<String, String> replaced;

  int get removed => replaced.length;
}

/// Two channels are the same stream when
///  * host + path + query of their URLs are equal, or
///  * host + path are equal and they have the same name
///    (e.g. the same stream with different tracking parameters).
/// The first one is kept; missing logo/categories are taken over.
DedupeResult dedupeChannels(List<Channel> list) {
  final byKey = <String, int>{};
  final out = <Channel>[];
  final replaced = <String, String>{};
  for (final c in list) {
    final path = streamPath(c.url);
    final query = Uri.tryParse(c.url.trim())?.query ?? '';
    final k1 = '$path?$query';
    final k2 = '$path#${c.name.trim().toLowerCase()}';
    final hit = byKey[k1] ?? byKey[k2];
    if (hit != null) {
      final kept = out[hit];
      if (kept.url != c.url) replaced[c.url] = kept.url;
      out[hit] = kept.mergedWith(c);
      continue;
    }
    byKey[k1] = out.length;
    byKey[k2] = out.length;
    out.add(c);
  }
  return DedupeResult(out, replaced);
}
