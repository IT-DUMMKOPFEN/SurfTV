import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Saves and loads the channel database as JSON in the app support folder.
class Storage {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}channels.json');
  }

  static Future<ChannelDb?> loadDb() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      return await Isolate.run(
          () => ChannelDb.fromJson(jsonDecode(text) as Map<String, dynamic>));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDb(ChannelDb db) async {
    final f = await _file();
    final text = jsonEncode(db.toJson());
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
  }
}
