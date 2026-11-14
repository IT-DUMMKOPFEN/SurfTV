// Plays a real HLS stream through the compatibility mode and lets ffprobe
// (the same ffmpeg the player uses) read it. Needs internet and ffprobe.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:surftv/stream_proxy.dart';

void main() {
  test('HLS through the compatibility mode', () async {
    const src = 'https://daserste-live.ard-mcdn.de/daserste/live/hls/de/master.m3u8';
    final url = await StreamProxy.instance.url(src);
    final master = await http.get(Uri.parse(url));
    print('master: HTTP ${master.statusCode}');
    print(master.body.split('\n').take(8).join('\n'));
    final r = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries', 'stream=codec_type,width,height',
      '-of', 'compact', url,
    ]).timeout(const Duration(seconds: 60));
    print('ffprobe exit ${r.exitCode}\n${r.stdout}\n${r.stderr}');
    expect(r.exitCode, 0);
    expect((r.stdout as String).contains('codec_type=video'), true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
