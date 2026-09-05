import 'package:flutter/material.dart';

import '../data/article_repository.dart';
import '../journal/theme_notes.dart';
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

  const ArticleBody({super.key, this.article, this.error});

  static const String _headingMark = '## ';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (error != null) {
      return Text(error!,
          key: const Key('article-error'), style: text.bodyLarge);
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

  /// Заметка на клише. `null` — поля не будет: писать некуда, если журнал
  /// экрану не передали.
  final ThemeNotes? notes;

  const ArticleSheet({
    super.key,
    required this.theme,
    this.article,
    this.error,
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
              ArticleBody(article: article, error: error),
              if (notes case final notes?) ...[
                const SizedBox(height: 24),
                ThemeNoteField(theme: theme, notes: notes),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
