import 'dart:math';

import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/data/tehnika_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/model/tehnika.dart';
import 'package:chgk_trainer/screens/classic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 30, 12);

const _tehnika = Tehnika(
  id: 'perevod',
  title: 'Перевод для ответа',
  explain: 'Ответ спрятан в другом языке.',
  trigger: 'Что это имя значит на своём языке?',
  examples: [TehnikaExample(questionId: 'gq-3', why: 'разбор примера')],
);

Question _q(int i, {bool marked = false}) => Question(
      id: 'gq-$i',
      corpus: Corpus.gq,
      question: 'вопрос $i',
      answer: 'ответ $i',
      acceptVariants: ['ответ $i'],
      tehniki: marked ? const ['perevod'] : const [],
    );

/// Помечен эталоном ровно один вопрос — как в корпусе, где их 91 на 8866.
final _pool = [
  for (var i = 0; i < 40; i++) _q(i, marked: i == 3),
];

class FakeQuestions implements QuestionRepository {
  final List<Question> questions;
  FakeQuestions(this.questions);
  @override
  Future<List<Question>> loadAll() async => questions;
}

class FakeTehniki implements TehnikaRepository {
  @override
  Future<List<Tehnika>> loadAll() async => const [_tehnika];
}

AnswerEvent _answer(String id, {int daysAgo = 0}) {
  final ts = _now.subtract(Duration(days: daysAgo));
  return AnswerEvent(
    ts: ts.millisecondsSinceEpoch,
    day: localDay(ts),
    questionId: id,
    corpus: Corpus.gq,
    mode: GameMode.classic,
    verdict: Verdict.taken,
    secondsUsed: 10,
  );
}

Future<void> _pump(WidgetTester tester, EventLog log) async {
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      home: ClassicScreen(
        repository: FakeQuestions(_pool),
        tehnikaRepository: FakeTehniki(),
        random: Random(1),
        now: () => _now,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  test('в раунде есть эталонный вопрос приёма недели', () {
    // Их 91 на 8866: без выделенного слота такой вопрос не попадался бы
    // неделями, и вердикт игрок не увидел бы ни разу.
    final round = selectRound(_pool, const [], _now,
        random: Random(3), tehnikaId: 'perevod');
    expect(round.map((q) => q.id), contains('gq-3'));
    expect(round.length, kRoundSize);
    expect(round.map((q) => q.id).toSet().length, kRoundSize);
  });

  test('без приёма недели слот не занимается', () {
    final round = selectRound(_pool, const [], _now, random: Random(3));
    expect(round.length, kRoundSize);
  });

  test('уже виденный эталонный вопрос слот не занимает', () {
    final round = selectRound(_pool, [_answer('gq-3')], _now,
        random: Random(3), tehnikaId: 'perevod');
    expect(round.map((q) => q.id), isNot(contains('gq-3')));
    expect(round.length, kRoundSize);
  });

  testWidgets('на пустом журнале карточка урока показана до первого вопроса',
      (tester) async {
    await _pump(tester, MemoryEventLog());
    expect(find.byKey(const Key('tehnika-card')), findsOneWidget);
    expect(find.text('Перевод для ответа'), findsOneWidget);
    expect(find.text('разбор примера'), findsOneWidget);
    expect(find.byKey(const Key('cycle-start')), findsNothing);

    await _tap(tester, 'tehnika-card-done');
    expect(find.byKey(const Key('cycle-start')), findsOneWidget);
  });

  testWidgets('после ответа на этой неделе карточка больше не показывается',
      (tester) async {
    final log = MemoryEventLog();
    await log.append(_answer('gq-0', daysAgo: 1));
    await _pump(tester, log);
    expect(find.byKey(const Key('tehnika-card')), findsNothing);
    expect(find.byKey(const Key('cycle-start')), findsOneWidget);
  });

  testWidgets('эталонный вопрос даёт вердикт с разбором', (tester) async {
    final log = MemoryEventLog();
    await log.append(_answer('gq-0', daysAgo: 1)); // карточку пропускаем
    await _pump(tester, log);

    // Эталонный вопрос стоит первым слотом раунда.
    expect(find.text('вопрос 3'), findsOneWidget);
    await _tap(tester, 'cycle-start');
    await _tap(tester, 'cycle-ready');
    await _tap(tester, 'cycle-answer-done');
    await _tap(tester, 'cycle-to-verdict');
    await tester.tap(find.text('Не взял'));
    await tester.pumpAndSettle();
    await _tap(tester, 'cycle-verdict-done');
    await _tap(tester, 'cycle-reason-done');

    expect(find.text('Здесь был приём «Перевод для ответа»?'), findsOneWidget);
    await tester.tap(find.text('Да'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-tehnika-verdict')), findsOneWidget);
    expect(find.text('разбор примера'), findsOneWidget);

    await _tap(tester, 'cycle-tehnika-done');
    final e = (await log.readAll()).events.whereType<AnswerEvent>().last;
    expect(e.questionId, 'gq-3');
    expect(e.tehnikaGuess, isTrue);
  });

  testWidgets('на вопросе без эталона вердикта нет, но догадка записана',
      (tester) async {
    final log = MemoryEventLog();
    await log.append(_answer('gq-0', daysAgo: 1));
    await log.append(_answer('gq-3', daysAgo: 1)); // эталонный уже виден
    await _pump(tester, log);

    // Ищем в раунде первый вопрос, на котором тап вообще показывается.
    var asked = false;
    for (var i = 0; i < kRoundSize && !asked; i++) {
      await _tap(tester, 'cycle-start');
      await _tap(tester, 'cycle-ready');
      await _tap(tester, 'cycle-answer-done');
      await _tap(tester, 'cycle-to-verdict');
      await tester.tap(find.text('Не взял'));
      await tester.pumpAndSettle();
      await _tap(tester, 'cycle-verdict-done');
      await _tap(tester, 'cycle-reason-done');
      if (find.byKey(const Key('cycle-tehnika-done')).evaluate().isNotEmpty) {
        asked = true;
        await tester.tap(find.text('Да'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cycle-tehnika-noted')), findsOneWidget);
        expect(find.byKey(const Key('cycle-tehnika-verdict')), findsNothing);
        await _tap(tester, 'cycle-tehnika-done');
      }
    }
    expect(asked, isTrue, reason: 'тап не попался ни на одном вопросе раунда');

    final tapped = (await log.readAll())
        .events
        .whereType<AnswerEvent>()
        .where((e) => e.tehnikaGuess != null)
        .toList();
    expect(tapped, isNotEmpty);
    expect(tapped.last.tehnikaGuess, isTrue);
  });
}
