import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/cycle/cycle_controller.dart';
import 'package:chgk_trainer/cycle/question_cycle.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets('длинный вопрос, раздатка и клавиатура: масштаб $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      AnswerEvent? result;
      await tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Классика')),
          body: QuestionCycle(
            question: Question(
                id: 'layout',
                corpus: Corpus.gq,
                question:
                    List.filled(30, 'Длинный вопрос для проверки прокрутки.')
                        .join(' '),
                handoutText: 'Текстовая раздатка',
                answer: 'Ответ',
                comment: 'Объяснение'),
            config: const CycleConfig(mode: GameMode.classic),
            onFinished: (event) => result = event,
          ),
        ),
      ));
      await tester.pump();
      expect(
          find.byKey(const Key('cycle-start')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('cycle-start')));
      await tester.pump();
      expect(
          find.byKey(const Key('cycle-ready')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('cycle-ready')));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.enterText(
          find.byKey(const Key('cycle-answer-field')), 'Моя версия');
      expect(find.byKey(const Key('cycle-answer-done')).hitTestable(),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('cycle-answer-done')));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('Моя версия'), findsOneWidget);
      expect(find.text('Текстовая раздатка'), findsOneWidget);
      expect(find.byKey(const Key('cycle-verdict-almost')).hitTestable(),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('cycle-verdict-almost')));
      await tester.pump();
      expect(result?.userAnswer, 'Моя версия');
      expect(result?.verdict, Verdict.almost);
      expect(tester.takeException(), isNull);
    });
  }
}
