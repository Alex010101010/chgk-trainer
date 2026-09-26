import 'dart:math';

import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/fact_repository.dart';
import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/data/tehnika_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/model/fact.dart';
import 'package:chgk_trainer/model/panda_line.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/model/tehnika.dart';
import 'package:chgk_trainer/panda/panda_voice.dart';
import 'package:chgk_trainer/screens/home_screen.dart';
import 'package:chgk_trainer/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 26, 12);

class _Questions implements QuestionRepository {
  @override
  Future<List<Question>> loadAll() async => const [
        Question(id: 'b1', corpus: Corpus.bingo, question: '', answer: '',
            acceptVariants: [], theme: 'Ковентри'),
        Question(id: 'b2', corpus: Corpus.bingo, question: '', answer: '',
            acceptVariants: [], theme: 'Менин'),
        Question(id: 'g1', corpus: Corpus.gq, question: '', answer: '',
            acceptVariants: [], tehniki: ['perevod']),
      ];
}

class _Tehniki implements TehnikaRepository {
  @override
  Future<List<Tehnika>> loadAll() async => const [
        Tehnika(id: 'perevod', title: 'Перевод', explain: '', trigger: ''),
        Tehnika(id: 'sozvuchie', title: 'Созвучие', explain: '', trigger: ''),
      ];
}

class _Facts implements FactRepository {
  @override
  Future<FactBook> loadAll() async => const FactBook(
        decks: [FactDeck(id: 'd', title: 'Колода')],
        cards: [
          FactCard(id: 'c1', deck: 'd', ask: '', front: '', back: '', note: ''),
          FactCard(id: 'c2', deck: 'd', ask: '', front: '', back: '', note: ''),
        ],
      );
}

/// Голос, который говорит всегда и выдаёт id момента: так видно, какой
/// момент экран выбрал.
PandaVoice _voice() => PandaVoice(
      [
        for (final id in const ['streak.alive', 'streak.broken', 'weakmap.show'])
          PandaMoment(id: id, name: id, lines: ['момент $id'], rare: const []),
      ],
      random: Random(1),
      speakPercent: 100,
    );

AnswerEvent _answer(String q, Verdict v, GameMode mode, int dayOffset,
    {String? theme, String? guess}) {
  final at = _now.add(Duration(days: dayOffset, minutes: q.hashCode % 50));
  return AnswerEvent(
    ts: at.millisecondsSinceEpoch,
    day: localDay(at),
    questionId: q,
    corpus: theme == null ? Corpus.gq : Corpus.bingo,
    mode: mode,
    verdict: v,
    secondsUsed: 0,
    theme: theme,
    themeGuess: guess,
  );
}

Future<void> _pump(WidgetTester tester, List<JournalEvent> events) async {
  _phone(tester);
  final log = MemoryEventLog();
  for (final e in events) {
    await log.append(e);
  }
  await tester.pumpWidget(JournalScope(
    log: log,
    child: PandaScope(
      voice: _voice(),
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: ProfileScreen(
          repository: _Questions(),
          tehnikaRepository: _Tehniki(),
          factRepository: _Facts(),
          now: () => _now,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  // Пузырь панды выходит с паузой — комедийный тайминг из T8.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Окно теста по умолчанию 800×600 — короче телефона, и панда внизу списка
/// не строится вовсе.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

String _value(WidgetTester tester, String key) => tester
    .widgetList<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)))
    .last
    .data!;

void main() {

  testWidgets('на журнале видны все блоки с верными числами', (tester) async {

    FactEvent fact(String id, int d) =>
        FactEvent.at(_now.add(Duration(days: d)), cardId: id, deck: 'd', known: true);

    await _pump(tester, [
      _answer('b1', Verdict.taken, GameMode.bingo, -1,
          theme: 'Ковентри', guess: 'Ковентри'),
      _answer('x', Verdict.missed, GameMode.classic, 0),
      // Неделя стажа 0: открыт только первый приём.
      _answer('g1', Verdict.missed, GameMode.tehnika, 0),
      NoteEvent(ts: _now.millisecondsSinceEpoch, day: localDay(_now),
          theme: 'Своё клише', text: 'заметка'),
      for (var d = -5; d < 0; d++) fact('c1', d),
    ]);

    // Серия — по любому событию: пять дней карточек фактов тоже заходы.
    expect(_value(tester, 'profile-streak'), '6');
    expect(_value(tester, 'profile-answered'), '2');
    expect(_value(tester, 'profile-rate'), '50%');
    expect(_value(tester, 'profile-mastered'), '1 из 2');
    expect(_value(tester, 'profile-custom'), '1');
    expect(_value(tester, 'profile-tehniki'), '0 из 1 открытых');
    expect(find.byKey(const Key('profile-weak-perevod')), findsOneWidget);
    expect(_value(tester, 'profile-facts'), '1 из 2');
    expect(find.text('момент weakmap.show'), findsOneWidget,
        reason: 'есть слабое место — панда говорит о нём, а не о серии');
    expect(tester.takeException(), isNull);
  });

  testWidgets('пустой журнал — нули и прочерк, экран строится', (tester) async {
    await _pump(tester, const []);

    expect(_value(tester, 'profile-streak'), '0');
    expect(_value(tester, 'profile-rate'), '—');
    expect(find.byKey(const Key('profile-unchecked-perevod')), findsOneWidget);
    expect(find.text('момент streak.broken'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('серия жива — панда про серию', (tester) async {
    await _pump(tester, [SessionStartEvent.at(_now)]);
    expect(find.text('момент streak.alive'), findsOneWidget);
  });

  testWidgets('карточка на главном открывает профиль', (tester) async {
    _phone(tester);

    await tester.pumpWidget(JournalScope(
      log: MemoryEventLog(),
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: HomeScreen(
          repository: _Questions(),
          tehnikaRepository: _Tehniki(),
          factRepository: _Facts(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-profile')));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
