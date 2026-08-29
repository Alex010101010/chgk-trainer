import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../model/question.dart';

const String kQuestionsAsset = 'assets/questions.json';

/// Ассет не собран или собран не до конца. Текст сообщения — инструкция:
/// экран показывает его как есть, а «вопросы кончились» и «ассет не собран»
/// обязаны выглядеть по-разному.
class QuestionAssetException implements Exception {
  final String message;
  const QuestionAssetException(this.message);

  @override
  String toString() => message;
}

abstract class QuestionRepository {
  Future<List<Question>> loadAll();
}

/// Читает `assets/questions.json` целиком. За интерфейсом переход на шарды —
/// замена реализации, а не переделка режима.
///
/// Честная цена: на web у `compute()` нет изолята, декод подвесит UI.
class AssetQuestionRepository implements QuestionRepository {
  List<Question>? _cache;

  @override
  Future<List<Question>> loadAll() async {
    if (_cache != null) return _cache!;
    final String raw;
    try {
      raw = await rootBundle.loadString(kQuestionsAsset);
    } catch (e) {
      throw const QuestionAssetException(
        'Ассет вопросов не собран. Выполни: python3 scripts/build_app_assets.py',
      );
    }
    final parsed = await compute(parseQuestionAsset, raw);
    _cache = parsed;
    return parsed;
  }
}

/// Верхнего уровня — уезжает в изолят через `compute`.
List<Question> parseQuestionAsset(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (e) {
    throw const QuestionAssetException(
      'Ассет вопросов не читается. Пересобери: python3 scripts/build_app_assets.py',
    );
  }
  if (decoded is! Map) {
    throw const QuestionAssetException(
      'Ассет вопросов не в том формате. Пересобери: python3 scripts/build_app_assets.py',
    );
  }
  final list = decoded['questions'];
  final count = decoded['count'];
  if (list is! List) {
    throw const QuestionAssetException(
      'В ассете нет списка вопросов. Пересобери: python3 scripts/build_app_assets.py',
    );
  }
  // `count` ловит обрезанный файл: без сверки усечённый ассет распарсился бы
  // как валидный короткий список и режим молча пошёл бы по огрызку корпуса.
  if (count is! int || count != list.length) {
    throw QuestionAssetException(
      'Ассет вопросов обрезан: заявлено $count, прочитано ${list.length}. '
      'Пересобери: python3 scripts/build_app_assets.py',
    );
  }
  final questions = list.map(Question.fromJson).whereType<Question>().toList();
  // Пустой список молча не возвращаем никогда.
  if (questions.isEmpty) {
    throw const QuestionAssetException(
      'Ассет вопросов пуст. Пересобери: python3 scripts/build_app_assets.py',
    );
  }
  return questions;
}
