import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../panda/panda_voice.dart';

/// Реплика панды в комикс-пузыре.
///
/// Пузырь намеренно не похож на карточки и тосты приложения: он всегда
/// светлый с тёмным текстом и хвостиком вниз-влево, в обеих темах одинаково.
/// Так с одного взгляда видно, что говорит ОН, а не интерфейс.
///
/// Появляется не сразу, а через паузу — комедийный тайминг почти бесплатно:
/// сначала игрок видит свой результат, и только потом панда его комментирует.
class PandaBubble extends StatefulWidget {
  final String moment;
  final Map<String, String> vars;

  /// Пауза перед репликой. Вынесена в параметр ради тестов и на случай,
  /// если на обкатке окажется, что полсекунды мало или много.
  final Duration delay;

  const PandaBubble({
    super.key,
    required this.moment,
    this.vars = const {},
    this.delay = const Duration(milliseconds: 700),
  });

  @override
  State<PandaBubble> createState() => _PandaBubbleState();
}

class _PandaBubbleState extends State<PandaBubble> {
  String? _line;
  bool _visible = false;
  Timer? _timer;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Строку спрашиваем ровно один раз: иначе на каждой перерисовке панда
    // говорила бы новое, а половину показов молчала бы прямо посреди фразы.
    if (_asked) return;
    _asked = true;
    _line = PandaScope.maybeOf(context)?.lineFor(widget.moment, vars: widget.vars);
    if (_line == null) return;
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = _line;
    if (line == null) return const SizedBox.shrink();
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.12),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        // Row + Flexible, а не Align: Align растягивается до максимума, и
        // пузырь на короткой реплике уезжал во всю ширину экрана. Здесь
        // пузырь обнимает текст и переносит строки, только упёршись в край.
        child: Row(
          children: [
            Flexible(
              child: CustomPaint(
                painter: _BubblePainter(),
                child: Padding(
                  // Нижний отступ больше на высоту хвостика — иначе текст
                  // наезжает на него.
                  padding:
                      const EdgeInsets.fromLTRB(18, 14, 18, 14 + _tailHeight),
                  child: Text(
                    line,
                    key: const Key('panda-line'),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: PandaPalette.ink,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const double _tailHeight = 16;
const double _tailWidth = 26;
const double _tailLeft = 22;
const double _radius = 18;

/// Пузырь рисуется одним контуром, а не плашкой с приклеенным треугольником:
/// иначе обводка идёт по стыку и хвостик выглядит отдельной фигурой.
class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final b = h - _tailHeight; // низ самого пузыря, без хвостика
    final path = Path()
      ..moveTo(_radius, 0)
      ..lineTo(w - _radius, 0)
      ..arcToPoint(Offset(w, _radius), radius: const Radius.circular(_radius))
      ..lineTo(w, b - _radius)
      ..arcToPoint(Offset(w - _radius, b), radius: const Radius.circular(_radius))
      ..lineTo(_tailLeft + _tailWidth, b)
      ..lineTo(_tailLeft + 4, h)
      ..lineTo(_tailLeft + 6, b)
      ..lineTo(_radius, b)
      ..arcToPoint(Offset(0, b - _radius), radius: const Radius.circular(_radius))
      ..lineTo(0, _radius)
      ..arcToPoint(const Offset(_radius, 0), radius: const Radius.circular(_radius))
      ..close();

    canvas.drawPath(path, Paint()..color = PandaPalette.paper);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = PandaPalette.ink,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) => false;
}
