import 'app_updater.dart';

/// Заглушка для платформ без файловой системы (web): самообновление не нужно —
/// веб раздаётся в актуальной версии при каждом деплое.
AppUpdater createAppUpdater() => const _StubAppUpdater();

class _StubAppUpdater implements AppUpdater {
  const _StubAppUpdater();

  @override
  Future<AppUpdateInfo> check() async => const AppUpdateInfo(
      AppUpdateStatus.skipped,
      message: 'самообновление недоступно на этой платформе');

  @override
  Future<String?> install() async => 'недоступно на этой платформе';
}
