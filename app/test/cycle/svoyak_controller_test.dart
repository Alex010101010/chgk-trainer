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
  testWidgets('«Знаю!» сразу раскрывает ответ и фиксирует время решения',
      (tester) async {
    final clock = _Clock();
    final c = SvoyakController(item: _item, now: clock.call)..startDeciding();
    clock.advance(4);
    c.buzz();
    expect(c.phase, SvoyakPhase.reveal);
    expect(c.buzzed, isTrue);
    clock.advance(30);
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.secondsUsed, 4);
    c.buzz();
    c.pass();
    expect(c.buzzed, isTrue);
    expect(c.secondsUsed, 4);
    c.dispose();
  });

  testWidgets('чтение не съедает отсчёт: он идёт с «Прочитал»', (tester) async {
    final clock = _Clock();
    final c = SvoyakController(item: _item, now: clock.call);
    clock.advance(kSvoyakDecideSec + 20);
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.phase, SvoyakPhase.reading);
    c.buzz();
    expect(c.phase, SvoyakPhase.reading, reason: '«Знаю!» до «Прочитал» нет');
    c.startDeciding();
    clock.advance(12);
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.phase, SvoyakPhase.deciding);
    expect(c.decideRemainingSec, kSvoyakDecideSec - 12);
    c.dispose();
  });

  testWidgets('истечение отсчёта — пас', (tester) async {
    final clock = _Clock();
    final c = SvoyakController(item: _item, now: clock.call)..startDeciding();
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
}
