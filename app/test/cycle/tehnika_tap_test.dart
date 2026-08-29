import 'package:chgk_trainer/cycle/tehnika_tap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('хеш устойчив между запусками', () {
    // Ради этого и взята fnv1a: `String.hashCode` в Dart стабильности
    // между запусками не гарантирует, и отбор «поехал бы» после перезапуска.
    expect(fnv1a('gq-107995'), fnv1a('gq-107995'));
    expect(fnv1a('gq-1'), isNot(fnv1a('gq-2')));
  });

  test('эталонный вопрос получает тап всегда', () {
    // Эталонных 91 на 8866 — без гарантии вердикт не показался бы ни разу.
    for (final id in ['gq-107995', 'gq-223916', 'gq-183047', 'gq-219834']) {
      expect(shouldAskTehnika(id, inStandard: true), isTrue, reason: id);
    }
  });

  test('на остальных тап примерно на каждом третьем', () {
    final ids = List.generate(3000, (i) => 'gq-$i');
    final asked =
        ids.where((id) => shouldAskTehnika(id, inStandard: false)).length;
    expect(asked, greaterThan(800));
    expect(asked, lessThan(1200));
  });

  test('тап на неэталонных вопросах бывает — иначе сам тап выдавал бы ответ',
      () {
    // Если бы тап показывался только на эталонных, «да» было бы всегда верным
    // и угадывать снова стало бы нечего.
    final ids = List.generate(50, (i) => 'gq-$i');
    expect(ids.any((id) => shouldAskTehnika(id, inStandard: false)), isTrue);
    expect(ids.any((id) => !shouldAskTehnika(id, inStandard: false)), isTrue);
  });

  test('решение не зависит от порядка вызовов', () {
    final first = shouldAskTehnika('gq-42', inStandard: false);
    for (var i = 0; i < 5; i++) {
      expect(shouldAskTehnika('gq-42', inStandard: false), first);
    }
  });
}
