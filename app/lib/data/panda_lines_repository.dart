import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../model/panda_line.dart';
import 'question_repository.dart';

const String kPandaLinesAsset = 'assets/panda_lines.json';

abstract class PandaLinesRepository {
  Future<List<PandaMoment>> loadAll();
}

class AssetPandaLinesRepository implements PandaLinesRepository {
  List<PandaMoment>? _cache;

  @override
  Future<List<PandaMoment>> loadAll() async {
    if (_cache != null) return _cache!;
    final String raw;
    try {
      raw = await rootBundle.loadString(kPandaLinesAsset);
    } catch (e) {
      throw const QuestionAssetException(
          'Ассет реплик не найден: $kPandaLinesAsset');
    }
    final parsed = parsePandaLinesAsset(raw);
    _cache = parsed;
    return parsed;
  }
}

/// Банк реплик коммитится руками из вычитанного черновика, поэтому пустой
/// список — это опечатка в файле, а не «реплик пока нет».
List<PandaMoment> parsePandaLinesAsset(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (e) {
    throw const QuestionAssetException('Ассет реплик не читается (битый JSON)');
  }
  final list = decoded is Map ? decoded['moments'] : null;
  if (list is! List) {
    throw const QuestionAssetException('В ассете реплик нет списка `moments`');
  }
  final moments = list.map(PandaMoment.fromJson).whereType<PandaMoment>().toList();
  if (moments.isEmpty) {
    throw const QuestionAssetException('Ассет реплик пуст');
  }
  return moments;
}
