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

    await tester.tap(find.text('Классика'));
    await tester.pumpAndSettle();

    expect(find.text('Скоро'), findsOneWidget);
  });
}
