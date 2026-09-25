import 'package:flutter/material.dart';

import '../data/handout_store.dart';

/// Каталог раздаток в ассетах сборки. Собирается
/// `scripts/build_handout_assets.py`; в APK больше не едет (T30) — CI
/// выкладывает его на Pages, откуда картинки берёт [HandoutStore].
const String kHandoutDir = 'assets/handouts';

/// Раздаточный материал вопроса (T20).
///
/// Показывается всюду, где виден текст вопроса: на живой игре раздатку выдают
/// до отсчёта и не отбирают ни на минуте, ни при разборе.
///
/// По тапу открывается на весь экран: в наборе есть схема 1080×946 и текстовая
/// полоса 600×59 — втиснутые в ширину телефона они не читаются, а раздатка,
/// которую не разглядеть, делает вопрос невзятым не по вине игрока.
class HandoutImage extends StatefulWidget {
  final String file;

  const HandoutImage({super.key, required this.file});

  @override
  State<HandoutImage> createState() => _HandoutImageState();
}

class _HandoutImageState extends State<HandoutImage> {
  late Future<ImageProvider> _image;

  @override
  void initState() {
    super.initState();
    _image = HandoutStore.instance.resolve(widget.file);
  }

  void _retry() {
    // Блоком, а не стрелкой: стрелка вернула бы Future из setState, и Flutter
    // отверг бы повтор — кнопка не делала бы ничего.
    setState(() {
      _image = HandoutStore.instance.resolve(widget.file);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider>(
      future: _image,
      builder: (context, snap) {
        if (snap.hasError) return _missing(context);
        final image = snap.data;
        if (image == null) {
          return const SizedBox(
            key: Key('handout-loading'),
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Semantics(
          label: 'Раздаточный материал',
          button: true,
          child: GestureDetector(
            key: const Key('handout-open'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _HandoutViewer(image: image),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              // Превью, а не полный размер: картинка 1080×946, растянутая по
              // ширине экрана, уводит текст вопроса под сгиб. Разглядывают её тапом.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Image(
                  image: image,
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
      },
    );
  }

  /// Молчать нельзя: без картинки вопрос не берётся, и игрок должен понимать,
  /// что дело не в нём. С T30 это обычный случай — нет сети при первом показе.
  Widget _missing(BuildContext context) => Container(
        key: const Key('handout-missing'),
        padding: const EdgeInsets.all(12),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Раздатка не загрузилась — нужен интернет. Без неё вопрос не берётся',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
            TextButton(
              key: const Key('handout-retry'),
              onPressed: _retry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
}

class _HandoutViewer extends StatelessWidget {
  final ImageProvider image;

  const _HandoutViewer({required this.image});

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
              child: Center(child: Image(image: image, fit: BoxFit.contain)),
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
