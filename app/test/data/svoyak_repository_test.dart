import 'dart:convert';

import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/data/svoyak_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _q(int n) => {
      'id': 'si-$n',
      'nominal': n,
      'question': 'Вопрос за $n',
      'answer': 'Ответ $n',
      'acceptVariants': ['ответ $n'],
      'sources': <String>[],
    };

Map<String, dynamic> _theme(String id, List<int> nominals) => {
      'id': id,
      'title': 'Тема $id',
      'pack': 'Кубок',
      'year': '2024',
      'questions': [for (final n in nominals) _q(n)],
    };

String _asset(List<Map<String, dynamic>> themes, {int? count}) =>
    jsonEncode({'v': 1, 'count': count ?? themes.length, 'themes': themes});

void main() {
  test('тема читается, вопросы по возрастанию номинала', () {
    final themes = parseSvoyakAsset(_asset([
      _theme('1', [30, 10, 50, 20, 40])
    ]));
    expect(themes.single.questions.map((q) => q.nominal), [10, 20, 30, 40, 50]);
    expect(themes.single.questions.first.question.id, 'si-10');
    expect(themes.single.year, '2024');
  });

  test('тема не из пяти вопросов отбрасывается, остальные читаются', () {
    final themes = parseSvoyakAsset(_asset([
      _theme('1', [10, 20, 30, 40, 50]),
      _theme('2', [10, 20, 30, 40]),
    ]));
    expect(themes.map((t) => t.id), ['1']);
  });

  test('обрезанный и пустой ассет — ошибка, а не тихий огрызок', () {
    expect(
        () => parseSvoyakAsset(_asset([
              _theme('1', [10, 20, 30, 40, 50])
            ], count: 2)),
        throwsA(isA<QuestionAssetException>()));
    expect(
        () => parseSvoyakAsset(_asset([
              _theme('2', [10])
            ])),
        throwsA(isA<QuestionAssetException>()));
  });
  test('package identity and explicit variants survive parsing', () {
    final a = _theme('1', [10, 20, 30, 40, 50])
      ..addAll({
        'packId': 'team',
        'packGroup': 'Крафт №14',
        'packVariant': 'Командная'
      });
    final b = _theme('2', [10, 20, 30, 40, 50])
      ..addAll({
        'packId': 'individual',
        'packGroup': 'Крафт №14',
        'packVariant': 'Индивидуальная'
      });
    final themes = parseSvoyakAsset(_asset([a, b]));
    expect(themes[0].packKey, isNot(themes[1].packKey));
    expect(themes[0].groupKey, themes[1].groupKey);
    expect(themes[0].packVariant, 'Командная');
    final legacy = parseSvoyakAsset(_asset([
      _theme('3', [10, 20, 30, 40, 50])
    ])).single;
    expect(legacy.packKey, 'Кубок');
    expect(legacy.groupTitle, 'Кубок');
  });
}
