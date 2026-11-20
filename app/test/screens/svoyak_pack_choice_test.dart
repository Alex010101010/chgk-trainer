import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/svoyak_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/screens/svoyak_screen.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(finder, 220,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> open(WidgetTester tester, MemoryEventLog log) async {
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      theme: buildDarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)),
        child: child!,
      ),
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      SvoyakScreen(repository: AssetSvoyakRepository()),
                )),
                child: const Text('Открыть игру'),
              ))),
    ),
  ));
  await tester.tap(find.text('Открыть игру'));
  await settle(tester);
  for (var i = 0;
      i < 100 && find.byKey(const Key('svoyak-packs')).evaluate().isEmpty;
      i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await settle(tester);
  expect(find.byKey(const Key('svoyak-packs')), findsOneWidget);
}

Future<void> team14(WidgetTester tester) async {
  await tap(tester, 'svoyak-packs');
  await tap(tester, 'svoyak-pack-group:Крафт №14');
  await tap(tester, 'svoyak-pack-kraft-team14');
}

void main() {
  testWidgets('real Kraft package: partial, restart, all five and navigation',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (Platform.environment['CHGK_CAPTURE'] == '1') {
      await tester.runAsync(() async {
        final loader = FontLoader('Nunito');
        for (final weight in ['Regular', 'SemiBold', 'Bold']) {
          loader.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
        }
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    final log = MemoryEventLog();
    await open(tester, log);
    await team14(tester);
    expect(find.text('Крафт №14 — Командная Своя игра'), findsOneWidget);
    await tap(tester, 'svoyak-theme-kraft-team14-1');
    expect(find.textContaining('Буквосочетание «чай»'), findsOneWidget);
    await tap(tester, 'svoyak-start');
    await tap(tester, 'svoyak-pass');
    await tap(tester, 'svoyak-next');
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Сыграно 1 из 5 · начать заново'), findsOneWidget);
    final first = (await log.readAll()).events.whereType<SvoyakEvent>().single;
    await log.append(first);
    await log.append(SvoyakEvent.at(DateTime.now(),
        questionId: 'removed-question',
        themeId: first.themeId,
        nominal: 20,
        buzzed: false,
        taken: false,
        secondsUsed: 0,
        decideSec: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await open(tester, log);
    await team14(tester);
    expect(find.text('Сыграно 1 из 5 · начать заново'), findsOneWidget);
    await tap(tester, 'svoyak-theme-kraft-team14-1');
    expect(find.textContaining('Буквосочетание «чай»'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tap(tester, 'svoyak-start');
      await tap(tester, 'svoyak-pass');
      await tap(tester, 'svoyak-next');
    }
    expect(find.byKey(const Key('svoyak-summary')), findsOneWidget);
    expect(find.text('Счёт за тему: 0'), findsOneWidget);
    await tap(tester, 'svoyak-again');
    expect(find.text('Завершена · можно сыграть снова'), findsOneWidget);
    expect(find.text('Крафт №14 — Командная Своя игра'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CHGK_CAPTURE'] == '1') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/private/tmp/chgk-pack-choice.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.binding.handlePopRoute();
    await settle(tester);
    await tap(tester, 'svoyak-pack-kraft-individual14');
    await tap(tester, 'svoyak-theme-kraft-individual14-10');
    expect(find.textContaining('При переводе с европейских языков'),
        findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.binding.handlePopRoute();
      await settle(tester);
    }
    expect(find.byKey(const Key('svoyak-choice')), findsOneWidget);
    await team14(tester);
    await tap(tester, 'svoyak-theme-kraft-team14-1');
    for (var i = 0; i < 5; i++) {
      await tap(tester, 'svoyak-start');
      await tap(tester, 'svoyak-pass');
      await tap(tester, 'svoyak-next');
    }
    await tap(tester, 'svoyak-done');
    expect(find.text('Открыть игру'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
