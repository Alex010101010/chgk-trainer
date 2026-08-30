import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chgk_trainer/data/app_updater.dart';
import 'package:chgk_trainer/widgets/update_button.dart';

/// Подставной апдейтер: сеть в тестах не трогаем, проверяем только развилки UI.
class _FakeUpdater implements AppUpdater {
  final AppUpdateInfo info;
  final String? installError;
  int installs = 0;
  _FakeUpdater(this.info, {this.installError});

  @override
  Future<AppUpdateInfo> check() async => info;

  @override
  Future<String?> install() async {
    installs++;
    return installError;
  }
}

Widget _host(AppUpdater u) => MaterialApp(
      home: Scaffold(appBar: AppBar(actions: [UpdateButton(updater: u)])),
    );

void main() {
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
    final u = _FakeUpdater(const AppUpdateInfo(AppUpdateStatus.available, build: 9),
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
