// Checks the program guide with the real epgshare01 file for Germany.
// Needs internet. Run: flutter test test/epg_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:surftv/epg.dart';
import 'package:surftv/models.dart';

void main() {
  test('EPG for German channels', () async {
    final favs = [
      const Channel(name: 'Das Erste', countryCode: 'DE', url: 'u1', channelId: 'DasErste.de'),
      const Channel(name: 'ZDF', countryCode: 'DE', url: 'u2', channelId: 'ZDF.de'),
      const Channel(name: 'arte', countryCode: 'DE', url: 'u3', channelId: 'ARTE.de'),
      const Channel(name: 'RTL', countryCode: 'DE', url: 'u4', channelId: 'RTL.de'),
      const Channel(name: 'ProSieben', countryCode: 'DE', url: 'u5'),
    ];
    final data = await EpgService.fetch(favs, (s) => print('status: $s'));
    final now = DateTime.now();
    for (final c in favs) {
      final list = data[c.url] ?? const [];
      final on = list.where((p) => p.isOn(now)).toList();
      print('${c.name}: ${list.length} programmes, now: '
          '${on.isEmpty ? '-' : '${on.first.title} (${on.first.start}-${on.first.stop})'}');
    }
    expect(data.length, greaterThanOrEqualTo(3));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
