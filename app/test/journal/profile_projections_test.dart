import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 26, 12);

/// Часы двигаются: у двух ответов с одним `ts` «последний» не определён.
AnswerEvent _a(String q, Verdict v, {GameMode mode = GameMode.tehnika, int min = 0}) {
  final at = _now.add(Duration(minutes: min));
  return AnswerEvent(
    ts: at.millisecondsSinceEpoch,
    day: localDay(at),
    questionId: q,
    corpus: Corpus.gq,
    mode: mode,
    verdict: v,
    secondsUsed: 0,
  );
}

const _tehnikiOf = {
  'q1': ['perevod'],
  'q2': ['perevod', 'sozvuchie'],
  'q3': ['sozvuchie'],
};
const _opened = ['perevod', 'sozvuchie', 'kalambur'];

void main() {
  group('tehnikaStates', () {
    test('решает последний ответ: верный, затем неверный — слабое место', () {
      final events = [
        _a('q1', Verdict.taken, min: 0),
        _a('q1', Verdict.missed, min: 1),
      ];
      expect(tehnikaStates(events, _tehnikiOf, _opened)['perevod'],
          TehnikaState.weak);
    });

    test('вопрос с двумя открытыми приёмами засчитывается обоим', () {
      final s = tehnikaStates([_a('q2', Verdict.taken)], _tehnikiOf, _opened);
      expect(s['perevod'], TehnikaState.mastered);
      expect(s['sozvuchie'], TehnikaState.mastered);
    });

    test('приём без ответов — не проверен', () {
      final s = tehnikaStates([_a('q1', Verdict.taken)], _tehnikiOf, _opened);
      expect(s['kalambur'], TehnikaState.unchecked);
      expect(s.keys, _opened, reason: 'порядок — как у открытых приёмов');
    });

    test('ответы Классики на приёмы не влияют', () {
      final events = [
        _a('q1', Verdict.taken, min: 0),
        _a('q1', Verdict.missed, mode: GameMode.classic, min: 1),
      ];
      expect(tehnikaStates(events, _tehnikiOf, _opened)['perevod'],
          TehnikaState.mastered);
    });

    test('вопрос, пропавший из разметки, не роняет свёртку', () {
      final s = tehnikaStates([_a('gone', Verdict.taken)], _tehnikiOf, _opened);
      expect(s.values.toSet(), {TehnikaState.unchecked});
    });
  });

  test('answeredCount не считает проверку недели', () {
    final events = [
      _a('q1', Verdict.taken, mode: GameMode.classic),
      _a('q2', Verdict.missed, mode: GameMode.daily, min: 1),
      _a('q3', Verdict.taken, mode: GameMode.tehnika, min: 2),
    ];
    expect(answeredCount(events), 2);
  });

  test('learnedFacts — карточки в последней коробке', () {
    FactEvent f(String id, int day) => FactEvent.at(
        DateTime(2026, 9, day, 12), cardId: id, deck: 'd', known: true);
    final five = [for (var d = 1; d <= 5; d++) f('a', d)];
    expect(learnedFacts([...five, f('b', 1)]), 1);
  });
}
