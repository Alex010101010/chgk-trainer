import 'package:flutter/material.dart';

import '../data/article_repository.dart';
import '../data/handout_store.dart';
import '../journal/theme_notes.dart';
import 'handout_image.dart';
import 'theme_note_field.dart';

/// Текст справки по клише: что это за факт и как его обыгрывают.
///
/// Абзац, начинающийся с `## `, — заголовок раздела статьи; без выделения он
/// читается как оборванное предложение посреди текста.
///
/// Три случая разведены явно: статья есть, статьи нет, ассет не собран.
/// Последний чинится командой сборки, а не поиском статьи, — и молчать о нём
/// нельзя: несобранный ассет выглядел бы как «справок в приложении нет».
class ArticleBody extends StatelessWidget {
  final Article? article;
  final String? error;

  /// Своя реалия (T24): статьи у неё нет и быть не может. «Статьи не нашлось»
  /// здесь было бы ложью — искать нечего, клише завёл сам игрок.
  final bool custom;

  const ArticleBody({super.key, this.article, this.error, this.custom = false});

  static const String _headingMark = '## ';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (error != null) {
      return Text(error!,
          key: const Key('article-error'), style: text.bodyLarge);
    }
    if (custom) {
      return Text(
        'Своя реалия — в корпусе бинго её нет. Что это такое, ты написал '
        'сам в заметке ниже.',
        key: const Key('article-custom'),
        style: text.bodyLarge,
      );
    }
    if (article == null) {
      return Text(
        'Справки по этому клише нет — статьи о нём не нашлось. '
        'Что это такое, придётся достраивать по вопросам.',
        key: const Key('article-missing'),
        style: text.bodyLarge,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._paragraphs(context),
        if (article!.images.isNotEmpty) ...[
          const SizedBox(height: 16),
          ArticleImages(files: article!.images),
        ],
        const SizedBox(height: 16),
        Text(_sourceLabel(article!.source), style: text.bodySmall),
      ],
    );
  }

  List<Widget> _paragraphs(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final out = <Widget>[];
    for (final p in article!.text.split('\n\n')) {
      if (p.isEmpty) continue;
      final heading = p.startsWith(_headingMark);
      out.add(Padding(
        padding: EdgeInsets.only(top: out.isEmpty ? 0 : (heading ? 18 : 12)),
        child: Text(
          heading ? p.substring(_headingMark.length) : p,
          style: heading ? text.titleMedium : text.bodyLarge,
        ),
      ));
    }
    return out;
  }

  static String _sourceLabel(String source) =>
      source == 'wiki' ? 'Из вики бинго' : 'Из статьи об этом клише';
}

/// Справка, открытая тапом по клетке сетки или строке справочника, — во весь
/// низ экрана.
class ArticleSheet extends StatelessWidget {
  final String theme;
  final Article? article;
  final String? error;

  /// Своя реалия, а не клише корпуса.
  final bool custom;

  /// Заметка на клише. `null` — поля не будет: писать некуда, если журнал
  /// экрану не передали.
  final ThemeNotes? notes;

  const ArticleSheet({
    super.key,
    required this.theme,
    this.article,
    this.error,
    this.custom = false,
    this.notes,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(theme,
                  key: const Key('article-title'),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              ArticleBody(article: article, error: error, custom: custom),
              if (notes case final notes?) ...[
                const SizedBox(height: 24),
                ThemeNoteField(theme: theme, notes: notes, custom: custom),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Иллюстрации статьи (T14) лентой под текстом. Лента, а не столбик: у
/// «Гюстава Курбе» их 23, и столбиком справка превратилась бы в галерею с
/// текстом где-то наверху. Тап открывает картинку на весь экран.
class ArticleImages extends StatelessWidget {
  final List<String> files;

  const ArticleImages({super.key, required this.files});

  static const double _height = 120;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const Key('article-images'),
        height: _height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: files.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _Thumb(file: files[i], height: _height),
        ),
      );
}

class _Thumb extends StatefulWidget {
  final String file;
  final double height;

  const _Thumb({required this.file, required this.height});

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late Future<ImageProvider> _image = HandoutStore.instance.resolve(widget.file);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Не загрузилась — значок с повтором по тапу, а не баннер, как у
    // раздатки: текст справки от иллюстрации не зависит.
    Widget missing() => InkWell(
          key: const Key('article-image-missing'),
          onTap: () => setState(() {
            _image = HandoutStore.instance.resolve(widget.file);
          }),
          child: Container(
            width: widget.height,
            color: scheme.surfaceContainerHighest,
            child: Icon(Icons.image_not_supported_outlined,
                color: scheme.onSurfaceVariant),
          ),
        );
    return FutureBuilder<ImageProvider>(
      future: _image,
      builder: (context, snap) {
        if (snap.hasError) return missing();
        final image = snap.data;
        if (image == null) {
          return SizedBox(
            width: widget.height,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return GestureDetector(
          key: const Key('article-image-open'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => HandoutViewer(image: image),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(
              image: image,
              height: widget.height,
              fit: BoxFit.fitHeight,
              errorBuilder: (_, __, ___) => missing(),
            ),
          ),
        );
      },
    );
  }
}
