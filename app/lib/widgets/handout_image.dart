import 'package:flutter/material.dart';

/// Каталог раздаток в ассетах. Собирается `scripts/build_handout_assets.py`.
const String kHandoutDir = 'assets/handouts';

/// Раздаточный материал вопроса (T20).
///
/// Показывается всюду, где виден текст вопроса: на живой игре раздатку выдают
/// до отсчёта и не отбирают ни на минуте, ни при разборе.
///
/// По тапу открывается на весь экран: в наборе есть схема 1080×946 и текстовая
/// полоса 600×59 — втиснутые в ширину телефона они не читаются, а раздатка,
/// которую не разглядеть, делает вопрос невзятым не по вине игрока.
class HandoutImage extends StatelessWidget {
  final String file;

  const HandoutImage({super.key, required this.file});

  String get _path => '$kHandoutDir/$file';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Раздаточный материал',
      button: true,
      child: GestureDetector(
        key: const Key('handout-open'),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _HandoutViewer(path: _path),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          // Превью, а не полный размер: картинка 1080×946, растянутая по ширине
          // экрана, уводит текст вопроса под сгиб. Разглядывают её тапом.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Image.asset(
              _path,
              fit: BoxFit.contain,
              // Узкая полоса на 59 точек высоты должна остаться полосой,
              // а не растянуться на всё отведённое место.
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stack) => _missing(context),
            ),
          ),
        ),
      ),
    );
  }

  /// Молчать нельзя: без картинки вопрос не берётся, и игрок должен понимать,
  /// что дело не в нём. В норме сюда не попасть — сборщик ассета не соберётся,
  /// если файла нет.
  Widget _missing(BuildContext context) => Container(
        key: const Key('handout-missing'),
        padding: const EdgeInsets.all(12),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Text(
          'Раздатка не загрузилась — вопрос без неё не берётся',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        ),
      );
}

class _HandoutViewer extends StatelessWidget {
  final String path;

  const _HandoutViewer({required this.path});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          // Щипком и двойным тапом — как в любой галерее; за пределы картинки
          // уводить незачем, поэтому масштаб ограничен.
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Center(child: Image.asset(path, fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              key: const Key('handout-close'),
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
