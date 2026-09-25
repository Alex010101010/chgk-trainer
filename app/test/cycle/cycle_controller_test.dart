import 'package:chgk_trainer/cycle/cycle_controller.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подменные часы. Без них ни один тест таймера не пишется — ради этого
/// контроллер и принимает `now` параметром.
class FakeClock {
  DateTime t = DateTime.utc(2026, 8, 30, 12);
  DateTime call() => t;
  void advance(int seconds) => t = t.add(Duration(seconds: seconds));
}

const _q = Question(
  id: 'gq-1',
  corpus: Corpus.gq,
  question: 'вопрос',
  answer: 'Уорхол.',
  acceptVariants: ['уорхол'],
);

CycleController _make(
  FakeClock clock, {
  bool askBingoTap = false,
  int windowSec = kDefaultAnswerWindowSec,
  String? roundId,
}) =>
    CycleController(
      question: _q,
      config: CycleConfig(
        mode: GameMode.classic,
        askBingoTap: askBingoTap,
        answerWindowSec: windowSec,
        roundId: roundId,
      ),
      now: clock.call,
    );

void main() {
  test('«готов» на 12-й секунде даёт secondsUsed == 12', () {
    final clock = FakeClock();
    final c = _make(clock)..startThinking();
    clock.advance(12);
    c.readyToAnswer();
    expect(c.phase, CyclePhase.writing);
    expect(c.secondsUsed, 12);
    c.dispose();
  });

  test('часы перескочили вперёд без тиков — минута всё равно истекла', () {
    // Красный→зелёный: на счётчике тиков здесь было бы 0. Замороженное в фоне
    // приложение иначе тихо врёт в пользу игрока, и по журналу это не увидеть.
    final clock = FakeClock();
    final c = _make(clock)..startThinking();
    clock.advance(70);
    expect(c.secondsUsed, kThinkingSec);
    expect(c.thinkingExpired, isTrue);
    c.dispose();
  });

  test('минута истекла без «готов» — secondsUsed == 60', () {
    final clock = FakeClock();
    final c = _make(clock)..startThinking();
    clock.advance(70);
    c.readyToAnswer();
    expect(c.secondsUsed, kThinkingSec);
    c.dispose();
  });

  test('окно записи длится ровно answerWindowSec, набранное сохранено', () {
    final clock = FakeClock();
    final c = _make(clock, windowSec: 10)..startThinking();
    c.readyToAnswer();
    c.setUserAnswer('Уорхол');
    expect(c.writingRemainingSec, 10);
    clock.advance(9);
    expect(c.writingClosed, isFalse);
    clock.advance(1);
    expect(c.writingClosed, isTrue);
    c.setUserAnswer('поздно');
    expect(c.userAnswer, 'Уорхол');
    c.dispose();
  });

  test('верный ответ предзаполняет «взял», промах — ничего', () {
    final clock = FakeClock();
    final c = _make(clock)..startThinking();
    c.readyToAnswer();
    c.setUserAnswer('Уорхол.');
    c.finishWriting();
    expect(c.phase, CyclePhase.reveal);
    expect(c.verdict, Verdict.taken);
    c.dispose();

    final c2 = _make(FakeClock())..startThinking();
    c2.readyToAnswer();
    c2.setUserAnswer('Магритт');
    c2.finishWriting();
    expect(c2.verdict, isNull);
    c2.dispose();
  });

  test('самооценка из раскрытия сразу закрывает вопрос', () {
    final c = _make(FakeClock())..startThinking();
    c.readyToAnswer();
    c.finishWriting();
    c.finish(Verdict.missed);
    expect(c.phase, CyclePhase.done);
    expect(c.buildEvent().verdict, Verdict.missed);
    expect(c.buildEvent().reason, isNull);
    c.dispose();
  });

  test('до раскрытия самооценка ничего не делает', () {
    final c = _make(FakeClock())..startThinking();
    c.finish(Verdict.taken);
    expect(c.phase, CyclePhase.thinking);
    c.dispose();
  });

  test('тап «это бинго?» идёт до раскрытия', () {
    final c = _make(FakeClock(), askBingoTap: true)..startThinking();
    c.readyToAnswer();
    c.finishWriting();
    expect(c.phase, CyclePhase.bingoTap);
    c.submitBingoTap('Ковентри');
    expect(c.phase, CyclePhase.reveal);
    expect(c.themeGuess, 'Ковентри');
    c.dispose();
  });

  test('«ни к одной» и «не спрашивали» — разные состояния', () {
    // Контракт T10: пустая строка значит «ни к одной» (осмысленный выбор из
    // девяти клеток), null — вопрос вообще не задавали. Слить их нельзя:
    // по журналу отличить отказ от молчания будет неоткуда.
    final none = _make(FakeClock(), askBingoTap: true)..startThinking();
    none.readyToAnswer();
    none.finishWriting();
    none.submitBingoTap(kThemeGuessNone);
    expect(none.themeGuess, kThemeGuessNone);
    none.dispose();

    final unasked = _make(FakeClock(), askBingoTap: true)..startThinking();
    unasked.readyToAnswer();
    unasked.finishWriting();
    unasked.submitBingoTap(null);
    expect(unasked.themeGuess, isNull);
    unasked.dispose();
  });

  test('событие несёт answerWindowSec и roundId', () {
    final clock = FakeClock();
    final c = _make(clock, windowSec: 15, roundId: '1756500000000')
      ..startThinking();
    clock.advance(20);
    c.readyToAnswer();
    c.setUserAnswer('Уорхол');
    c.finishWriting();
    c.finish(Verdict.almost);

    final e = c.buildEvent();
    expect(e.answerWindowSec, 15);
    expect(e.roundId, '1756500000000');
    expect(e.questionId, 'gq-1');
    expect(e.mode, GameMode.classic);
    expect(e.corpus, Corpus.gq);
    expect(e.secondsUsed, 20);
    expect(e.userAnswer, 'Уорхол');
    expect(e.hintUsed, isFalse); // подсказки в фазе 1 нет вовсе
    c.dispose();
  });

  test('пустая версия доезжает до события как пустая строка', () {
    final c = _make(FakeClock())..startThinking();
    c.readyToAnswer();
    c.finishWriting();
    c.finish(Verdict.missed);
    expect(c.buildEvent().userAnswer, '');
    c.dispose();
  });
}
