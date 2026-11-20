import 'dart:async';
import 'dart:typed_data';
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
  final http.Client Function() _clientFactory;
  final Duration downloadTimeout;
  final Future<OpenResult> Function(String) _openApk;
  IoAppUpdater(
      {http.Client Function()? clientFactory,
      Future<OpenResult> Function(String)? openApk,
      this.downloadTimeout = kApkDownloadTimeout})
      : _clientFactory = clientFactory ?? http.Client.new,
        _openApk = openApk ??
            ((path) => OpenFilex.open(path,
                type: 'application/vnd.android.package-archive'));
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
    final manifestClient = _clientFactory();
    try {
      // cache-busting: редирект GitHub на latest кешируется CDN, и без метки
      // времени проверка может отдать вчерашний манифест.
      final ts = DateTime.now().millisecondsSinceEpoch;
      final resp = await manifestClient
          .get(Uri.parse('$kAppManifestUrl?ts=$ts'))
          .timeout(kOtaTimeout);
      if (resp.statusCode != 200) {
        return AppUpdateInfo(AppUpdateStatus.offline,
            message: 'манифест: код ${resp.statusCode}');
      }
      m = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      return AppUpdateInfo(AppUpdateStatus.offline, message: '$e');
    } finally {
      manifestClient.close();
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
  Future<String?> install(
      {void Function(UpdateProgress)? onProgress,
      UpdateCancellation? cancellation}) async {
    final m = _manifest;
    if (m == null) return 'нет данных об обновлении';
    final apkUrl = m['apk_url'] as String?;
    final expected = m['sha256'] as String?;
    if (apkUrl == null) return 'в манифесте нет ссылки на APK';

    final client = _clientFactory();
    final token = cancellation ?? UpdateCancellation();
    if (token.isCancelled) {
      client.close();
      return 'Загрузка отменена';
    }
    var finished = false;
    final cancelled = token.cancelled.then<Uint8List>((_) {
      if (!finished) client.close();
      throw const _DownloadCancelled();
    });
    Future<Uint8List> download() async {
      final resp = await client.send(http.Request('GET', Uri.parse(apkUrl)));
      if (resp.statusCode != 200) {
        throw HttpException('скачивание: код ${resp.statusCode}');
      }
      final total = (m['size'] as int?) ?? resp.contentLength;
      final buffer = BytesBuilder(copy: false);
      onProgress?.call(UpdateProgress(UpdatePhase.downloading, total: total));
      await for (final chunk in resp.stream) {
        if (finished || token.isCancelled) throw const _DownloadCancelled();
        buffer.add(chunk);
        onProgress?.call(UpdateProgress(UpdatePhase.downloading,
            received: buffer.length, total: total));
      }
      return buffer.takeBytes();
    }

    try {
      final bytes =
          await Future.any([download(), cancelled]).timeout(downloadTimeout);
      if (token.isCancelled) return 'Загрузка отменена';
      onProgress?.call(const UpdateProgress(UpdatePhase.verifying));
      // Let the progress dialog paint before synchronous hashing.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (expected != null && sha256.convert(bytes).toString() != expected) {
        return 'файл повреждён (sha256 не сходится) — установка отменена';
      }
      // Перезаписываемое имя — старый файл обновления нам не нужен.
      final dir = await getApplicationSupportDirectory();
      if (token.isCancelled) return 'Загрузка отменена';
      final f = File('${dir.path}/update.apk');
      await f.writeAsBytes(bytes, flush: true);

      // Открыть системный установщик. open_filex несёт свой FileProvider,
      // ручной настройки не требует. Дальше система показывает «Установить».
      onProgress?.call(const UpdateProgress(UpdatePhase.opening));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (token.isCancelled) return 'Загрузка отменена';
      final res = await _openApk(f.path);
      if (res.type != ResultType.done) {
        return res.message.isEmpty
            ? 'не удалось открыть установщик'
            : res.message;
      }
      return null;
    } on _DownloadCancelled {
      return 'Загрузка отменена';
    } on TimeoutException {
      return 'Загрузка не завершилась за 5 минут. Проверьте соединение и повторите.';
    } catch (e) {
      if (token.isCancelled) return 'Загрузка отменена';
      debugPrint('APK install failed: $e');
      return '$e';
    } finally {
      finished = true;
      client.close();
    }
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
