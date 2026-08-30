import 'dart:math';

import 'package:chgk_trainer/model/panda_line.dart';
import 'package:chgk_trainer/panda/panda_voice.dart';
import 'package:chgk_trainer/widgets/panda_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _moments = [
  PandaMoment(id: 'm', name: 'M', lines: ['реплика'], rare: []),
  PandaMoment(id: 'vars', name: 'V', lines: ['{n} дней'], rare: []),
];

Widget _wrap(Widget child, {PandaVoice? voice}) {
  final w = MaterialApp(home: Scaffold(body: child));
  return voice == null ? w : PandaScope(voice: voice, child: w);
}

PandaVoice _loud() =>
    PandaVoice(_moments, random: Random(1), speakPercent: 100, rareOneIn: 1000);

void main() {
  testWidgets('реплика появляется не сразу, а после паузы', (tester) async {
    await tester.pumpWidget(_wrap(
      const PandaBubble(moment: 'm', delay: Duration(milliseconds: 700)),
      voice: _loud(),
    ));

    // Пауза — это и есть комедийный тайминг: до неё пузырь прозрачен.
    await tester.pump();
    expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('реплика'), findsOneWidget);
    expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
  });

  testWidgets('без скоупа панда молчит и места не занимает', (tester) async {
    await tester.pumpWidget(_wrap(const PandaBubble(moment: 'm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('panda-line')), findsNothing);
    expect(tester.getSize(find.byType(PandaBubble)), Size.zero);
  });

  testWidgets('молчащий голос — пустое место, а не пустой пузырь',
      (tester) async {
    await tester.pumpWidget(
        _wrap(const PandaBubble(moment: 'm'), voice: PandaVoice.silent()));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(PandaBubble)), Size.zero);
  });

  testWidgets('строка выбирается один раз и не меняется на перерисовке',
      (tester) async {
    final voice = PandaVoice(
      [const PandaMoment(id: 'm', name: 'M', lines: ['раз', 'два'], rare: [])],
      random: Random(5),
      speakPercent: 100,
      rareOneIn: 1000,
    );
    await tester.pumpWidget(_wrap(const PandaBubble(moment: 'm'), voice: voice));
    await tester.pumpAndSettle();

    final first = tester.widget<Text>(find.byKey(const Key('panda-line'))).data;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
        tester.widget<Text>(find.byKey(const Key('panda-line'))).data, first);
  });

  testWidgets('подстановка доезжает до экрана', (tester) async {
    await tester.pumpWidget(_wrap(
      const PandaBubble(moment: 'vars', vars: {'n': '7'}),
      voice: _loud(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('7 дней'), findsOneWidget);
  });
}
