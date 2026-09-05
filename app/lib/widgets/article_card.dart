import 'package:flutter/material.dart';

import '../data/article_repository.dart';
import 'article_sheet.dart';

/// Свёрнутая справка по клише под раскрытым ответом (T14).
///
/// Свёрнутая, а не раскрытая: разбор вопроса читают ради ответа и
/// комментария, и статья на пол-экрана поверх них мешала бы. Тап делает
/// чтение выбором — а выбор здесь и есть смысл: справку открывают через
/// пять секунд после промаха на этом клише, а не «когда-нибудь потом».
///
/// Текст грузится при первом раскрытии: на вопросах, где справку не открыли,
/// ассет в 356 КБ читать незачем.
class ArticleCard extends StatefulWidget {
  final String theme;
  final ArticleRepository repository;

  const ArticleCard({
    super.key,
    required this.theme,
    required this.repository,
  });

  @override
  State<ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<ArticleCard> {
  bool _open = false;
  bool _loaded = false;
  Article? _article;
  String? _error;

  Future<void> _toggle() async {
    final open = !_open;
    setState(() => _open = open);
    if (!open || _loaded) return;
    try {
      final all = await widget.repository.loadAll();
      if (!mounted) return;
      setState(() {
        _article = all[widget.theme];
        _loaded = true;
      });
    } on ArticleAssetException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('cycle-article-toggle'),
            onTap: _toggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Клише: ${widget.theme}',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      color: scheme.primary),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              key: const Key('cycle-article-body'),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _loaded
                  ? ArticleBody(article: _article, error: _error)
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
