import 'package:flutter/material.dart';

import '../data/article_repository.dart';

/// Карточка справки по клише: что это за факт и как его обыгрывают.
///
/// Абзац, начинающийся с `## `, — заголовок раздела статьи; без выделения он
/// читается как оборванное предложение посреди текста.
class ArticleSheet extends StatelessWidget {
  final String theme;
  final Article? article;

  /// Ассет справок не прочитался. Показывается вместо текста: «статьи нет» и
  /// «сборка не запускалась» чинятся по-разному.
  final String? error;

  const ArticleSheet({
    super.key,
    required this.theme,
    this.article,
    this.error,
  });

  static const String _headingMark = '## ';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
              Text(theme, key: const Key('article-title'), style: text.headlineSmall),
              const SizedBox(height: 12),
              if (error != null)
                Text(error!,
                    key: const Key('article-error'), style: text.bodyLarge)
              else if (article == null)
                Text(
                  'Справки по этому клише нет — статьи о нём не нашлось. '
                  'Что это такое, придётся достраивать по вопросам.',
                  key: const Key('article-missing'),
                  style: text.bodyLarge,
                )
              else
                ..._paragraphs(context),
              if (article != null) ...[
                const SizedBox(height: 16),
                Text(_sourceLabel(article!.source), style: text.bodySmall),
              ],
            ],
          ),
        ),
      ),
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
