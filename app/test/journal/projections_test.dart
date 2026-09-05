import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 8, 29, 12);

AnswerEvent _answer({
  required String questionId,
  required Verdict verdict,
  required int daysAgo,
  int minutesAgo = 0,
  bool hintUsed = false,
  String? theme,
  String? themeGuess,
}) {
  final at = _now.subtract(Duration(days: daysAgo, minutes: minutesAgo));
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

/// Сетка. Часы двигаются: два события с одним `ts` дали бы неопределённый
/// порядок «какая сетка последняя», которого в жизни не бывает.
BingoGridEvent _grid(List<String> themes, {required int minutesAgo}) {
  final at = _now.subtract(Duration(minutes: minutesAgo));
  return BingoGridEvent(
      ts: at.millisecondsSinceEpoch, day: localDay(at), themes: themes);
}

const _nine = [
  'т1', 'т2', 'т3',
  'т4', 'т5', 'т6',
  'т7', 'т8', 'т9',
];

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

  group('masteredThemes', () {
    test('берёт только точное совпадение с клише', () {
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
        // Тап по клетке на отвлекающем gq-вопросе: клише нет, узнавания нет.
        _answer(
            questionId: 'b3',
            verdict: Verdict.taken,
            daysAgo: 1,
            themeGuess: 'Ковентри'),
      ];
      expect(masteredThemes(events), {'Ковентри'});
    });

    test('решает последнее суждение, а не первое', () {
      // Красный→зелёный: реализация «узнал хоть раз» держит обе темы освоенными.
      final events = [
        _answer(
            questionId: 'b1',
            verdict: Verdict.taken,
            daysAgo: 3,
            theme: 'Ковентри',
            themeGuess: 'Ковентри'),
        _answer(
            questionId: 'b2',
            verdict: Verdict.missed,
            daysAgo: 1,
            theme: 'Ковентри',
            themeGuess: kThemeGuessNone),
        _answer(
            questionId: 'b3',
            verdict: Verdict.missed,
            daysAgo: 3,
            theme: 'Мадлен',
            themeGuess: 'Ковентри'),
        _answer(
            questionId: 'b4',
            verdict: Verdict.taken,
            daysAgo: 1,
            theme: 'Мадлен',
            themeGuess: 'Мадлен'),
      ];
      expect(masteredThemes(events), {'Мадлен'});
    });
  });

  group('сетка бинго', () {
    test('текущая сетка — последняя собранная', () {
      expect(currentGrid([]), isNull);
      final events = [
        _grid(const ['старая'], minutesAgo: 30),
        _grid(_nine, minutesAgo: 10),
      ];
      expect(currentGrid(events), _nine);
    });

    test('клетка закрашивается узнаванием, золотится взятым вопросом', () {
      final events = <JournalEvent>[
        _grid(_nine, minutesAgo: 60),
        _answer(
            questionId: 'q1',
            verdict: Verdict.missed,
            daysAgo: 0,
            minutesAgo: 30,
            theme: 'т1',
            themeGuess: 'т1'),
        _answer(
            questionId: 'q2',
            verdict: Verdict.taken,
            daysAgo: 0,
            minutesAgo: 20,
            theme: 'т5',
            themeGuess: 'т5'),
        // Мимо клетки — состояние не меняется.
        _answer(
            questionId: 'q3',
            verdict: Verdict.taken,
            daysAgo: 0,
            minutesAgo: 10,
            theme: 'т9',
            themeGuess: kThemeGuessNone),
      ];
      final cells = gridCells(events);
      expect(cells[0], BingoCell.filled);
      expect(cells[4], BingoCell.golden);
      expect(cells[8], BingoCell.empty);
    });

    test('узнавания до старта сетки её не закрашивают', () {
      // Красный→зелёный: без сверки с `ts` сетки новая кампания открывалась бы
      // уже наполовину закрытой — по темам, узнанным в прошлой.
      final events = <JournalEvent>[
        _answer(
            questionId: 'q1',
            verdict: Verdict.taken,
            daysAgo: 1,
            theme: 'т1',
            themeGuess: 'т1'),
        _grid(_nine, minutesAgo: 10),
      ];
      expect(gridCells(events).every((c) => c == BingoCell.empty), isTrue);
    });

    test('линия — три в ряд любого цвета', () {
      expect(hasLine(const []), isFalse);
      final cells = List.filled(9, BingoCell.empty);
      cells[2] = BingoCell.filled;
      cells[4] = BingoCell.golden;
      expect(hasLine(cells), isFalse);
      cells[6] = BingoCell.filled;
      expect(hasLine(cells), isTrue);
    });
  });
}
