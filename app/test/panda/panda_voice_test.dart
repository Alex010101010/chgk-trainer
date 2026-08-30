import 'dart:math';

import 'package:chgk_trainer/data/panda_lines_repository.dart';
import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/model/panda_line.dart';
import 'package:chgk_trainer/panda/panda_voice.dart';
import 'package:flutter_test/flutter_test.dart';

const _moments = [
  PandaMoment(
    id: 'verdict.took',
    name: 'Взял',
    lines: ['первая', 'вторая', 'третья'],
    rare: ['искренняя'],
  ),
  PandaMoment(
    id: 'streak.alive',
    name: 'Стрик',
    lines: ['{n} дней подряд'],
    rare: [],
  ),
];

/// Голос, который всегда подаёт голос: молчание проверяется отдельно, а в
/// остальных тестах оно только зашумляет результат.
PandaVoice _loud({int rareOneIn = 30, int seed = 1}) => PandaVoice(
      _moments,
      random: Random(seed),
      speakPercent: 100,
      rareOneIn: rareOneIn,
    );

void main() {
  test('незнакомый момент — молчание, а не исключение', () {
    expect(_loud().lineFor('нет.такого'), isNull);
  });

  test('молчание примерно в половине моментов', () {
    final voice =
        PandaVoice(_moments, random: Random(7), speakPercent: 50, rareOneIn: 30);
    var spoken = 0;
    for (var i = 0; i < 2000; i++) {
      if (voice.lineFor('verdict.took') != null) spoken++;
    }
    // Полоса широкая намеренно: проверяем порядок величины, а не генератор
    // случайных чисел.
    expect(spoken, greaterThan(800));
    expect(spoken, lessThan(1200));
  });

  test('бюджет искренности — примерно одна редкая из тридцати', () {
    final voice = _loud(seed: 3);
    var rare = 0;
    for (var i = 0; i < 3000; i++) {
      if (voice.lineFor('verdict.took') == 'искренняя') rare++;
    }
    expect(rare, greaterThan(50));
    expect(rare, lessThan(160));
  });

  test('никогда не повторяет ту же строку подряд', () {
    final voice = _loud(rareOneIn: 1000000, seed: 11);
    String? prev;
    for (var i = 0; i < 500; i++) {
      final line = voice.lineFor('verdict.took');
      expect(line, isNotNull);
      expect(line, isNot(prev));
      prev = line;
    }
  });

  test('подставляет переменные', () {
    expect(_loud().lineFor('streak.alive', vars: {'n': '5'}), '5 дней подряд');
  });

  test('строка с неподставленной переменной не показывается', () {
    expect(_loud().lineFor('streak.alive'), isNull);
  });

  test('молчащий голос молчит всегда', () {
    final voice = PandaVoice.silent();
    for (var i = 0; i < 50; i++) {
      expect(voice.lineFor('verdict.took'), isNull);
    }
  });

  group('разбор ассета', () {
    test('битый JSON — понятная ошибка', () {
      expect(() => parsePandaLinesAsset('{['),
          throwsA(isA<QuestionAssetException>()));
    });

    test('нет списка moments — понятная ошибка', () {
      expect(() => parsePandaLinesAsset('{"v":1}'),
          throwsA(isA<QuestionAssetException>()));
    });

    test('пустой банк — ошибка, а не тихое молчание', () {
      expect(() => parsePandaLinesAsset('{"v":1,"moments":[]}'),
          throwsA(isA<QuestionAssetException>()));
    });

    test('кривая запись выбрасывается, здоровые остаются', () {
      final moments = parsePandaLinesAsset(
          '{"v":1,"moments":[{"id":"a","name":"A","lines":["раз"]},'
          '{"id":"","name":"пусто","lines":["два"]},'
          '{"id":"c","name":"C","lines":[],"rare":[]}]}');
      expect(moments.map((m) => m.id), ['a']);
    });
  });
}
