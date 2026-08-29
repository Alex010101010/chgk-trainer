import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:flutter_test/flutter_test.dart';

JournalEvent _session(String day) =>
    SessionStartEvent(ts: DateTime.parse(day).millisecondsSinceEpoch, day: day);

JournalEvent _answer(String day) => AnswerEvent(
      ts: DateTime.parse(day).millisecondsSinceEpoch,
      day: day,
      questionId: 'gq-1',
      corpus: Corpus.gq,
      mode: GameMode.classic,
      verdict: Verdict.taken,
      secondsUsed: 10,
    );

void main() {
  test('пустой журнал — неделя 0, без исключения', () {
    expect(weekIndex(const [], DateTime.parse('2026-08-30')), 0);
  });

  test('границы включительно: день 6 — неделя 0, день 7 — неделя 1', () {
    // Красный→зелёный: реализация по календарным неделям (пн–вс) здесь врёт,
    // потому что стаж считается от первого дня игрока, а не от понедельника.
    final events = [_session('2026-08-01')];
    expect(weekIndex(events, DateTime.parse('2026-08-01')), 0);
    expect(weekIndex(events, DateTime.parse('2026-08-07')), 0); // день 6
    expect(weekIndex(events, DateTime.parse('2026-08-08')), 1); // день 7
    expect(weekIndex(events, DateTime.parse('2026-08-14')), 1);
    expect(weekIndex(events, DateTime.parse('2026-08-15')), 2);
  });

  test('дата раньше первого дня журнала не даёт отрицательную неделю', () {
    final events = [_session('2026-08-10')];
    expect(weekIndex(events, DateTime.parse('2026-08-01')), 0);
  });

  group('answeredThisWeek', () {
    test('только заход без ответа — на этой неделе не отвечал', () {
      final events = [_session('2026-08-01')];
      expect(answeredThisWeek(events, DateTime.parse('2026-08-01')), isFalse);
    });

    test('ответ на этой неделе виден, ответ на прошлой — нет', () {
      final events = [_session('2026-08-01'), _answer('2026-08-03')];
      expect(answeredThisWeek(events, DateTime.parse('2026-08-05')), isTrue);
      expect(answeredThisWeek(events, DateTime.parse('2026-08-12')), isFalse);
    });
  });
}
