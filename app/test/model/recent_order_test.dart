import 'dart:math';
import 'package:chgk_trainer/model/recent_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('горизонт движется по дню первого отыгрыша', () {
    final now = DateTime(2026, 11, 14);
    expect(withinTenYears('2016-11-14', now), isTrue);
    expect(withinTenYears('2016-11-13', now), isFalse);
    expect(withinTenYears('2026-11-15', now), isFalse);
    expect(withinTenYears('2001-01-01', now), isFalse);
  });
  test('новые чаще, старые не пропадают и выбор без повторов', () {
    final now = DateTime(2026, 11, 14);
    final dates = ['2026-11-14', '2017-11-14'];
    var recent = 0;
    final random = Random(34);
    for (var i = 0; i < 1000; i++) {
      final ranked = preferRecent(dates, (s) => s, now, random);
      expect(ranked.toSet(), dates.toSet());
      if (ranked.first == dates.first) recent++;
    }
    expect(recent, greaterThan(800));
    expect(recent, lessThan(990));
  });
}
