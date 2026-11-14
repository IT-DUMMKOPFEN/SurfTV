import 'package:flutter/material.dart';

import '../models.dart';

/// Country flag as an image (emoji flags do not work on Windows).
/// Flags are loaded from flagcdn.com and cached by Flutter.
class FlagIcon extends StatelessWidget {
  const FlagIcon(this.code, {super.key, this.width = 24});

  final String code;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 0.7;
    // Own feeds: small SlaxxTV logo. YouTube: YouTube symbol.
    if (code == kOwnCountry || code == kYouTubeCountry) {
      return SizedBox(
        width: width,
        height: h,
        child: Image.asset(
          code == kOwnCountry ? 'assets/own.png' : 'assets/youtube.png',
          fit: BoxFit.contain,
        ),
      );
    }
    if (code.isEmpty || code == 'XX') {
      return SizedBox(
        width: width,
        height: h,
        child: Icon(Icons.public, size: h),
      );
    }
    // iptv-org uses "UK" for the United Kingdom, flagcdn uses "gb".
    final c = code.toUpperCase() == 'UK' ? 'gb' : code.toLowerCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Image.network(
        'https://flagcdn.com/w80/$c.png',
        width: width,
        height: h,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => SizedBox(
          width: width,
          height: h,
          child: FittedBox(child: Text(code.toUpperCase())),
        ),
      ),
    );
  }
}

/// Small orange "VPN" badge.
class VpnBadge extends StatelessWidget {
  const VpnBadge({super.key, this.countryName, this.large = false});

  final String? countryName;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final fs = large ? 13.0 : 10.0;
    return Tooltip(
      message: countryName == null
          ? 'Probably geo-blocked - VPN needed'
          : 'Probably geo-blocked - VPN to $countryName needed',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 6 : 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.vpn_lock, size: fs + 2, color: Colors.black),
          const SizedBox(width: 2),
          Text('VPN',
              style: TextStyle(
                  fontSize: fs,
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
        ]),
      ),
    );
  }
}
