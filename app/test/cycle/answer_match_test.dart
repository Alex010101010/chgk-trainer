import 'package:chgk_trainer/cycle/answer_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeAnswer', () {
    test('снимает регистр, пунктуацию, кавычки и ё', () {
      expect(normalizeAnswer('«Ёжик».'), 'ежик');
      expect(normalizeAnswer('  два   слова  '), 'два слова');
    });
  });

  group('matchAnswer', () {
    test('пустой ответ не матчится ни с чем и никогда', () {
      // Красный→зелёный: на наивной реализации `''.contains(v)` даёт almost
      // на каждом вопросе, и пустая версия молча становится «почти».
      expect(matchAnswer('', ['уорхол']), MatchHint.none);
      expect(matchAnswer('   ', ['уорхол']), MatchHint.none);
      expect(matchAnswer('...', ['уорхол']), MatchHint.none);
    });

    test('точный матч после нормализации', () {
      expect(matchAnswer('Уорхол.', ['уорхол']), MatchHint.taken);
    });

    test('опечатка в пределах порога', () {
      expect(matchAnswer('Уорхал', ['уорхол']), MatchHint.taken);
    });

    test('вхождение даёт не none', () {
      expect(matchAnswer('гамма', ['гамма (музыка)']), isNot(MatchHint.none));
      expect(matchAnswer('гамма (музыка)', ['гамма']), isNot(MatchHint.none));
    });

    test('короткий ответ не проходит по вхождению', () {
      expect(matchAnswer('а', ['гамма']), MatchHint.none);
    });

    test('точный матч ищется по всем вариантам раньше вхождения', () {
      // Порядок вариантов не должен решать: «блины» есть в списке точным.
      expect(matchAnswer('блины', ['масленичные блины', 'блины']),
          MatchHint.taken);
    });

    test('несвязанный ответ — none', () {
      expect(matchAnswer('Магритт', ['уорхол']), MatchHint.none);
    });
  });
}
