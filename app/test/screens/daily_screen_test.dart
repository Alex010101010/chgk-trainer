import 'dart:math';

import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/screens/classic_screen.dart';
import 'package:chgk_trainer/screens/daily_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 25, 12);

Question _q(int i, {Corpus corpus = Corpus.gq}) => Question(
      id: '${corpus == Corpus.gq ? 'gq' : 'ix'}-$i',
      corpus: corpus,
      question: 'вопрос $i',
      answer: 'ответ $i',
      acceptVariants: ['ответ $i'],
    );

final _pool = List.generate(40, _q);

class FakeRepository implements QuestionRepository {
  final List<Question> questions;
  FakeRepository(this.questions);
  @override
  Future<List<Question>> loadAll() async => questions;
}

AnswerEvent _daily(DateTime at, {Verdict verdict = Verdict.taken}) => AnswerEvent(
      ts: at.millisecondsSinceEpoch,
      day: localDay(at),
      questionId: 'gq-1',
      corpus: Corpus.gq,
      mode: GameMode.daily,
      verdict: verdict,
      secondsUsed: 30,
    );

Future<void> _pump(WidgetTester tester, EventLog log,
    {List<Question>? pool}) async {
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      theme: buildLightTheme(),
      home: DailyScreen(repository: FakeRepository(pool ?? _pool), now: () => _now),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('dailyQuestion', () {
    test('один и тот же день — один и тот же вопрос, в любом порядке пула', () {
      final a = dailyQuestion(_pool, '2026-09-25');
      final b = dailyQuestion(_pool.reversed.toList(), '2026-09-25');
      expect(a!.id, b!.id);
    });

    test('разные дни дают разные вопросы', () {
      final ids = {
        for (var d = 1; d <= 20; d++)
          dailyQuestion(_pool, '2026-09-${d.toString().padLeft(2, '0')}')!.id
      };
      expect(ids.length, greaterThan(10));
    });

    // Красный→зелёный: на `pool[hash(day) % length]` пересборка корпуса,
    // добавившая вопросы, сдвигала бы сегодняшний вопрос.
    test('пул вырос — вопрос дня почти всегда тот же', () {
      final grown = [..._pool, for (var i = 100; i < 110; i++) _q(i)];
      var same = 0;
      for (var d = 1; d <= 28; d++) {
        final day = '2026-09-${d.toString().padLeft(2, '0')}';
        if (dailyQuestion(_pool, day)!.id == dailyQuestion(grown, day)!.id) same++;
      }
      // 40 из 50 вопросов старые: победитель сохраняется с вероятностью ~80%.
      expect(same, greaterThanOrEqualTo(18));
    });

    test('пустой пул — нет вопроса, а не падение', () {
      expect(dailyQuestion(const [], '2026-09-25'), isNull);
    });
  });

  group('dailyStreak', () {
    test('серия считается по дням с вопросом дня, вчерашняя ещё жива', () {
      final events = [
        _daily(_now.subtract(const Duration(days: 3))),
        _daily(_now.subtract(const Duration(days: 2))),
        _daily(_now.subtract(const Duration(days: 1))),
      ];
      expect(dailyStreak(events, _now), 3);
      expect(dailyStreak([...events, _daily(_now)], _now), 4);
    });

    test('ответ в Классике серию вопроса дня не продлевает', () {
      final classic = AnswerEvent(
        ts: _now.millisecondsSinceEpoch,
        day: localDay(_now),
        questionId: 'gq-2',
        corpus: Corpus.gq,
        mode: GameMode.classic,
        verdict: Verdict.taken,
        secondsUsed: 30,
      );
      expect(dailyStreak([classic], _now), 0);
    });

    test('пропущенный день обрывает серию', () {
      final events = [
        _daily(_now.subtract(const Duration(days: 3))),
        _daily(_now.subtract(const Duration(days: 1))),
      ];
      expect(dailyStreak(events, _now), 1);
    });
  });

  testWidgets('одна попытка: после ответа — итог, и повторный вход его же',
      (tester) async {
    final log = MemoryEventLog();
    await _pump(tester, log);
    final expected = dailyQuestion(_pool, localDay(_now))!;
    expect(find.text(expected.question), findsOneWidget);

    await _tap(tester, 'cycle-start');
    await _tap(tester, 'cycle-ready');
    await _tap(tester, 'cycle-answer-done');
    await _tap(tester, 'cycle-verdict-almost');

    expect(find.byKey(const Key('daily-result')), findsOneWidget);
    expect(find.text('Дней подряд: 1'), findsOneWidget);
    final events = (await log.readAll()).events.whereType<AnswerEvent>().toList();
    expect(events, hasLength(1));
    expect(events.single.mode, GameMode.daily);
    expect(events.single.questionId, expected.id);

    // Повторный вход в тот же день — итог, а не вопрос заново.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, log);
    expect(find.byKey(const Key('daily-result')), findsOneWidget);
    expect(find.byKey(const Key('cycle-start')), findsNothing);
  });

  testWidgets('бинго-вопрос вопросом дня не становится', (tester) async {
    final pool = [_q(1, corpus: Corpus.bingo), _q(2)];
    await _pump(tester, MemoryEventLog(), pool: pool);
    expect(find.text('вопрос 2'), findsOneWidget);
  });

  testWidgets('сегодняшний вопрос дня в Классику не попадает', (tester) async {
    final pool = List.generate(6, _q);
    final daily = dailyQuestion(pool, localDay(_now))!;
    await tester.pumpWidget(JournalScope(
      log: MemoryEventLog(),
      child: MaterialApp(
        home: ClassicScreen(
          repository: FakeRepository(pool),
          random: Random(1),
          now: () => _now,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('tehnika-card-done'));
    if (card.evaluate().isNotEmpty) await _tap(tester, 'tehnika-card-done');

    final shown = <String>{};
    for (var i = 0; i < kRoundSize; i++) {
      shown.addAll(_pool
          .map((q) => q.question)
          .where((t) => find.text(t).evaluate().isNotEmpty));
      await _tap(tester, 'cycle-start');
      await _tap(tester, 'cycle-ready');
      await _tap(tester, 'cycle-answer-done');
      await _tap(tester, 'cycle-verdict-missed');
    }
    expect(shown, hasLength(kRoundSize));
    expect(shown, isNot(contains(daily.question)));
  });
}
