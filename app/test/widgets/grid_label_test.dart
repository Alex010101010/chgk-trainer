import 'package:chgk_trainer/journal/projections.dart';
import 'package:chgk_trainer/screens/bingo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Самое длинное название в корпусе — на нём и обрезалось.
const _long = 'Физическая невозможность смерти в сознании живущего';

const _short = ['Ковентри', 'Титаник', 'Мы', 'Улисс', 'Кафка'];

/// Ширина сетки в тесте; клетки квадратные, отступы — как в [BingoBoard].
const double _boardWidth = 360;
double _cellInner(double boardWidth) => (boardWidth - 8 * 2) / 3 - (5 + 1) * 2;

Widget _board(List<String> themes, {double width = _boardWidth}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: BingoBoard(
            themes: themes,
            cells: List.filled(themes.length, BingoCell.empty),
          ),
        ),
      ),
    );

List<double> _sizes(WidgetTester tester, List<String> themes) => [
      for (final t in themes)
        tester.widget<Text>(find.text(t)).style!.fontSize!,
    ];

void main() {
  testWidgets('кегль один на всю сетку', (tester) async {
    final themes = [_long, ..._short, 'Ялта', 'Пиррова победа', 'Сизиф'];
    await tester.pumpWidget(_board(themes));

    expect(_sizes(tester, themes).toSet().length, 1,
        reason: 'девять разных размеров — сетка рябит');
  });

  testWidgets('в тесной сетке кегль падает — на всех клетках сразу',
      (tester) async {
    final themes = [_long, ..._short, 'Ялта', 'Пиррова победа', 'Сизиф'];
    await tester.pumpWidget(_board(themes, width: 600));
    final wide = _sizes(tester, themes).first;

    await tester.pumpWidget(_board(themes, width: 240));
    final narrow = _sizes(tester, themes);

    expect(narrow.first, lessThan(wide));
    expect(narrow.toSet().length, 1);
  });

  testWidgets('самое длинное название влезает в клетку целиком',
      (tester) async {
    final themes = [_long, ..._short, 'Ялта', 'Сизиф', 'Годо'];
    await tester.pumpWidget(_board(themes));
    final style = tester.widget<Text>(find.text(_long)).style!;

    final maxLines = tester.widget<Text>(find.text(_long)).maxLines!;
    final painter = TextPainter(
      text: TextSpan(text: _long, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: maxLines,
    )..layout(maxWidth: _cellInner(_boardWidth));
    addTearDown(painter.dispose);

    expect(painter.didExceedMaxLines, isFalse);
    expect(painter.height, lessThanOrEqualTo(_cellInner(_boardWidth)));
  });
}
