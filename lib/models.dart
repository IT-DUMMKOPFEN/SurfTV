/// Data models for SurfTV.
library;

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
