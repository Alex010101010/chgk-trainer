import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/fact_repository.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/model/fact.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chgk_trainer/screens/home_screen.dart';

class _FakeFacts implements FactRepository {
  @override
  Future<FactBook> loadAll() async => const FactBook(
        decks: [FactDeck(id: 'perifrazy', title: 'Перифразы')],
        cards: [
          FactCard(id: 'p-1', deck: 'perifrazy', ask: '?', front: 'Архангельский мужик', back: 'Ломоносов'),
        ],
      );
}

void main() {
  testWidgets('в шапке — название приложения, а не рабочее имя', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('Панда будет?'), findsOneWidget);
    expect(find.text('ЧГК-тренажёр'), findsNothing);
  });

  testWidgets('«Тренировка» вместо заглушки открывает список колод (T15)',
      (tester) async {
    await tester.pumpWidget(JournalScope(
      log: MemoryEventLog(),
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: HomeScreen(factRepository: _FakeFacts()),
      ),
    ));

    expect(find.text('Классика'), findsOneWidget);
    expect(find.text('Бинго'), findsOneWidget);
    expect(find.text('Тренажёр рассуждений'), findsNothing);

    await tester.scrollUntilVisible(find.text('Тренировка'), 100);
    await tester.tap(find.text('Тренировка'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('deck-perifrazy')), findsOneWidget);
    expect(find.textContaining('новых: 1'), findsOneWidget);
  });
}
