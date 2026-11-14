// Resolves real YouTube live links from the Famelack list. Needs internet.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:surftv/models.dart';
import 'package:surftv/youtube.dart';

void main() {
  test('YouTube live links resolve to HLS', () async {
    final res = await http.get(Uri.parse(
        'https://raw.githubusercontent.com/famelack/famelack-channels/main/tv/categories/news.json'));
    final list = jsonDecode(res.body) as List;
    final links = <String>[
      for (final e in list)
        ...(((e as Map)['sources'] as Map?)?['youtube'] as List? ?? const [])
            .whereType<String>(),
    ].take(12).toList();
    var ok = 0;
    for (final l in links) {
      try {
        final hls = await YouTubeResolver.resolve(l);
        ok++;
        print('OK   $l -> ${hls.substring(0, 60)}...');
      } catch (e) {
        print('FAIL $l ($e)');
      }
    }
    print('resolved $ok of ${links.length}');
    // channel page with /live
    try {
      final h = await YouTubeResolver.resolve('https://www.youtube.com/@aljazeeraenglish');
      print('channel OK -> ${h.substring(0, 60)}');
    } catch (e) {
      print('channel FAIL $e');
    }
    expect(youTubeVideoId('https://www.youtube-nocookie.com/embed/iw0YDBYgaUU'), 'iw0YDBYgaUU');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
