import 'dart:convert';
import 'dart:io';

import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дампы читаются из репозитория напрямую: ассет объявляет T2b, а проверять
/// парсер на выдуманных данных смысла нет — падает он ровно на настоящих.
List<dynamic> _dump(String name) =>
    jsonDecode(File('../data/$name').readAsStringSync()) as List<dynamic>;

void main() {
  test('round-trip на записи из реального дампа', () {
    final q = Question.fromJson(_dump('gq_clean.json').first)!;
    expect(q.id, 'gq-369291');
    expect(q.corpus, Corpus.gq);
    expect(q.acceptVariants, contains('гамма'));
    expect(Question.fromJson(q.toJson())!.toJson(), q.toJson());
  });

  test('запись без comment/sources/author читается, а не падает', () {
    final q = Question.fromJson({
      'id': 'gq-1',
      'corpus': 'gq',
      'question': 'вопрос',
      'answer': 'ответ',
      'acceptance': null,
      'acceptVariants': ['ответ'],
      'comment': null,
      'sources': [],
      'author': null,
      'theme': null,
    })!;
    expect(q.comment, isNull);
    expect(q.sources, isEmpty);
    expect(q.author, isNull);
    expect(q.theme, isNull);
  });

  test('запись без обязательных полей — null, а не исключение', () {
    expect(Question.fromJson({'id': 'x', 'corpus': 'gq'}), isNull);
    expect(
        Question.fromJson(
            {'id': 'x', 'corpus': 'нет', 'question': 'q', 'answer': 'a'}),
        isNull);
    expect(Question.fromJson('строка'), isNull);
  });

  test('оба корпуса читаются без потерь', () {
    for (final f in ['gq_clean.json', 'bingo_clean.json']) {
      final raw = _dump(f);
      final parsed = raw.map(Question.fromJson).whereType<Question>().length;
      expect(parsed, raw.length, reason: f);
    }
  });

  test('клише есть у бинго-корпуса и нет у gq', () {
    expect(Question.fromJson(_dump('bingo_clean.json').first)!.theme,
        '15 минут славы');
    expect(Question.fromJson(_dump('gq_clean.json').first)!.theme, isNull);
  });
}
