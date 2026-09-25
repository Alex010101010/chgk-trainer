import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'handout_store.dart';

HandoutStore createHandoutStore(String baseUrl) => _FileHandoutStore(baseUrl);

/// Кэш на диске: скачанная раз картинка дальше показывается без сети.
/// Имя файла — id вопроса, содержимое по нему не меняется, поэтому кэш не
/// нужно ни проверять, ни сбрасывать.
class _FileHandoutStore implements HandoutStore {
  final String baseUrl;
  _FileHandoutStore(this.baseUrl);

  static const _timeout = Duration(seconds: 30);

  /// Одна загрузка на файл, даже если докачка и показ попросили одновременно.
  final _inFlight = <String, Future<ImageProvider>>{};

  @override
  Future<ImageProvider> resolve(String file) =>
      _inFlight.putIfAbsent(file, () => _resolve(file).whenComplete(() {
            _inFlight.remove(file);
          }));

  Future<ImageProvider> _resolve(String file) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/handouts');
    final cached = File('${dir.path}/$file');
    if (await cached.exists()) return FileImage(cached);

    final r = await http.get(Uri.parse('$baseUrl/$file')).timeout(_timeout);
    if (r.statusCode != 200) {
      throw HttpException('раздатка $file: HTTP ${r.statusCode}');
    }
    await dir.create(recursive: true);
    // Через временный файл: оборванная запись не должна остаться в кэше
    // «готовой» картинкой, которую потом никогда не перекачают.
    final tmp = File('${cached.path}.part');
    await tmp.writeAsBytes(r.bodyBytes, flush: true);
    await tmp.rename(cached.path);
    return FileImage(cached);
  }
}
