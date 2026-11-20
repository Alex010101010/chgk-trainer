import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chgk_trainer/data/app_updater.dart';
import 'package:chgk_trainer/widgets/update_button.dart';

/// Подставной апдейтер: сеть в тестах не трогаем, проверяем только развилки UI.
class _FakeUpdater implements AppUpdater {
  final AppUpdateInfo info;
  final String? installError;
  int installs = 0;
  Completer<String?>? pending;
  void Function(UpdateProgress)? report;
  UpdateCancellation? token;
  _FakeUpdater(this.info, {this.installError});

  @override
  Future<AppUpdateInfo> check() async => info;

  @override
  Future<String?> install(
      {void Function(UpdateProgress)? onProgress,
      UpdateCancellation? cancellation}) async {
    installs++;
    report = onProgress;
    token = cancellation;
    if (pending != null) {
      cancellation?.cancelled.then((_) {
        if (!pending!.isCompleted) pending!.complete('Загрузка отменена');
      });
      return pending!.future;
    }
    return installError;
  }
}

Widget _host(AppUpdater u) => MaterialApp(
      home: Scaffold(appBar: AppBar(actions: [UpdateButton(updater: u)])),
    );

void main() {
  testWidgets('прогресс, неизвестный размер и отмена загрузки', (tester) async {
    final u =
        _FakeUpdater(const AppUpdateInfo(AppUpdateStatus.available, build: 49))
          ..pending = Completer<String?>();
    await tester.pumpWidget(_host(u));
    await tester.tap(find.byKey(const Key('home-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Обновить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    u.report!(const UpdateProgress(UpdatePhase.downloading,
        received: 12000000, total: 32000000));
    await tester.pump();
    expect(find.text('37% · 12.0 из 32.0 МБ'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .375);
    u.report!(
        const UpdateProgress(UpdatePhase.downloading, received: 12000000));
    await tester.pump();
    expect(find.text('12.0 МБ'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(u.token!.isCancelled, isTrue);
    expect(find.text('Загрузка отменена'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('проверка и установщик показываются отдельно от загрузки',
      (tester) async {
    final u =
        _FakeUpdater(const AppUpdateInfo(AppUpdateStatus.available, build: 49))
          ..pending = Completer<String?>();
    await tester.pumpWidget(_host(u));
    await tester.tap(find.byKey(const Key('home-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Обновить'));
    await tester.pump();
    u.report!(const UpdateProgress(UpdatePhase.verifying));
    await tester.pump();
    expect(find.text('Проверяю файл…'), findsOneWidget);
    expect(find.text('Отмена'), findsNothing);
    u.report!(const UpdateProgress(UpdatePhase.opening));
    await tester.pump();
    expect(find.text('Открываю установщик…'), findsOneWidget);
    u.pending!.complete(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('Нажмите «Установить»'), findsOneWidget);
  });

  testWidgets('свежая версия уже стоит — сообщение без предложения ставить',
      (tester) async {
    await tester.pumpWidget(_host(
        _FakeUpdater(const AppUpdateInfo(AppUpdateStatus.upToDate, build: 7))));

    await tester.tap(find.byKey(const Key('home-update')));
    await tester.pumpAndSettle();

    expect(find.text('Обновлений нет'), findsOneWidget);
    expect(find.text('Обновить'), findsNothing);
  });

  testWidgets('есть свежая сборка — «Обновить» запускает установку',
      (tester) async {
    final u = _FakeUpdater(const AppUpdateInfo(AppUpdateStatus.available,
        build: 9, version: '0.1.0'));
    await tester.pumpWidget(_host(u));

    await tester.tap(find.byKey(const Key('home-update')));
    await tester.pumpAndSettle();
    expect(find.text('Есть свежая сборка'), findsOneWidget);

    await tester.tap(find.text('Обновить'));
    await tester.pumpAndSettle();

    expect(u.installs, 1);
    expect(find.textContaining('Нажмите «Установить»'), findsOneWidget);
  });

  testWidgets('ошибка установки показывается, а не замалчивается',
      (tester) async {
    final u = _FakeUpdater(
        const AppUpdateInfo(AppUpdateStatus.available, build: 9),
        installError: 'файл повреждён');
    await tester.pumpWidget(_host(u));

    await tester.tap(find.byKey(const Key('home-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Обновить'));
    await tester.pumpAndSettle();

    expect(find.textContaining('файл повреждён'), findsOneWidget);
  });

  testWidgets('нет связи — понятное сообщение', (tester) async {
    await tester.pumpWidget(
        _host(_FakeUpdater(const AppUpdateInfo(AppUpdateStatus.offline))));

    await tester.tap(find.byKey(const Key('home-update')));
    await tester.pumpAndSettle();

    expect(find.text('Нет связи'), findsOneWidget);
  });
}
