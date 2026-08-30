import 'app_updater_stub.dart'
    if (dart.library.io) 'app_updater_io.dart' as impl;

/// Итог проверки самообновления приложения.
enum AppUpdateStatus {
  available, // вышла сборка новее установленной — можно ставить
  upToDate, // установлена уже последняя
  skipped, // платформа без самообновления (web)
  offline, // нет сети/таймаут
  error, // не удалось прочитать свою версию или манифест
}

class AppUpdateInfo {
  final AppUpdateStatus status;
  final int? build; // доступный build-номер из манифеста
  final String? version; // человекочитаемая версия (app_version)
  final String? message;
  const AppUpdateInfo(this.status, {this.build, this.version, this.message});
}

/// Самообновление установочного APK.
///
/// Канал — GitHub Releases: манифест последнего релиза по стабильному адресу
/// (kAppManifestUrl), APK — ассетом того же релиза. На web — заглушка.
abstract class AppUpdater {
  /// Прочитать свой build-номер, сравнить с манифестом релиза.
  /// При available запоминает манифест для последующего install().
  Future<AppUpdateInfo> check();

  /// Скачать APK из запомненного манифеста, проверить sha256, открыть системный
  /// установщик. Возвращает null при успехе или текст ошибки. Вызывать только
  /// после check() со статусом available.
  Future<String?> install();
}

AppUpdater createAppUpdater() => impl.createAppUpdater();
