import 'dart:math';

import 'package:flutter/material.dart';

/// Ниже этого кегля не опускаемся: нечитаемая клетка хуже обрезанной, за краем
/// работает `TextOverflow.ellipsis`.
const double kGridLabelMinFontSize = 9;

/// Как набрать подписи в сетке клеток: кегль и предел строк — **одни на всю
/// сетку сразу**. Свой размер в каждой клетке дал бы девять разных, и сетка
/// стала бы рябой; поэтому берётся наибольший кегль, при котором в клетку
/// целиком влезает самое длинное название из [labels].
///
/// Имена тем неравномерны: две трети короче 16 символов, но хвост доходит до
/// полусотни («Физическая невозможность смерти в сознании живущего»), и на
/// фиксированном кегле обрезается именно он.
({double fontSize, int maxLines}) gridLabelStyle(
  BuildContext context, {
  required List<String> labels,
  required TextStyle style,
  required double maxWidth,
  required double maxHeight,
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final floor = style.copyWith(fontSize: kGridLabelMinFontSize);
  var size = style.fontSize ?? 13;
  while (size > kGridLabelMinFontSize) {
    final stepStyle = style.copyWith(fontSize: size);
    final fits = labels
        .every((l) => _fits(l, stepStyle, floor, scaler, maxWidth, maxHeight));
    if (fits) break;
    size -= 1;
  }
  final line =
      _measure('X', style.copyWith(fontSize: size), scaler, maxWidth).height;
  return (
    fontSize: size,
    // Предел строк — сколько их помещается по высоте. Без него текст, не
    // влезший даже на минимальном кегле, вылезал бы за клетку вместо «…».
    maxLines: line <= 0 ? 1 : max(1, (maxHeight / line).floor()),
  );
}

/// Размер набранной подписи. Ширина может выйти за [width]: слово длиннее
/// строки не переносится, и в клетку оно не влезает при любой её высоте.
Size _measure(String text, TextStyle style, TextScaler scaler, double width) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    textScaler: scaler,
  )..layout(maxWidth: width);
  final size = painter.size;
  painter.dispose();
  return size;
}

bool _fits(String text, TextStyle style, TextStyle floor, TextScaler scaler,
    double maxWidth, double maxHeight) {
  if (maxWidth <= 0 || maxHeight <= 0) return true;
  // Слово шире клетки Flutter разрывает по буквам («невозможност / ь») — по
  // высоте такое «влезает», но читается как брак. Считаем невлезшим — но
  // только если уменьшение кегля его спасёт: слово, не влезающее и на
  // минимальном, ужало бы всю сетку впустую.
  for (final word in text.split(' ')) {
    if (_measure(word, style, scaler, double.infinity).width > maxWidth &&
        _measure(word, floor, scaler, double.infinity).width <= maxWidth) {
      return false;
    }
  }
  return _measure(text, style, scaler, maxWidth).height <= maxHeight;
}
