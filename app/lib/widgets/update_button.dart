import 'package:flutter/material.dart';

import '../data/app_updater.dart';

/// Кнопка «обновить приложение» в шапке главного экрана.
///
/// Держит один экземпляр AppUpdater: check() запоминает манифест, install()
/// его читает — разные экземпляры друг о друге не знают.
class UpdateButton extends StatefulWidget {
  /// Инжектируется в тестах, чтобы не ходить в сеть.
  final AppUpdater? updater;

  const UpdateButton({super.key, this.updater});

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  late final AppUpdater _updater = widget.updater ?? createAppUpdater();
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Проверяю версию приложения…')));
    final info = await _updater.check();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.hideCurrentSnackBar();
    switch (info.status) {
      case AppUpdateStatus.available:
        _confirmInstall(info);
      case AppUpdateStatus.upToDate:
        _info('Обновлений нет',
            'Установлена последняя сборка (${info.build ?? '—'}).');
      case AppUpdateStatus.offline:
        _info('Нет связи', 'Не достучались до сервера. Попробуйте позже.');
      case AppUpdateStatus.skipped:
        _info('Недоступно', 'Самообновление работает только на Android.');
      case AppUpdateStatus.error:
        _info('Ошибка проверки', 'Не удалось прочитать версию. Попробуйте позже.');
    }
  }

  void _info(String title, String text) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );

  void _confirmInstall(AppUpdateInfo info) {
    final ver = info.version != null ? ' ${info.version}' : '';
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Есть свежая сборка'),
        content: Text(
          'Версия$ver (build ${info.build}) готова к установке. Скачать? '
          'После загрузки система попросит подтвердить установку.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Позже'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _install();
            },
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }

  Future<void> _install() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Скачиваю… не закрывайте приложение'),
        duration: Duration(minutes: 5)));
    final err = await _updater.install();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text(err == null
            ? 'Открываю установщик. Нажмите «Установить».'
            : 'Не удалось обновить: $err')));
  }

  @override
  Widget build(BuildContext context) => IconButton(
        key: const Key('home-update'),
        tooltip: 'Обновить приложение',
        icon: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.system_update),
        onPressed: _busy ? null : _check,
      );
}
