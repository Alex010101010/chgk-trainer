import 'package:chgk_trainer/cycle/answer_match.dart';
import 'package:chgk_trainer/cycle/svoyak_controller.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/model/svoyak.dart';
import 'package:flutter_test/flutter_test.dart';

const _item = SvoyakQuestion(
  nominal: 30,
  question: Question(
    id: 'si-1',
    corpus: Corpus.gq,
    question: 'ОН встречался с птицей Рух.',
    answer: 'Синдбад-мореход',
    acceptVariants: ['синдбад-мореход', 'синдбад'],
  ),
);

/// Часы двигаются между шагами: замороженные прятали бы сценарии, которых
/// не бывает (грабля 2 Flutter-тестов).
class _Clock {
  DateTime t = DateTime.utc(2026, 10, 10, 12);
  DateTime call() => t;
  void advance(int s) => t = t.add(Duration(seconds: s));
}

/// testWidgets, а не test: периодический таймер контроллера крутится в
/// фейковом времени, и `pump` его продвигает.
void main() {
  testWidgets('«Знаю!» останавливает отсчёт, версия сверяется с зачётом',
      (tester) async {
    final clock = _Clock();
    final c = SvoyakController(item: _item, now: clock.call);
    clock.advance(4);
    c.buzz();
    clock.advance(30);
    expect(c.phase, SvoyakPhase.writing);
    expect(c.buzzed, isTrue);
    expect(c.secondsUsed, 4, reason: 'секунды до нажатия, а не до раскрытия');
    c.finishWriting();
    expect(c.hint, MatchHint.none, reason: 'пустая версия не матчится');
  });

  testWidgets('версия в окне записи доезжает до подсказки', (tester) async {
    final clock = _Clock();
    final c = SvoyakController(item: _item, now: clock.call);
    c.buzz();
    clock.advance(3);
    c.setUserAnswer('Синдбад');
    c.finishWriting();
    expect(c.phase, SvoyakPhase.reveal);
    expect(c.userAnswer, 'Синдбад');
    expect(c.hint, MatchHint.taken);
  });

  testWidgets('истечение отсчёта — пас', (tester) async {
    final clock = _Clock();
    final c = SvoyakController(item: _item, now: clock.call);
    clock.advance(kSvoyakDecideSec - 1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.phase, SvoyakPhase.deciding);
    expect(c.decideRemainingSec, 1);
    clock.advance(5);
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.phase, SvoyakPhase.reveal);
    expect(c.buzzed, isFalse);
    expect(c.secondsUsed, kSvoyakDecideSec);
  });

  testWidgets('после окна записи новое не принимается', (tester) async {
    final clock = _Clock();
    final c = SvoyakController(item: _item, now: clock.call);
    c.buzz();
    c.setUserAnswer('Синд');
    clock.advance(c.answerWindowSec + 1);
    c.setUserAnswer('Синдбад');
    expect(c.writingClosed, isTrue);
    expect(c.userAnswer, 'Синд');
    // Таймер живёт до раскрытия; тестовая среда проверяет таймеры раньше
    // `addTearDown`, поэтому останавливается явно.
    c.dispose();
  });
}
