import 'dart:math';

import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/screens/bingo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 9, 5, 12);

Question _bingo(String theme, int i) => Question(
      id: 'b-$theme-$i',
      corpus: Corpus.bingo,
      question: 'вопрос $theme $i',
      answer: 'ответ',
      acceptVariants: ['ответ'],
      theme: theme,
    );

Question _gq(int i) => Question(
      id: 'gq-$i',
      corpus: Corpus.gq,
      question: 'вопрос отвлекающий $i',
      answer: 'ответ',
      acceptVariants: ['ответ'],
    );

/// Двенадцать тем по два вопроса плюс запас отвлекающих.
final _pool = <Question>[
  for (var t = 0; t < 12; t++) ...[_bingo('т$t', 0), _bingo('т$t', 1)],
  for (var i = 0; i < 20; i++) _gq(i),
];

AnswerEvent _answer(
  String questionId, {
  required int minutesAgo,
  String? theme,
  String? themeGuess,
  Verdict verdict = Verdict.missed,
}) {
  final at = _now.subtract(Duration(minutes: minutesAgo));
  return AnswerEvent(
    ts: at.millisecondsSinceEpoch,
    day: localDay(at),
    questionId: questionId,
    corpus: theme == null ? Corpus.gq : Corpus.bingo,
    mode: GameMode.bingo,
    verdict: verdict,
    secondsUsed: 60,
    theme: theme,
    themeGuess: themeGuess,
  );
}

void main() {
  group('buildGrid', () {
    test('девять тем, три из них освоенные', () {
      final events = <JournalEvent>[
        for (var t = 0; t < 5; t++)
          _answer('b-т$t-0', minutesAgo: 100 - t, theme: 'т$t', themeGuess: 'т$t'),
      ];
      final grid = buildGrid(_pool, events, random: Random(1));
      expect(grid, hasLength(kGridSize));
      expect(grid.toSet(), hasLength(kGridSize), reason: 'темы не повторяются');
      final mastered = masteredThemes(events);
      expect(grid.where(mastered.contains), hasLength(kGridMastered));
    });

    test('в начале игры освоенных нет — сетка всё равно собирается', () {
      final grid = buildGrid(_pool, const [], random: Random(2));
      expect(grid, hasLength(kGridSize));
    });

    test('тема без непоказанных вопросов в сетку не попадает', () {
      // Красный→зелёный: без проверки остатка тема встаёт в клетку, которую
      // нечем закрасить — вопросов по ней в корпусе больше нет.
      final events = <JournalEvent>[
        _answer('b-т0-0', minutesAgo: 20),
        _answer('b-т0-1', minutesAgo: 10),
      ];
      final grid = buildGrid(_pool, events, random: Random(3));
      expect(grid.contains('т0'), isFalse);
      expect(grid, hasLength(kGridSize));
    });
  });

  group('selectBingoRound', () {
    final grid = ['т0', 'т1', 'т2', 'т3', 'т4', 'т5', 'т6', 'т7', 'т8'];

    test('три вопроса по разным темам сетки и два отвлекающих', () {
      final round = selectBingoRound(_pool, const [], grid, random: Random(1));
      expect(round, hasLength(kBingoRoundSize));

      final themed = round.where((q) => q.corpus == Corpus.bingo).toList();
      expect(themed, hasLength(kBingoThemed));
      expect(themed.map((q) => q.theme).toSet(), hasLength(kBingoThemed),
          reason: 'две клетки одной темы в раунде бессмысленны');
      expect(themed.every((q) => grid.contains(q.theme)), isTrue);
      expect(round.where((q) => q.corpus == Corpus.gq), hasLength(2));
    });

    test('вопрос, уже отвеченный, во второй раунд не попадает', () {
      final first = selectBingoRound(_pool, const [], grid, random: Random(5));
      final events = <JournalEvent>[
        for (final q in first)
          _answer(q.id, minutesAgo: 30, theme: q.theme, themeGuess: q.theme),
      ];
      final second = selectBingoRound(_pool, events, grid, random: Random(6));
      expect(second.map((q) => q.id).toSet().intersection(
          first.map((q) => q.id).toSet()),
          isEmpty);
    });

    test('закрытые клетки в раунд не попадают — их темы не передают', () {
      final round =
          selectBingoRound(_pool, const [], const ['т0'], random: Random(7));
      final themed = round.where((q) => q.corpus == Corpus.bingo);
      expect(themed, hasLength(1));
      expect(themed.single.theme, 'т0');
      // Недостающие места добираются отвлекающими, раунд не укорачивается.
      expect(round, hasLength(kBingoRoundSize));
    });
  });
  setUp(() => _clock = _now);

  group('BingoScreen', () {
    testWidgets('вход собирает сетку и пишет её в журнал', (tester) async {
      final log = MemoryEventLog();
      await _pumpBingo(tester, log);

      expect(find.byKey(const Key('bingo-board')), findsOneWidget);
      final events = (await log.readAll()).events;
      final grid = events.whereType<BingoGridEvent>().toList();
      expect(grid, hasLength(1));
      expect(grid.single.themes, hasLength(kGridSize));
      // Все девять тем видны на доске — иначе кампания идёт вслепую.
      for (final t in grid.single.themes) {
        expect(find.text(t), findsWidgets);
      }
    });

    testWidgets('сетка переживает перезапуск экрана', (tester) async {
      // Красный→зелёный: сетка, собираемая при каждом входе, теряет прогресс
      // кампании — игрок возвращается к другим девяти клеткам.
      final log = MemoryEventLog();
      await _pumpBingo(tester, log);
      final first = currentGrid((await log.readAll()).events);

      _clock = _now.add(const Duration(hours: 2));
      await _pumpBingo(tester, log);
      final events = (await log.readAll()).events;
      expect(events.whereType<BingoGridEvent>(), hasLength(1));
      expect(currentGrid(events), first);
    });

    testWidgets('раунд из пяти: три по сетке, догадка едет в журнал',
        (tester) async {
      final log = MemoryEventLog();
      await _pumpBingo(tester, log);
      await _tapKey(tester, 'bingo-start-round');

      for (var i = 0; i < kBingoRoundSize; i++) {
        final theme = _themeOnScreen(tester);
        _clock = _clock.add(const Duration(minutes: 2));
        await _playOne(tester, cell: theme);
      }

      expect(find.byKey(const Key('bingo-board')), findsOneWidget);
      final answers =
          (await log.readAll()).events.whereType<AnswerEvent>().toList();
      expect(answers, hasLength(kBingoRoundSize));
      expect(answers.every((e) => e.mode == GameMode.bingo), isTrue);
      expect(answers.map((e) => e.roundId).toSet(), hasLength(1));

      final themed = answers.where((e) => e.theme != null).toList();
      expect(themed, hasLength(kBingoThemed));
      expect(themed.every((e) => e.themeGuess == e.theme), isTrue);
      // Отвлекающие: «ни к одной» записана маркером, а не как «не спрашивали».
      final others = answers.where((e) => e.theme == null);
      expect(others.every((e) => e.themeGuess == kThemeGuessNone), isTrue);
      // И клетки закрасились ровно по узнанным темам.
      final cells = gridCells((await log.readAll()).events);
      expect(cells.where((c) => c != BingoCell.empty), hasLength(kBingoThemed));
    });

    testWidgets('линия закрывает сетку, следующий раунд начинает новую',
        (tester) async {
      final log = MemoryEventLog();
      await _pumpBingo(tester, log);
      final grid = currentGrid((await log.readAll()).events)!;

      // Закрываем верхний ряд руками: попасть в линию честной игрой можно
      // только перебором раундов, а проверяется здесь реакция экрана.
      for (final i in [0, 1, 2]) {
        _clock = _clock.add(const Duration(minutes: 5));
        await log.append(_answer('b-${grid[i]}-0',
            minutesAgo: 0, theme: grid[i], themeGuess: grid[i]));
      }
      _clock = _clock.add(const Duration(minutes: 5));
      await _pumpBingo(tester, log);

      expect(hasLine(gridCells((await log.readAll()).events)), isTrue);
      await _tapKey(tester, 'bingo-start-round');

      final grids =
          (await log.readAll()).events.whereType<BingoGridEvent>().toList();
      expect(grids, hasLength(2), reason: 'линия закрыла сетку');
      expect(grids.last.themes, isNot(grid));
      expect(gridCells((await log.readAll()).events)
          .every((c) => c == BingoCell.empty),
          isTrue,
          reason: 'новая сетка открывается пустой');
    });

    testWidgets('клише кончились — сообщение, а не сетка из семи клеток',
        (tester) async {
      await _pumpBingo(tester, MemoryEventLog(),
          pool: [for (var t = 0; t < 4; t++) _bingo('т$t', 0), _gq(0)]);
      expect(find.byKey(const Key('bingo-error')), findsOneWidget);
      expect(find.textContaining('Клише кончились'), findsOneWidget);
    });
  });
}


// ── экран ────────────────────────────────────────────────────────────────────

class FakeRepository implements QuestionRepository {
  final List<Question> questions;
  FakeRepository(this.questions);

  @override
  Future<List<Question>> loadAll() async => questions;
}

/// Часы двигаются между раундами: с замороженными два раунда получили бы один
/// `roundId`, а две сетки — один `ts`, и «какая последняя» стало бы неясно.
DateTime _clock = _now;

Future<void> _pumpBingo(WidgetTester tester, EventLog log,
    {List<Question>? pool}) async {
  // Окно по умолчанию (800×600) короче телефона: доска с девятью клетками и
  // кнопками в него не влезает, и тап не доходит до кнопки за краем.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      home: BingoScreen(
        // Свой ключ на каждый pump: иначе Flutter переиспользует State, и
        // «перезапуск» в тесте не перечитывает журнал вовсе.
        key: UniqueKey(),
        repository: FakeRepository(pool ?? _pool),
        random: Random(1),
        now: () => _clock,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Один вопрос от «начал» до конца цикла. [cell] — какую клетку выбрать:
/// `null` значит «ни к одной».
Future<void> _playOne(WidgetTester tester,
    {String? cell, Verdict verdict = Verdict.missed}) async {
  await _tapKey(tester, 'cycle-start');
  await _tapKey(tester, 'cycle-ready');
  await _tapKey(tester, 'cycle-answer-done');

  if (cell == null) {
    await tester.ensureVisible(find.byKey(const Key('cycle-bingo-none')));
    await tester.pump();
    await _tapKey(tester, 'cycle-bingo-none');
  } else {
    final button = find.descendant(
      of: find.byKey(const Key('cycle-bingo-grid')),
      matching: find.text(cell),
    );
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  await _tapKey(tester, 'cycle-to-verdict');
  await tester.tap(find.text(switch (verdict) {
    Verdict.taken => 'Взял',
    Verdict.almost => 'Почти',
    Verdict.missed => 'Не взял',
  }));
  await tester.pumpAndSettle();
  await _tapKey(tester, 'cycle-verdict-done');
  if (verdict != Verdict.taken) await _tapKey(tester, 'cycle-reason-done');
}

/// Тема вопроса, который сейчас на экране, или `null` у отвлекающего.
String? _themeOnScreen(WidgetTester tester) {
  final text = tester.widget<Text>(find.textContaining('вопрос ').first).data!;
  final match = RegExp(r'вопрос (т\d+)').firstMatch(text);
  return match?.group(1);
}
