import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../model/tehnika.dart';
import 'question_repository.dart';

const String kTehnikiAsset = 'assets/tehniki.json';

abstract class TehnikaRepository {
  Future<List<Tehnika>> loadAll();
}

class AssetTehnikaRepository implements TehnikaRepository {
  List<Tehnika>? _cache;

  @override
  Future<List<Tehnika>> loadAll() async {
    if (_cache != null) return _cache!;
    final String raw;
    try {
      raw = await rootBundle.loadString(kTehnikiAsset);
    } catch (e) {
      throw const QuestionAssetException('Ассет приёмов не найден: $kTehnikiAsset');
    }
    final parsed = parseTehnikiAsset(raw);
    _cache = parsed;
    return parsed;
  }
}

/// Приёмы коммитятся руками, поэтому пустой список — это опечатка в файле,
/// а не «приёмов пока нет».
List<Tehnika> parseTehnikiAsset(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (e) {
    throw const QuestionAssetException('Ассет приёмов не читается (битый JSON)');
  }
  final list = decoded is Map ? decoded['tehniki'] : null;
  if (list is! List) {
    throw const QuestionAssetException('В ассете приёмов нет списка `tehniki`');
  }
  final tehniki = list.map(Tehnika.fromJson).whereType<Tehnika>().toList();
  if (tehniki.isEmpty) {
    throw const QuestionAssetException('Ассет приёмов пуст');
  }
  return tehniki;
}
