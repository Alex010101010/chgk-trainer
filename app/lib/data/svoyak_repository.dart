import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../model/svoyak.dart';
import 'question_repository.dart' show QuestionAssetException;

const String kSvoyakAsset = 'assets/svoyak.json';

abstract class SvoyakRepository {
  Future<List<SvoyakTheme>> loadAll();
}

/// Читает `assets/svoyak.json` (T6) — отдельный ассет, а не корпус в
/// `questions.json`: иначе вопросы «Своей игры» попали бы в раунды «Классики».
class AssetSvoyakRepository implements SvoyakRepository {
  List<SvoyakTheme>? _cache;

  @override
  Future<List<SvoyakTheme>> loadAll() async {
    if (_cache != null) return _cache!;
    final String raw;
    try {
      raw = await rootBundle.loadString(kSvoyakAsset);
    } catch (e) {
      throw const QuestionAssetException(
        'Ассет «Своей игры» не собран. Выполни: python3 scripts/build_app_assets.py',
      );
    }
    final parsed = await compute(parseSvoyakAsset, raw);
    _cache = parsed;
    return parsed;
  }
}

/// Верхнего уровня — уезжает в изолят через `compute`.
List<SvoyakTheme> parseSvoyakAsset(String raw) {
  const rebuild = 'Пересобери: python3 scripts/build_app_assets.py';
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (e) {
    throw const QuestionAssetException('Ассет «Своей игры» не читается. $rebuild');
  }
  if (decoded is! Map || decoded['themes'] is! List) {
    throw const QuestionAssetException('Ассет «Своей игры» не в том формате. $rebuild');
  }
  final list = decoded['themes'] as List;
  final count = decoded['count'];
  // Как у вопросов: `count` ловит обрезанный файл.
  if (count is! int || count != list.length) {
    throw QuestionAssetException(
      'Ассет «Своей игры» обрезан: заявлено $count, прочитано ${list.length}. $rebuild',
    );
  }
  final themes = list.map(SvoyakTheme.fromJson).whereType<SvoyakTheme>().toList();
  if (themes.isEmpty) {
    throw const QuestionAssetException('Ассет «Своей игры» пуст. $rebuild');
  }
  return themes;
}
