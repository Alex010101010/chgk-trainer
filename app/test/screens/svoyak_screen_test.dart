import 'dart:math';

import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/cycle/svoyak_controller.dart';
import 'package:chgk_trainer/data/svoyak_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/model/svoyak.dart';
import 'package:chgk_trainer/screens/svoyak_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SvoyakTheme _theme(String id) => SvoyakTheme(
      id: id,
      title: 'Тема $id',
      pack: 'Кубок',
      year: '2024',
      questions: [
        for (final n in [10, 20, 30, 40, 50])
          SvoyakQuestion(
            nominal: n,
            question: Question(
              id: 'si-$id$n',
              corpus: Corpus.gq,
              question: 'Вопрос $id за $n',
              answer: 'Ответ $id$n',
              acceptVariants: ['ответ $id$n'],
            ),
          ),
      ],
    );

final _themes = [for (final id in ['a', 'b', 'c', 'd']) _theme(id)];

class _Repo implements SvoyakRepository {
  @override
  Future<List<SvoyakTheme>> loadAll() async => _themes;
}

class _Clock {
  DateTime t = DateTime.utc(2026, 10, 10, 12);
  DateTime call() => t;
  void advance(int s) => t = t.add(Duration(seconds: s));
}

SvoyakEvent _played(String themeId, int hoursAgo) => SvoyakEvent.at(
      DateTime.utc(2026, 10, 10, 12).subtract(Duration(hours: hoursAgo)),
      questionId: 'si-${themeId}10',
      themeId: themeId,
      nominal: 10,
      buzzed: false,
      taken: false,
      secondsUsed: 10,
      decideSec: 10,
    );

Future<MemoryEventLog> _logWith(List<JournalEvent> events) async {
  final log = MemoryEventLog();
  for (final e in events) {
    await log.append(e);
  }
  return log;
}

/// `pump` с шагом, а не `pumpAndSettle`: таймер отсчёта периодический, и
/// дерево с ним не «успокаивается» никогда.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Список строится лениво: кнопка далеко за краем окна ещё не существует,
/// и `ensureVisible` её не найдёт — сперва до неё докручивают.
Future<void> _tap(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(find.byKey(Key(key)), 200,
      scrollable: find.byType(Scrollable).first);
  // Построенная, но за краем окна кнопка для `scrollUntilVisible` уже
  // «видима» — докручивает до неё `ensureVisible`.
  await tester.ensureVisible(find.byKey(Key(key)));
  await _settle(tester);
  await tester.tap(find.byKey(Key(key)));
  await _settle(tester);
}

Future<void> _pumpScreen(WidgetTester tester, EventLog log, _Clock clock) async {
  // Тема приложения, а не голая MaterialApp: у её кнопок бесконечная ширина,
  // и ряд без Expanded падает только на ней.
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      theme: buildLightTheme(),
      home: SvoyakScreen(
        repository: _Repo(),
        now: clock.call,
        random: Random(1),
        tick: const Duration(milliseconds: 20),
      ),
    ),
  ));
  await _settle(tester);
}

void main() {
  group('выбор тем', () {
    test('несыгранные первыми, сыгранная не предлагается', () {
      final got = selectSvoyakThemes(_themes, [_played('b', 1)], random: Random(1));
      expect(got.map((t) => t.id).toSet(), {'a', 'c', 'd'});
    });

    test('несыгранные кончились — самые давние', () {
      final events = [_played('a', 1), _played('b', 5), _played('c', 3)];
      final got = selectSvoyakThemes(_themes, events, random: Random(1));
      expect(got.map((t) => t.id), ['d', 'b', 'c']);
    });
  });

  testWidgets('тема целиком: плюс, минус, пас, истечение — и итог', (tester) async {
    final clock = _Clock();
    final log = await _logWith(const []);
    await _pumpScreen(tester, log, clock);

    final first = find.byKey(const Key('svoyak-choice'));
    expect(first, findsOneWidget);
    final themeTile = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('svoyak-theme-'));
    final id = ((tester.widget(themeTile.first).key as ValueKey<String>).value)
        .replaceFirst('svoyak-theme-', '');
    await tester.tap(themeTile.first);
    await _settle(tester);

    // 10: «Знаю!», верная версия, «Взял» → +10.
    expect(find.text('Вопрос $id за 10'), findsOneWidget);
    clock.advance(3);
    await _tap(tester, 'svoyak-buzz');
    await tester.enterText(find.byKey(const Key('svoyak-answer-field')), 'Ответ ${id}10');
    await _settle(tester);
    await _tap(tester, 'svoyak-answer-done');
    expect(find.text('Взял +10'), findsOneWidget);
    await _tap(tester, 'svoyak-taken');
    expect(find.text('Счёт: +10'), findsOneWidget);

    // 20: «Знаю!» и «Не взял» → −20.
    clock.advance(5);
    await _tap(tester, 'svoyak-buzz');
    await _tap(tester, 'svoyak-answer-done');
    await _tap(tester, 'svoyak-missed');
    expect(find.text('Счёт: −10'), findsOneWidget);

    // 30: пас → 0.
    clock.advance(5);
    await _tap(tester, 'svoyak-pass');
    await _tap(tester, 'svoyak-next');

    // 40: время на решение вышло — пас.
    clock.advance(kSvoyakDecideSec + 1);
    await _settle(tester);
    expect(find.byKey(const Key('svoyak-next')), findsOneWidget);
    await _tap(tester, 'svoyak-next');

    // 50: «Знаю!», «Взял» → +50.
    clock.advance(5);
    await _tap(tester, 'svoyak-buzz');
    await _tap(tester, 'svoyak-answer-done');
    await _tap(tester, 'svoyak-taken');

    expect(find.byKey(const Key('svoyak-summary')), findsOneWidget);
    expect(find.text('Счёт за тему: +40'), findsOneWidget);

    final events = (await log.readAll()).events.whereType<SvoyakEvent>().toList();
    expect(events.map((e) => e.nominal), [10, 20, 30, 40, 50]);
    expect(events.map((e) => e.score), [10, -20, 0, 0, 50]);
    expect(events.every((e) => e.themeId == id), isTrue);
    expect(events.first.secondsUsed, 3);
    expect(events.first.userAnswer, 'Ответ ${id}10');
    expect(events[3].buzzed, isFalse, reason: 'истечение пишется пасом');
    expect(events.map((e) => e.roundId).toSet().length, 1);

    // Общая статистика «Свою игру» не видит, серия — видит.
    final all = (await log.readAll()).events;
    expect(takenRate(all), isNull);
    expect(answeredCount(all), 0);
    expect(currentStreak(all, clock.t), 1);

    // Сыгранная тема больше не предлагается.
    await _tap(tester, 'svoyak-again');
    expect(find.byKey(Key('svoyak-theme-$id')), findsNothing);
    expect(find.byKey(const Key('svoyak-choice')), findsOneWidget);
  });
}
