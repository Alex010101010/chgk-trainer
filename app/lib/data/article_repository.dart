import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

const String kArticlesAsset = 'assets/articles.json';

/// Справка по клише: что это за факт и как его обыгрывают в вопросах.
/// Текст — проза статьи до первого вопроса, см. `structure_bingo_articles.py`.
class Article {
  final String theme;
  final String text;

  /// Откуда взята статья: `wiki` или `index`. Показывается как подпись.
  final String source;
  final String? url;

  const Article({
    required this.theme,
    required this.text,
    required this.source,
    this.url,
  });

  static Article? fromJson(Object? json) {
    if (json is! Map) return null;
    final theme = json['theme'];
    final text = json['text'];
    if (theme is! String || text is! String || text.isEmpty) return null;
    return Article(
      theme: theme,
      text: text,
      source: json['source'] is String ? json['source'] as String : 'wiki',
      url: json['url'] is String ? json['url'] as String : null,
    );
  }
}

/// Ассет справок не собран или не читается. Отдельно от «статьи нет»: тема без
/// статьи в корпусе бывает (одна на 333), и путать её с несобранным ассетом
/// нельзя — в первом случае чинить нечего, во втором надо запустить сборку.
class ArticleAssetException implements Exception {
  final String message;
  const ArticleAssetException(this.message);

  @override
  String toString() => message;
}

/// Читает `assets/articles.json` — 356 КБ, лениво и один раз за запуск.
class ArticleRepository {
  Map<String, Article>? _cache;

  Future<Map<String, Article>> loadAll() async {
    if (_cache != null) return _cache!;
    final String raw;
    try {
      raw = await rootBundle.loadString(kArticlesAsset);
    } catch (e) {
      throw const ArticleAssetException(
        'Ассет справок не собран. Выполни: python3 scripts/build_app_assets.py',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      throw const ArticleAssetException(
        'Ассет справок не читается. Пересобери: '
        'python3 scripts/build_app_assets.py',
      );
    }
    final list = decoded is Map ? decoded['articles'] : null;
    if (list is! List) {
      throw const ArticleAssetException(
        'В ассете справок нет списка статей. Пересобери: '
        'python3 scripts/build_app_assets.py',
      );
    }
    final byTheme = <String, Article>{};
    for (final item in list) {
      final a = Article.fromJson(item);
      if (a != null) byTheme[a.theme] = a;
    }
    _cache = byTheme;
    return byTheme;
  }
}
