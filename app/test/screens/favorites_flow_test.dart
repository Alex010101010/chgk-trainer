import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/cycle/question_cycle.dart';
import 'package:chgk_trainer/cycle/cycle_controller.dart';
import 'package:chgk_trainer/model/tehnika.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/event_log_io.dart';
import 'package:chgk_trainer/journal/favorites.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/main.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/panda/panda_voice.dart';
import 'package:chgk_trainer/widgets/favorite_button.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitFor(WidgetTester t, Finder finder) async {
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await settle(t);
  }
  expect(finder, findsOneWidget);
}

Future<void> tap(WidgetTester t, String key) async {
  final finder = find.byKey(Key(key));
  await t.scrollUntilVisible(finder, 200,
      scrollable: find
          .descendant(
              of: find.byType(ListView).last, matching: find.byType(Scrollable))
          .first);
  await t.ensureVisible(finder);
  await settle(t);
  await t.tap(finder);
  await settle(t);
}

Future<void> capture(WidgetTester t, String name) async {
  if (Platform.environment['CHGK_CAPTURE'] != '1') return;
  RenderObject? render = t.renderObject(find.byType(Scaffold).last);
  while (render != null && render is! RenderRepaintBoundary) {
    render = render.parent;
  }
  final boundary = render! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/private/tmp/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class WriteFailure extends MemoryEventLog {
  @override
  Future<void> append(JournalEvent e) async =>
      throw const FileSystemException('test failure');
}

void main() {
  testWidgets(
      'real app and disk: reveal, save, restart, profile, search, review, remove',
      (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    PackageInfo.setMockInitialValues(
        appName: 'Панда будет?',
        packageName: 'test',
        version: '0.1.0',
        buildNumber: '48',
        buildSignature: 'test');
    if (Platform.environment['CHGK_CAPTURE'] == '1') {
      await t.runAsync(() async {
        final font = FontLoader('Nunito');
        for (final w in ['Regular', 'SemiBold', 'Bold']) {
          font.addFont(rootBundle.load('assets/fonts/Nunito-$w.ttf'));
        }
        await font.load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });
    }
    final dir = await t
        .runAsync(() => Directory.systemTemp.createTemp('favorite-flow-'));
    final file = File('${dir!.path}/journal.jsonl');
    Future<void> launch() async {
      await t.pumpWidget(
          ChgkTrainerApp(log: FileEventLog(file), voice: PandaVoice([])));
      await settle(t);
    }

    await launch();
    await t.scrollUntilVisible(find.text('Своя игра'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
    await t.ensureVisible(find.text('Своя игра'));
    await settle(t);
    await t.tap(find.text('Своя игра'));
    await settle(t);
    await waitFor(t, find.byKey(const Key('svoyak-packs')));
    await tap(t, 'svoyak-packs');
    await tap(t, 'svoyak-pack-group:Крафт №14');
    await tap(t, 'svoyak-pack-kraft-team14');
    await tap(t, 'svoyak-theme-kraft-team14-1');
    const id = 'si-kraft-team14-1-10';
    expect(find.byKey(const Key('favorite-$id')), findsNothing);
    await tap(t, 'svoyak-start');
    await tap(t, 'svoyak-pass');
    await tap(t, 'favorite-$id');
    await waitFor(t, find.text('В избранном · убрать'));
    final saved = await t.runAsync(() async =>
        favoriteQuestions((await FileEventLog(file).readAll()).events));
    expect(saved!.single.question.answer, 'салочки.');
    expect(saved.single.question.comment, contains('Чай, чай выручай'));
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
    await launch();
    await t.tap(find.byKey(const Key('home-profile')));
    await settle(t);
    expect(find.text('Версия 0.1.0 · сборка 48'), findsOneWidget);
    await capture(t, 'chgk-profile-favorites');
    await t.tap(find.byKey(const Key('profile-favorites')));
    await settle(t);
    await waitFor(t, find.byKey(const Key('favorites-search')));
    await t.enterText(find.byKey(const Key('favorites-search')), 'ВЫРУЧАЙ');
    await settle(t);
    expect(find.byKey(const Key('favorite-open-$id')), findsOneWidget);
    await t.enterText(
        find.byKey(const Key('favorites-search')), 'несуществующий ответ');
    await settle(t);
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await t.enterText(find.byKey(const Key('favorites-search')), 'салочки');
    await settle(t);
    t.testTextInput.hide();
    await settle(t);
    await tap(t, 'favorite-open-$id');
    expect(find.text('салочки.'), findsOneWidget);
    await t.scrollUntilVisible(find.text('догонялки.'), 200,
        scrollable: find.descendant(of: find.byType(ListView).last,
            matching: find.byType(Scrollable)).first);
    await settle(t);
    expect(find.text('догонялки.'), findsOneWidget);
    await capture(t, 'chgk-favorite-question');
    await tap(t, 'favorite-$id');
    await waitFor(t, find.text('В избранное'));
    await t.pageBack();
    await settle(t);
    expect(find.textContaining('Пока нет избранных вопросов'), findsOneWidget);
    final removed = await t.runAsync(() async =>
        favoriteQuestions((await FileEventLog(file).readAll()).events));
    expect(removed, isEmpty);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
    await t.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('failed write does not show saved state', (t) async {
    await t.pumpWidget(JournalScope(
        log: WriteFailure(),
        child: MaterialApp(
            theme: buildDarkTheme(),
            home: const Scaffold(
                body: FavoriteButton(
                    question: Question(
                        id: 'gq-failure',
                        corpus: Corpus.gq,
                        question: 'Q',
                        answer: 'A'),
                    origin: 'Классика')))));
    await settle(t);
    await t.tap(find.byKey(const Key('favorite-gq-failure')));
    await settle(t);
    expect(find.text('В избранное'), findsOneWidget);
    expect(find.text('В избранном · убрать'), findsNothing);
    expect(find.textContaining('Не удалось сохранить вопрос'), findsOneWidget);
  });
  testWidgets(
      'common reveal saves both source commentary and technique explanation',
      (t) async {
    final log = MemoryEventLog();
    await t.pumpWidget(JournalScope(
        log: log,
        child: MaterialApp(
            theme: buildDarkTheme(),
            home: Scaffold(
                body: QuestionCycle(
              question: const Question(
                  id: 'gq-technique',
                  corpus: Corpus.gq,
                  question: 'Вопрос',
                  answer: 'Ответ',
                  comment: 'Комментарий автора'),
              config: const CycleConfig(
                  mode: GameMode.classic,
                  tehnika: Tehnika(
                      id: 'test',
                      title: 'Перевод',
                      explain: 'Урок',
                      trigger: 'Запасной текст',
                      examples: [
                        TehnikaExample(
                            questionId: 'gq-technique', why: 'Разбор примера')
                      ])),
              onFinished: (_) {},
            )))));
    await settle(t);
    expect(find.byKey(const Key('favorite-gq-technique')), findsNothing);
    await t.tap(find.byKey(const Key('cycle-start')));
    await settle(t);
    await t.tap(find.byKey(const Key('cycle-ready')));
    await settle(t);
    await t.enterText(find.byKey(const Key('cycle-answer-field')), 'Ответ');
    await t.tap(find.byKey(const Key('cycle-answer-done')));
    await settle(t);
    await t.ensureVisible(find.byKey(const Key('favorite-gq-technique')));
    await settle(t);
    await t.tap(find.byKey(const Key('favorite-gq-technique')));
    await settle(t);
    final saved = favoriteQuestions((await log.readAll()).events).single;
    expect(saved.question.comment, 'Комментарий автора');
    expect(saved.explanation, 'Приём «Перевод»: Разбор примера');
  });
}
