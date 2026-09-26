import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../model/fact.dart';
import 'question_repository.dart';

const String kFactsAsset = 'assets/facts.json';

/// Карточки фактов (T15). Интерфейс — seam для виджет-тестов, как у вопросов.
abstract class FactRepository {
  Future<FactBook> loadAll();
}

FactBook parseFactsAsset(String raw) {
  final decoded = jsonDecode(raw);
  final decks = decoded is Map ? decoded['decks'] : null;
  final cards = decoded is Map ? decoded['cards'] : null;
  if (decks is! List || cards is! List) {
    throw const QuestionAssetException(
      'В ассете фактов нет колод. Пересобери: python3 scripts/build_app_assets.py',
    );
  }
  // `count` ловит обрезанный файл — как у ассета вопросов.
  if (decoded['count'] != cards.length) {
    throw const QuestionAssetException(
      'Ассет фактов обрезан. Пересобери: python3 scripts/build_app_assets.py',
    );
  }
  return FactBook(
    decks: [
      for (final d in decks)
        if (d is Map && d['id'] is String && d['title'] is String)
          FactDeck(id: d['id'] as String, title: d['title'] as String),
    ],
    cards: cards.map(FactCard.fromJson).whereType<FactCard>().toList(),
  );
}

class AssetFactRepository implements FactRepository {
  FactBook? _cache;

  @override
  Future<FactBook> loadAll() async {
    if (_cache != null) return _cache!;
    final String raw;
    try {
      raw = await rootBundle.loadString(kFactsAsset);
    } catch (e) {
      throw const QuestionAssetException(
        'Ассет фактов не собран. Выполни: python3 scripts/build_app_assets.py',
      );
    }
    return _cache = parseFactsAsset(raw);
  }
}
