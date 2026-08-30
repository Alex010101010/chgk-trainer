import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_updater.dart';
import 'ota_config.dart';

AppUpdater createAppUpdater() => IoAppUpdater();

class IoAppUpdater implements AppUpdater {
  Map<String, dynamic>? _manifest; // манифест доступного обновления

  @override
  Future<AppUpdateInfo> check() async {
    int currentBuild;
    try {
      final info = await PackageInfo.fromPlatform();
      currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (e) {
      return AppUpdateInfo(AppUpdateStatus.error,
          message: 'версия приложения: $e');
    }

    Map<String, dynamic> m;
    try {
      // cache-busting: редирект GitHub на latest кешируется CDN, и без метки
      // времени проверка может отдать вчерашний манифест.
      final ts = DateTime.now().millisecondsSinceEpoch;
      final resp = await http
          .get(Uri.parse('$kAppManifestUrl?ts=$ts'))
          .timeout(kOtaTimeout);
      if (resp.statusCode != 200) {
        return AppUpdateInfo(AppUpdateStatus.offline,
            message: 'манифест: код ${resp.statusCode}');
      }
      m = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      return AppUpdateInfo(AppUpdateStatus.offline, message: '$e');
    }

    final remoteBuild = (m['app_build'] as int?) ?? 0;
    if (remoteBuild <= currentBuild) {
      return AppUpdateInfo(AppUpdateStatus.upToDate, build: currentBuild);
    }
    _manifest = m;
    return AppUpdateInfo(AppUpdateStatus.available,
        build: remoteBuild, version: m['app_version'] as String?);
  }

  @override
  Future<String?> install() async {
    final m = _manifest;
    if (m == null) return 'нет данных об обновлении';
    final apkUrl = m['apk_url'] as String?;
    final expected = m['sha256'] as String?;
    if (apkUrl == null) return 'в манифесте нет ссылки на APK';

    try {
      final resp =
          await http.get(Uri.parse(apkUrl)).timeout(kApkDownloadTimeout);
      if (resp.statusCode != 200) {
        return 'скачивание: код ${resp.statusCode}';
      }
      final bytes = resp.bodyBytes;
      if (expected != null && sha256.convert(bytes).toString() != expected) {
        return 'файл повреждён (sha256 не сходится) — установка отменена';
      }
      // Перезаписываемое имя — старый файл обновления нам не нужен.
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/update.apk');
      await f.writeAsBytes(bytes, flush: true);

      // Открыть системный установщик. open_filex несёт свой FileProvider,
      // ручной настройки не требует. Дальше система показывает «Установить».
      final res = await OpenFilex.open(f.path,
          type: 'application/vnd.android.package-archive');
      if (res.type != ResultType.done) {
        return res.message.isEmpty
            ? 'не удалось открыть установщик'
            : res.message;
      }
      return null;
    } catch (e) {
      debugPrint('APK install failed: $e');
      return '$e';
    }
  }
}
