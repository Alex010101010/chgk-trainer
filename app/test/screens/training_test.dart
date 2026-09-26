import 'dart:math';

import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/fact_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:chgk_trainer/model/fact.dart';
import 'package:chgk_trainer/screens/fact_deck_screen.dart';
import 'package:chgk_trainer/screens/training_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 26, 12);

FactCard _card(String id, {String deck = 'perifrazy'}) =>
    FactCard(id: id, deck: deck, ask: 'Кто это?', front: 'лицо $id', back: 'оборот $id', note: 'заметка $id');

final _decks = [
  const FactDeck(id: 'perifrazy', title: 'Перифразы'),
  const FactDeck(id: 'latyn', title: 'Латынь'),
  const FactDeck(id: 'empty', title: 'Пустая'),
];

class FakeFacts implements FactRepository {
  final List<FactCard> cards;
  FakeFacts(this.cards);
  @override
  Future<FactBook> loadAll() async => FactBook(decks: _decks, cards: cards);
}

FactEvent _f(String id, bool known, {int daysAgo = 0}) => FactEvent.at(
    _now.subtract(Duration(days: daysAgo)),
    cardId: id, deck: 'perifrazy', known: known);

Future<MemoryEventLog> _logWith(List<JournalEvent> events) async {
  final log = MemoryEventLog();
  for (final e in events) {
    await log.append(e);
  }
  return log;
}

Future<void> _pump(WidgetTester tester, MemoryEventLog log, List<FactCard> cards) async {
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      theme: buildDarkTheme(),
      home: TrainingScreen(
        repository: FakeFacts(cards),
        now: () => _now,
        random: Random(1),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('selectFactSession', () {
    final deck = [for (var i = 0; i < 15; i++) _card('c$i')];

    test('новых — не больше дневного лимита колоды', () {
      expect(selectFactSession(deck, 'perifrazy', const [], _now), hasLength(kNewFactsPerDay));
    });

    test('подошедшие идут первыми, открытые сегодня новые съедают лимит', () {
      final events = [
        _f('c0', false, daysAgo: 1),
        _f('c1', true, daysAgo: 1), // вторая коробка — через два дня, ещё рано
        for (var i = 2; i < 10; i++) _f('c$i', true),
      ];
      final s = selectFactSession(deck, 'perifrazy', events, _now, random: Random(3));
      expect(s.first.id, 'c0');
      expect(s.map((c) => c.id), isNot(contains('c1')));
      // Сегодня открыто 8 новых — осталось 2 из 10.
      expect(s.length, 1 + 2);
    });
  });

  testWidgets('колоды со счётчиками, пустая колода не показывается', (tester) async {
    await _pump(tester, await _logWith([_f('a', false, daysAgo: 1)]),
        [_card('a'), _card('b'), _card('l', deck: 'latyn')]);

    expect(find.byKey(const Key('deck-perifrazy')), findsOneWidget);
    expect(find.byKey(const Key('deck-latyn')), findsOneWidget);
    expect(find.byKey(const Key('deck-empty')), findsNothing);
    expect(find.text('Повторить: 1 · новых: 1 · выучено 0 из 2'), findsOneWidget);
    expect(find.textContaining('Сергея Лобачёва'), findsOneWidget);
  });

  testWidgets('карточка: показать → знал → в журнале FactEvent, а не AnswerEvent', (tester) async {
    final log = await _logWith(const []);
    await _pump(tester, log, [_card('a'), _card('b')]);

    await tester.tap(find.byKey(const Key('deck-perifrazy')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const Key('fact-back')), findsNothing, reason: 'оборот скрыт до «Показать»');

    await tester.tap(find.byKey(const Key('fact-reveal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fact-back')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fact-known')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fact-reveal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fact-missed')));
    await tester.pumpAndSettle();

    expect(find.text('Знал 1 из 2. Карточки, которых не знал, вернутся завтра.'), findsOneWidget);
    final events = (await log.readAll()).events;
    expect(events.whereType<FactEvent>().map((e) => e.known).toList(), [true, false]);
    expect(events.whereType<AnswerEvent>(), isEmpty);

    // Назад к колодам — счётчики перечитаны: новых сегодня больше нет.
    await tester.tap(find.text('К колодам'));
    await tester.pumpAndSettle();
    expect(find.text('Повторить: 0 · новых: 0 · выучено 0 из 2'), findsOneWidget);
  });

  testWidgets('колода, где на сегодня всё, говорит об этом сразу', (tester) async {
    await _pump(tester, await _logWith([_f('a', true)]), [_card('a')]);
    await tester.tap(find.byKey(const Key('deck-perifrazy')));
    await tester.pumpAndSettle();
    expect(find.text('В этой колоде на сегодня всё'), findsOneWidget);
  });
}
