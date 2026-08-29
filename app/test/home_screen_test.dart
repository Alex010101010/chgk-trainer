import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chgk_trainer/screens/home_screen.dart';

void main() {
  testWidgets('главный экран показывает три режима и открывает заглушку',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('Классика'), findsOneWidget);
    expect(find.text('Тренажёр рассуждений'), findsOneWidget);
    expect(find.text('Бинго'), findsOneWidget);

    // «Классика» ведёт уже в режим — это проверяет classic_screen_test;
    // здесь остаются два пункта, которые пока заглушки.
    await tester.tap(find.text('Бинго'));
    await tester.pumpAndSettle();

    expect(find.text('Скоро'), findsOneWidget);
  });
}
