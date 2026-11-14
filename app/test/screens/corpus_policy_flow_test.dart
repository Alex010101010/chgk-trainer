import 'dart:math';
import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/data/tehnika_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/screens/classic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('реальная новая база: урок, вопрос, запись результата', (tester) async {
    final repo = AssetQuestionRepository();
    final lessons = AssetTehnikaRepository();
    await tester.runAsync(() async {
      await repo.loadAll();
      await lessons.loadAll();
    });
    final log = MemoryEventLog();
    final seen = TehnikaCardSeen();
    await tester.pumpWidget(JournalScope(
      log: log,
      child: MaterialApp(theme: buildDarkTheme(), home: ClassicScreen(
        repository: repo, tehnikaRepository: lessons, cardSeen: seen,
        random: Random(34), now: () => DateTime(2026,11,14),
      )),
    ));
    await tester.pumpAndSettle();
    final error = find.byKey(const Key('classic-error'));
    expect(error, findsNothing, reason: error.evaluate().isEmpty ? '' : tester.widget<Text>(error).data);
    Future<void> tap(String key) async {
      final finder = find.byKey(Key(key));
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(finder, 500, maxScrolls: 40);
      }
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tap('tehnika-card-done');
    for (var i=0;i<1;i++) {
      await tap('cycle-start');
      await tap('cycle-ready');
      await tap('cycle-answer-done');
      await tap('cycle-verdict-taken');
    }
    final events = (await log.readAll()).events.whereType<AnswerEvent>().toList();
    expect(events.length,1);
    final pool = {for (final q in await repo.loadAll()) q.id:q};
    for (final event in events) {
      final q=pool[event.questionId]!;
      expect(q.packDate,isNotNull);
      expect(DateTime.parse(q.packDate!).year,greaterThanOrEqualTo(2022));
      expect(q.corpus,Corpus.gq);
    }
    expect(tester.takeException(),isNull);
  });
}
