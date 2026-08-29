import 'dart:math';

import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/screens/classic_screen.dart';
import 'package:chgk_trainer/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подменные часы. Не константа: `roundId` — это момент старта раунда, и с
/// замороженными часами два раунда получают один id. В жизни раунд занимает
/// минуты, поэтому между раундами часы двигаются руками.
DateTime _clock = DateTime.utc(2026, 8, 30, 12);
final _now = DateTime.utc(2026, 8, 30, 12);

Question _q(int i) => Question(
      id: 'gq-$i',
      corpus: Corpus.gq,
      question: 'вопрос $i',
      answer: 'ответ $i',
      acceptVariants: ['ответ $i'],
    );

final _pool = List.generate(40, _q);

class FakeRepository implements QuestionRepository {
  final List<Question> questions;
  final Object? error;
  FakeRepository(this.questions, {this.error});

  @override
  Future<List<Question>> loadAll() async {
    if (error != null) throw error!;
    return questions;
  }
}

/// Журнал, у которого чтение сообщает о битых строках.
class SkippingLog extends MemoryEventLog {
  final int skipped;
  SkippingLog(this.skipped);

  @override
  Future<JournalRead> readAll() async {
    final base = await super.readAll();
    return JournalRead(base.events, skipped);
  }
}

AnswerEvent _answer(String id,
    {Verdict verdict = Verdict.missed, int daysAgo = 0}) {
  final ts = _now.subtract(Duration(days: daysAgo));
  return AnswerEvent(
    ts: ts.millisecondsSinceEpoch,
    day: localDay(ts),
    questionId: id,
    corpus: Corpus.gq,
    mode: GameMode.classic,
    verdict: verdict,
    secondsUsed: 60,
  );
}

Future<void> _pumpClassic(WidgetTester tester, EventLog log,
    {QuestionRepository? repo}) async {
  _clock = _now;
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      home: ClassicScreen(
        repository: repo ?? FakeRepository(_pool),
        random: Random(1),
        now: () => _clock,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Один вопрос от «начал» до конца цикла.
Future<void> _playOne(WidgetTester tester, {required Verdict verdict}) async {
  Future<void> tap(String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  await tap('cycle-start');
  await tap('cycle-ready');
  await tap('cycle-answer-done');
  await tap('cycle-to-verdict');
  await tester.tap(find.text(switch (verdict) {
    Verdict.taken => 'Взял',
    Verdict.almost => 'Почти',
    Verdict.missed => 'Не взял',
  }));
  await tester.pumpAndSettle();
  await tap('cycle-verdict-done');
  if (verdict != Verdict.taken) await tap('cycle-reason-done');
}

void main() {
  group('selectRound', () {
    test('вопрос из прошлого раунда во втором не выпадает', () {
      // Красный→зелёный: реализация без учёта виденных даёт пересечение
      // почти на каждом прогоне.
      final events = <JournalEvent>[
        for (var i = 0; i < 5; i++) _answer('gq-$i', verdict: Verdict.taken),
      ];
      final round = selectRound(_pool, events, _now, random: Random(7));
      expect(round.length, kRoundSize);
      expect(
        round.map((q) => q.id).toSet().intersection(
            {'gq-0', 'gq-1', 'gq-2', 'gq-3', 'gq-4'}),
        isEmpty,
      );
    });

    test('созревший вопрос идёт первым слотом', () {
      final events = <JournalEvent>[_answer('gq-3', daysAgo: 3)];
      final round = selectRound(_pool, events, _now, random: Random(7));
      expect(round.first.id, 'gq-3');
      expect(round.length, kRoundSize);
    });

    test('несозревший промах первым слотом не идёт', () {
      // Вчерашний missed ещё не подошёл: правило возврата — через два дня.
      final events = <JournalEvent>[_answer('gq-3', daysAgo: 1)];
      final round = selectRound(_pool, events, _now, random: Random(7));
      expect(round.map((q) => q.id), isNot(contains('gq-3')));
    });

    test('невиденные кончились — берутся самые давние, без дублей', () {
      final small = List.generate(6, _q);
      final events = <JournalEvent>[
        for (var i = 0; i < 6; i++)
          _answer('gq-$i', verdict: Verdict.taken, daysAgo: 6 - i),
      ];
      final round = selectRound(small, events, _now, random: Random(7));
      expect(round.length, kRoundSize);
      expect(round.map((q) => q.id).toSet().length, kRoundSize);
      // Самый давний ответ — у gq-0.
      expect(round.map((q) => q.id), contains('gq-0'));
    });
  });

  testWidgets('раунд из пяти кладёт пять событий с одним roundId',
      (tester) async {
    final log = MemoryEventLog();
    await _pumpClassic(tester, log);

    for (var i = 0; i < kRoundSize; i++) {
      await _playOne(tester, verdict: Verdict.taken);
    }

    final read = await log.readAll();
    final answers = read.events.whereType<AnswerEvent>().toList();
    expect(answers.length, kRoundSize);
    expect(answers.map((e) => e.roundId).toSet().length, 1);
    expect(answers.map((e) => e.questionId).toSet().length, kRoundSize);
    expect(answers.every((e) => e.mode == GameMode.classic), isTrue);

    expect(find.byKey(const Key('classic-summary')), findsOneWidget);
    expect(find.text('Взято 5 из 5'), findsOneWidget);
  });

  testWidgets('«ещё раунд» стартует раунд с новым roundId', (tester) async {
    final log = MemoryEventLog();
    await _pumpClassic(tester, log);
    for (var i = 0; i < kRoundSize; i++) {
      await _playOne(tester, verdict: Verdict.missed);
    }
    final firstRoundId =
        (await log.readAll()).events.whereType<AnswerEvent>().first.roundId;

    _clock = _clock.add(const Duration(minutes: 5));
    await tester.tap(find.byKey(const Key('classic-next-round')));
    await tester.pumpAndSettle();
    await _playOne(tester, verdict: Verdict.taken);

    final answers =
        (await log.readAll()).events.whereType<AnswerEvent>().toList();
    expect(answers.length, kRoundSize + 1);
    expect(answers.last.roundId, isNot(firstRoundId));
    // Вопросы первого раунда во втором не повторяются.
    expect(answers.map((e) => e.questionId).toSet().length, kRoundSize + 1);
  });

  testWidgets('битые строки журнала показываются, а не замалчиваются',
      (tester) async {
    await _pumpClassic(tester, SkippingLog(3));
    expect(find.byKey(const Key('classic-journal-warning')), findsOneWidget);
    expect(find.textContaining('3 строк'), findsOneWidget);
  });

  testWidgets('несобранный ассет показывается ошибкой с инструкцией',
      (tester) async {
    await _pumpClassic(
      tester,
      MemoryEventLog(),
      repo: FakeRepository(const [],
          error: const QuestionAssetException(
              'Ассет вопросов не собран. Выполни: python3 scripts/build_app_assets.py')),
    );
    expect(find.byKey(const Key('classic-error')), findsOneWidget);
    expect(find.textContaining('build_app_assets.py'), findsOneWidget);
  });

  testWidgets('«Классика» из меню ведёт в режим, остальные — в заглушку',
      (tester) async {
    await tester.pumpWidget(JournalScope(
      log: MemoryEventLog(),
      child: MaterialApp(home: HomeScreen(repository: FakeRepository(_pool))),
    ));

    await tester.tap(find.text('Классика'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-start')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Бинго'));
    await tester.pumpAndSettle();
    expect(find.text('Скоро'), findsOneWidget);
  });
}
