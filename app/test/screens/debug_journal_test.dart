import 'package:chgk_trainer/data/handout_store.dart';
import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/screens/debug_journal_screen.dart';
import 'package:chgk_trainer/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 30, 12);

class FakeQuestions implements QuestionRepository {
  @override
  Future<List<Question>> loadAll() async => const [
        Question(
          id: 'gq-1',
          corpus: Corpus.gq,
          question: 'вопрос',
          answer: 'ответ',
          acceptVariants: ['ответ'],
        ),
      ];
}

/// Вопрос объявляет раздатку, но файла под неё в сборке нет — ровно тот
/// случай, ради которого строка и добавлена (T20).
class FakeHandoutQuestions implements QuestionRepository {
  @override
  Future<List<Question>> loadAll() async => const [
        Question(
          id: 'b-1',
          corpus: Corpus.bingo,
          question: 'вопрос',
          answer: 'ответ',
          acceptVariants: ['ответ'],
          theme: 'Ковентри',
          handout: 'нет-такого-файла.jpg',
        ),
      ];
}

class SkippingLog extends MemoryEventLog {
  final int skipped;
  SkippingLog(this.skipped);

  @override
  Future<JournalRead> readAll() async {
    final base = await super.readAll();
    return JournalRead(base.events, skipped);
  }
}

AnswerEvent _answer(String id, Verdict verdict, {int daysAgo = 0}) {
  final ts = _now.subtract(Duration(days: daysAgo));
  return AnswerEvent(
    ts: ts.millisecondsSinceEpoch,
    day: localDay(ts),
    questionId: id,
    corpus: Corpus.gq,
    mode: GameMode.classic,
    verdict: verdict,
    secondsUsed: 30,
  );
}

Future<void> _pump(WidgetTester tester, EventLog log) async {
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      home: DebugJournalScreen(repository: FakeQuestions(), now: () => _now),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('на трёх событиях показаны ожидаемые числа', (tester) async {
    final log = MemoryEventLog();
    await log.append(SessionStartEvent.at(_now));
    await log.append(_answer('gq-1', Verdict.taken));
    await log.append(_answer('gq-2', Verdict.missed, daysAgo: 3));
    await _pump(tester, log);

    expect(find.text('3'), findsOneWidget); // событий
    expect(find.text('2'), findsOneWidget); // ответов
    expect(find.text('50%'), findsOneWidget); // взят один из двух
    expect(find.text('2026-08-27'), findsOneWidget); // первое событие
    // gq-2 провален три дня назад — правило возврата даёт два дня.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('пустой журнал не падает и показывает прочерки', (tester) async {
    await _pump(tester, MemoryEventLog());
    expect(find.byKey(const Key('debug-journal')), findsOneWidget);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('битые строки показаны, а не спрятаны', (tester) async {
    // Ради этого числа `skippedLines` и заведён в T10: журнал, часть которого
    // не прочитана, не имеет права выглядеть целым.
    final log = SkippingLog(4);
    await log.append(_answer('gq-1', Verdict.taken));
    await _pump(tester, log);

    final row = find.byKey(const Key('debug-skipped'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('4')), findsOneWidget);
  });

  testWidgets('замер загрузки вопросов показан числом', (tester) async {
    await _pump(tester, MemoryEventLog());
    expect(find.textContaining(' мс'), findsOneWidget);
    expect(find.text('1'), findsWidgets); // вопросов в ассете
  });

  testWidgets('вход — долгий тап по заголовку, а не пункт меню',
      (tester) async {
    await tester.pumpWidget(JournalScope(
      log: MemoryEventLog(),
      child: MaterialApp(home: HomeScreen(repository: FakeQuestions())),
    ));
    expect(find.byKey(const Key('debug-journal')), findsNothing);

    await tester.longPress(find.byKey(const Key('home-title')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('debug-journal')), findsOneWidget);
  });

  testWidgets('раздаток нет в ассете — это тревога, а не прочерк',
      (tester) async {
    await _pump(tester, MemoryEventLog());
    expect(find.text('Вопросов с раздаткой'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('раздатка объявлена, а картинка не скачивается', (tester) async {
    // С T30 картинки на Pages: без сети или без выкладки — тревога.
    final prev = HandoutStore.instance;
    HandoutStore.instance = _NoNetworkStore();
    addTearDown(() => HandoutStore.instance = prev);
    await tester.pumpWidget(JournalScope(
      log: MemoryEventLog(),
      child: MaterialApp(
        home: DebugJournalScreen(
            repository: FakeHandoutQuestions(), now: () => _now),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('не скачивается'), findsOneWidget);
  });
}

class _NoNetworkStore implements HandoutStore {
  @override
  Future<ImageProvider> resolve(String file) async => throw Exception('нет сети');
}
