import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 8, 29, 12);

AnswerEvent _answer({
  required String questionId,
  required Verdict verdict,
  required int daysAgo,
  bool hintUsed = false,
  String? theme,
  String? themeGuess,
}) {
  final at = _now.subtract(Duration(days: daysAgo));
  return AnswerEvent(
    ts: at.millisecondsSinceEpoch,
    day: localDay(at),
    questionId: questionId,
    corpus: Corpus.gq,
    mode: GameMode.classic,
    verdict: verdict,
    secondsUsed: 60,
    hintUsed: hintUsed,
    theme: theme,
    themeGuess: themeGuess,
  );
}

void main() {
  group('dueQuestions', () {
    test('промах возвращается через два дня, не раньше', () {
      final fresh = [_answer(questionId: 'q1', verdict: Verdict.missed, daysAgo: 1)];
      expect(dueQuestions(fresh, _now), isEmpty);

      final old = [_answer(questionId: 'q1', verdict: Verdict.missed, daysAgo: 3)];
      expect(dueQuestions(old, _now), ['q1']);
    });

    test('граница включительная — ровно два дня уже считаются', () {
      final events = [_answer(questionId: 'q1', verdict: Verdict.missed, daysAgo: 2)];
      expect(dueQuestions(events, _now), ['q1']);
    });

    test('«почти» и «взял с подсказкой» — через неделю', () {
      final almost = [_answer(questionId: 'q1', verdict: Verdict.almost, daysAgo: 3)];
      expect(dueQuestions(almost, _now), isEmpty);
      expect(
        dueQuestions(
            [_answer(questionId: 'q1', verdict: Verdict.almost, daysAgo: 8)], _now),
        ['q1'],
      );

      final withHint = [
        _answer(
            questionId: 'q2',
            verdict: Verdict.taken,
            daysAgo: 8,
            hintUsed: true)
      ];
      expect(dueQuestions(withHint, _now), ['q2']);
    });

    test('повторный промах возвращается быстрее — через день', () {
      final events = [
        _answer(questionId: 'q1', verdict: Verdict.missed, daysAgo: 5),
        _answer(questionId: 'q1', verdict: Verdict.missed, daysAgo: 1),
      ];
      expect(dueQuestions(events, _now), ['q1']);
    });

    test('взятый без подсказки не возвращается вовсе', () {
      final events = [
        _answer(questionId: 'q1', verdict: Verdict.taken, daysAgo: 400)
      ];
      expect(dueQuestions(events, _now), isEmpty);
    });

    test('решает последний ответ, а не первый', () {
      final events = [
        _answer(questionId: 'q1', verdict: Verdict.missed, daysAgo: 30),
        _answer(questionId: 'q1', verdict: Verdict.taken, daysAgo: 1),
      ];
      expect(dueQuestions(events, _now), isEmpty);
    });
  });

  group('currentStreak', () {
    SessionStartEvent start(int daysAgo) {
      final at = _now.subtract(Duration(days: daysAgo));
      return SessionStartEvent(
          ts: at.millisecondsSinceEpoch, day: localDay(at));
    }

    test('пустой журнал — ноль', () {
      expect(currentStreak([], _now), 0);
    });

    test('три дня подряд, считая сегодня', () {
      expect(currentStreak([start(0), start(1), start(2)], _now), 3);
    });

    test('сегодня ещё не заходил, но вчера — стрик жив', () {
      expect(currentStreak([start(1), start(2)], _now), 2);
    });

    test('пропуск больше суток обрывает стрик', () {
      expect(currentStreak([start(2), start(3)], _now), 0);
      expect(currentStreak([start(0), start(1), start(4)], _now), 2);
    });
  });

  test('takenRate считается по окну последних ответов', () {
    expect(takenRate([]), isNull);
    final events = [
      _answer(questionId: 'q1', verdict: Verdict.taken, daysAgo: 3),
      _answer(questionId: 'q2', verdict: Verdict.missed, daysAgo: 2),
      _answer(questionId: 'q3', verdict: Verdict.taken, daysAgo: 1),
    ];
    expect(takenRate(events), closeTo(2 / 3, 1e-9));
    expect(takenRate(events, window: 1), 1.0);
  });

  test('recognizedThemes берёт только точное совпадение с клише', () {
    final events = [
      _answer(
          questionId: 'b1',
          verdict: Verdict.taken,
          daysAgo: 1,
          theme: 'Ковентри',
          themeGuess: 'Ковентри'),
      _answer(
          questionId: 'b2',
          verdict: Verdict.missed,
          daysAgo: 1,
          theme: 'Мадлен',
          themeGuess: kThemeGuessNone),
      _answer(questionId: 'b3', verdict: Verdict.taken, daysAgo: 1),
    ];
    expect(recognizedThemes(events), {'Ковентри'});
  });
}
