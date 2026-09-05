import 'package:chgk_trainer/cycle/cycle_controller.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/model/tehnika.dart';
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

const _tehnika = Tehnika(
  id: 'perevod',
  title: 'Перевод для ответа',
  explain: 'ответ прячется в другом языке',
  trigger: 'что значит это имя на своём языке?',
);

CycleController _make(
  FakeClock clock, {
  bool askBingoTap = false,
  Tehnika? tehnika,
  bool tehnikaInStandard = false,
  int windowSec = kDefaultAnswerWindowSec,
  String? roundId,
}) =>
    CycleController(
      question: _q,
      config: CycleConfig(
        mode: GameMode.classic,
        askBingoTap: askBingoTap,
        tehnika: tehnika,
        tehnikaInStandard: tehnikaInStandard,
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

  test('«взял» проскакивает роутер причины, «не взял» — нет', () {
    final clock = FakeClock();
    final c = _make(clock)..startThinking();
    c.readyToAnswer();
    c.finishWriting();
    c.toVerdict();
    c.setVerdict(Verdict.taken);
    c.confirmVerdict();
    expect(c.phase, CyclePhase.done);
    c.dispose();

    final c2 = _make(FakeClock())..startThinking();
    c2.readyToAnswer();
    c2.finishWriting();
    c2.toVerdict();
    c2.setVerdict(Verdict.missed);
    c2.confirmVerdict();
    expect(c2.phase, CyclePhase.reason);
    c2.confirmReason(); // причину разрешено пропустить
    expect(c2.phase, CyclePhase.done);
    c2.dispose();
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

  CycleController _toTehnika({bool inStandard = false}) {
    final c = _make(FakeClock(), tehnika: _tehnika, tehnikaInStandard: inStandard)
      ..startThinking();
    c.readyToAnswer();
    c.finishWriting();
    c.toVerdict();
    c.setVerdict(Verdict.taken);
    c.confirmVerdict();
    return c;
  }

  test('фаза приёма показывается только если он задан', () {
    final c = _toTehnika();
    expect(c.phase, CyclePhase.tehnika);
    c.setTehnikaGuess(true);
    c.revealTehnika();
    c.confirmTehnika();
    expect(c.phase, CyclePhase.done);
    expect(c.buildEvent().tehnikaGuess, isTrue);
    c.dispose();

    final c2 = _make(FakeClock())..startThinking();
    c2.readyToAnswer();
    c2.finishWriting();
    c2.toVerdict();
    c2.setVerdict(Verdict.taken);
    c2.confirmVerdict();
    expect(c2.phase, CyclePhase.done);
    expect(c2.buildEvent().tehnikaGuess, isNull);
    c2.dispose();
  });

  test('вердикт по тапу выносится только когда эталон говорит «да»', () {
    // Эталон с низкой полнотой не даёт права сказать «приёма здесь не было»:
    // игрок мог увидеть то, что правило поиска пропустило.
    final known = _toTehnika(inStandard: true)
      ..setTehnikaGuess(true)
      ..revealTehnika();
    expect(known.tehnikaVerdictKnown, isTrue);
    expect(known.tehnikaGuessedRight, isTrue);
    known.dispose();

    final missed = _toTehnika(inStandard: true)
      ..setTehnikaGuess(false)
      ..revealTehnika();
    expect(missed.tehnikaVerdictKnown, isTrue);
    expect(missed.tehnikaGuessedRight, isFalse);
    missed.dispose();

    final unknown = _toTehnika()
      ..setTehnikaGuess(true)
      ..revealTehnika();
    expect(unknown.tehnikaVerdictKnown, isFalse);
    // Догадка всё равно записана — это и есть разметка, ради которой тап есть.
    expect(unknown.buildEvent().tehnikaGuess, isTrue);
    unknown.dispose();
  });

  test('догадку о приёме можно переменить до «Ответить» и нельзя после', () {
    // Мисклик по сегменту не должен запирать в случайном ответе; но и
    // переписать догадку, уже увидев вердикт, нельзя — иначе разметка липовая.
    final c = _toTehnika(inStandard: true);
    c.setTehnikaGuess(true);
    c.setTehnikaGuess(false);
    expect(c.tehnikaGuess, isFalse);
    expect(c.tehnikaAnswered, isFalse);

    c.revealTehnika();
    expect(c.tehnikaAnswered, isTrue);
    c.setTehnikaGuess(true);
    expect(c.tehnikaGuess, isFalse, reason: 'после «Ответить» решение заперто');
    expect(c.buildEvent().tehnikaGuess, isFalse);
    c.dispose();
  });

  test('«Ответить» без выбора ничего не фиксирует', () {
    final c = _toTehnika()..revealTehnika();
    expect(c.tehnikaAnswered, isFalse);
    expect(c.phase, CyclePhase.tehnika);
    c.dispose();
  });

  test('событие несёт answerWindowSec и roundId', () {
    final clock = FakeClock();
    final c = _make(clock, windowSec: 15, roundId: '1756500000000')
      ..startThinking();
    clock.advance(20);
    c.readyToAnswer();
    c.setUserAnswer('Уорхол');
    c.finishWriting();
    c.toVerdict();
    c.setVerdict(Verdict.almost);
    c.confirmVerdict();
    c.setReason(MissReason.link);
    c.confirmReason();

    final e = c.buildEvent();
    expect(e.answerWindowSec, 15);
    expect(e.roundId, '1756500000000');
    expect(e.questionId, 'gq-1');
    expect(e.mode, GameMode.classic);
    expect(e.corpus, Corpus.gq);
    expect(e.secondsUsed, 20);
    expect(e.userAnswer, 'Уорхол');
    expect(e.reason, MissReason.link);
    expect(e.hintUsed, isFalse); // подсказки в фазе 1 нет вовсе
    c.dispose();
  });

  test('пустая версия доезжает до события как пустая строка', () {
    final c = _make(FakeClock())..startThinking();
    c.readyToAnswer();
    c.finishWriting();
    c.toVerdict();
    c.setVerdict(Verdict.missed);
    c.confirmVerdict();
    c.confirmReason();
    expect(c.buildEvent().userAnswer, '');
    c.dispose();
  });
}
