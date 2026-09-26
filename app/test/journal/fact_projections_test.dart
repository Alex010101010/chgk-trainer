import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 26, 12);

FactEvent _f(String id, bool known, {int daysAgo = 0, int hour = 12, String deck = 'd'}) {
  final at = DateTime(_now.year, _now.month, _now.day - daysAgo, hour);
  return FactEvent.at(at, cardId: id, deck: deck, known: known);
}

AnswerEvent _answer(String id) => AnswerEvent(
      ts: _now.millisecondsSinceEpoch,
      day: localDay(_now),
      questionId: id,
      corpus: Corpus.gq,
      mode: GameMode.classic,
      verdict: Verdict.missed,
      secondsUsed: 60,
    );

void main() {
  test('«знал» трижды — четвёртая коробка, повтор через 8 дней', () {
    final events = [_f('a', true, daysAgo: 30), _f('a', true, daysAgo: 20), _f('a', true, daysAgo: 8)];
    final s = factStates(events)['a']!;
    expect(s.box, 4);
    expect(s.isDue(_now), isTrue, reason: 'срок ровно сегодня — пора');
    expect(s.isDue(_now.subtract(const Duration(days: 1))), isFalse);
  });

  test('«не знал» из пятой коробки — обратно в первую', () {
    final events = [
      for (var i = 0; i < 6; i++) _f('a', true, daysAgo: 40 - i),
      _f('a', false, daysAgo: 1),
    ];
    expect(factStates(events.sublist(0, 6))['a']!.learned, isTrue, reason: 'выше пятой некуда');
    expect(factStates(events)['a']!.box, 1);
  });

  test('отвеченная вечером карточка подходит на следующее утро', () {
    final s = factStates([_f('a', false, daysAgo: 1, hour: 23)])['a']!;
    expect(s.isDue(DateTime(_now.year, _now.month, _now.day, 7)), isTrue);
  });

  test('новые за сегодня — по колоде и по первому ответу', () {
    final events = [
      _f('old', false, daysAgo: 3),
      _f('old', true),
      _f('a', true),
      _f('b', false),
      _f('x', true, deck: 'other'),
    ];
    expect(newFactsToday(events, 'd', _now), 2);
    expect(newFactsToday(events, 'other', _now), 1);
  });

  test('карточки не трогают свёртки вопросов', () {
    final base = [_answer('q1')];
    final withFacts = [...base, _f('a', false, daysAgo: 5), _f('b', true)];
    final later = _now.add(const Duration(days: 3));
    expect(dueQuestions(withFacts, later), dueQuestions(base, later));
    expect(takenRate(withFacts), takenRate(base));
    expect(answeredThisWeek(withFacts, _now), answeredThisWeek(base, _now));
  });

  test('FactEvent переживает запись и чтение', () {
    final e = _f('a', true);
    final back = JournalEvent.fromJson(e.toJson()) as FactEvent;
    expect([back.cardId, back.deck, back.known, back.day], [e.cardId, e.deck, e.known, e.day]);
  });
}
