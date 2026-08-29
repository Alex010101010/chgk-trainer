import 'dart:convert';

import 'package:chgk_trainer/journal/event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> roundTrip(JournalEvent e) {
    final parsed = JournalEvent.fromJson(jsonDecode(e.toJsonLine()));
    expect(parsed, isNotNull, reason: 'событие не разобралось обратно');
    return parsed!.toJson();
  }

  test('round-trip события ответа сохраняет все поля', () {
    final e = AnswerEvent(
      ts: 1756400000000,
      day: '2026-08-29',
      questionId: 'gq-369291',
      corpus: Corpus.gq,
      mode: GameMode.classic,
      verdict: Verdict.missed,
      secondsUsed: 60,
      answerWindowSec: 10,
      userAnswer: 'гамма',
      reason: MissReason.fact,
      hintUsed: true,
      roundId: '1756399999000',
      tags: const ['бинго?'],
    );
    expect(roundTrip(e), e.toJson());
  });

  test('пустая версия, «ни к одной» и отсутствие причины — валидные значения', () {
    final e = AnswerEvent(
      ts: 1756400000000,
      day: '2026-08-29',
      questionId: '15-minut-slavy-1',
      corpus: Corpus.bingo,
      mode: GameMode.bingo,
      verdict: Verdict.almost,
      secondsUsed: 0,
      userAnswer: '',
      themeGuess: kThemeGuessNone,
      theme: '15 минут славы',
      tehnikaGuess: false,
    );
    final back = roundTrip(e);
    expect(back['userAnswer'], '');
    expect(back['themeGuess'], kThemeGuessNone);
    expect(back['reason'], isNull);
    expect(back['tags'], isEmpty);
    expect(back, e.toJson());
  });

  test('round-trip заметки и старта сессии', () {
    final note = NoteEvent(
      ts: 1756400000000,
      day: '2026-08-29',
      theme: 'Ковентри',
      text: 'город + разрушение = Ковентри',
      questionId: 'coventry-1',
    );
    expect(roundTrip(note), note.toJson());

    const start = SessionStartEvent(ts: 1756400000000, day: '2026-08-29');
    expect(roundTrip(start), start.toJson());
  });

  test('незнакомый тип и будущая версия схемы не разбираются', () {
    expect(JournalEvent.fromJson({'v': 1, 'type': 'нечто', 'ts': 1, 'day': 'x'}),
        isNull);
    expect(
        JournalEvent.fromJson({
          'v': kSchemaVersion + 1,
          'type': 'sessionStart',
          'ts': 1,
          'day': '2026-08-29',
        }),
        isNull);
    expect(JournalEvent.fromJson('строка'), isNull);
  });

  test('localDay берёт локальную дату, а не UTC', () {
    expect(localDay(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    expect(localDay(DateTime(2026, 12, 31)), '2026-12-31');
  });
}
