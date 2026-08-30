import 'dart:io';

import 'package:chgk_trainer/data/panda_lines_repository.dart';
import 'package:chgk_trainer/panda/panda_voice.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ассет реплик собран скриптом из вычитанного черновика и лежит в git.
/// Проверяем сам файл, а не подставной: расхождение с черновиком иначе
/// обнаружится только на экране, и только если реплика вообще выпадет.
void main() {
  final raw = File('assets/panda_lines.json').readAsStringSync();

  test('банк читается и содержит все девять моментов', () {
    final moments = parsePandaLinesAsset(raw);
    expect(moments, hasLength(9));
    expect(moments.map((m) => m.id), containsAll(const [
      PandaMoments.took,
      PandaMoments.almost,
      PandaMoments.missed,
      PandaMoments.roundEnd,
    ]));
  });

  test('в каждом моменте хватает строк, чтобы не повторяться', () {
    for (final m in parsePandaLinesAsset(raw)) {
      expect(m.lines.length, greaterThanOrEqualTo(8), reason: m.id);
    }
  });

  test('подстановки объявлены только там, где экран их передаёт', () {
    // {n} и {приём} приходят из T9 и T4b. Если такая скобка заведётся в
    // моменте, который уже на экране, реплика молча исчезнет — тест ловит
    // это раньше игрока.
    const wired = {
      PandaMoments.took,
      PandaMoments.almost,
      PandaMoments.missed,
      PandaMoments.roundEnd,
    };
    for (final m in parsePandaLinesAsset(raw)) {
      if (!wired.contains(m.id)) continue;
      for (final line in [...m.lines, ...m.rare]) {
        expect(line.contains('{'), isFalse, reason: '${m.id}: $line');
      }
    }
  });
}
