import 'package:flutter/material.dart';

import '../data/app_updater.dart';

/// Кнопка «обновить приложение» в шапке профиля.
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
  UpdateCancellation? _cancellation;

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

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
        _info('Ошибка проверки',
            'Не удалось прочитать версию. Попробуйте позже.');
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
    final progress =
        ValueNotifier(const UpdateProgress(UpdatePhase.downloading));
    final token = UpdateCancellation();
    _cancellation = token;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<UpdateProgress>(
          valueListenable: progress,
          builder: (_, value, __) => AlertDialog(
            title: const Text('Обновление приложения'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(switch (value.phase) {
                UpdatePhase.downloading => 'Скачиваю обновление…',
                UpdatePhase.verifying => 'Проверяю файл…',
                UpdatePhase.opening => 'Открываю установщик…',
              }),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                  value: value.phase == UpdatePhase.downloading
                      ? value.fraction
                      : null),
              if (value.phase == UpdatePhase.downloading) ...[
                const SizedBox(height: 12),
                Text(value.total != null && value.total! > 0
                    ? '${((value.fraction ?? 0) * 100).floor()}% · '
                        '${(value.received / 1000000).toStringAsFixed(1)} из '
                        '${(value.total! / 1000000).toStringAsFixed(1)} МБ'
                    : '${(value.received / 1000000).toStringAsFixed(1)} МБ'),
              ],
            ]),
            actions: [
              if (value.phase == UpdatePhase.downloading)
                TextButton(onPressed: token.cancel, child: const Text('Отмена'))
            ],
          ),
        ),
      ),
    );
    navigator.push(route);
    final err = await _updater.install(
      onProgress: (value) {
        if (!token.isCancelled) progress.value = value;
      },
      cancellation: token,
    );
    _cancellation = null;
    if (route.isActive) navigator.removeRoute(route);
    // The removed route may still dispose its listener this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => progress.dispose());
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text(err == null
            ? 'Открываю установщик. Нажмите «Установить».'
            : err == 'Загрузка отменена'
                ? err
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
