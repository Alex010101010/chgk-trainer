import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Questions implements QuestionRepository {
  @override
  Future<List<Question>> loadAll() async => const [
        Question(
            id: 'home-test',
            corpus: Corpus.gq,
            question: 'Вопрос',
            answer: 'Ответ'),
      ];
}

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('главная: ширина $width, масштаб текста $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: buildDarkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const HomeScreen(),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('home-profile')), findsOneWidget);
        expect(find.byKey(const Key('home-update')), findsNothing);
        await tester.scrollUntilVisible(
            find.byKey(const Key('home-tehnika')), 200);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('home-tehnika')).hitTestable(),
            findsOneWidget);
      });
    }
  }

  testWidgets('сыгранный вопрос дня открывает результат из новой карточки',
      (tester) async {
    final now = DateTime.now();
    final log = MemoryEventLog();
    await log.append(AnswerEvent(
      ts: now.millisecondsSinceEpoch,
      day: localDay(now),
      questionId: 'home-test',
      corpus: Corpus.gq,
      mode: GameMode.daily,
      verdict: Verdict.taken,
      secondsUsed: 20,
    ));
    await tester.pumpWidget(JournalScope(
      log: log,
      child: MaterialApp(
          theme: buildDarkTheme(), home: HomeScreen(repository: _Questions())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Сегодня: взял!'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-daily')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-result')), findsOneWidget);
    expect(find.text('Ответ: Ответ'), findsOneWidget);
  });
}
