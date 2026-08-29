import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/data/tehnika_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Этот тест — гард против забытой генерации ассета: без
  // `python3 scripts/build_app_assets.py` он падает ещё до запуска, на
  // «No file or variants found for asset».
  // Обычный `test`, а не `testWidgets`: последний крутит фейковые часы, а
  // `compute` уходит в настоящий изолят — его Future в фейковом времени
  // не завершается никогда, и тест висит до таймаута вместо падения.
  test('настоящий ассет грузится через rootBundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final sw = Stopwatch()..start();
    final questions = await AssetQuestionRepository().loadAll();
    // Замер под критерий T2b: больше секунды — заводим шарды отдельной задачей.
    // ignore: avoid_print
    print('loadAll(): ${sw.elapsedMilliseconds} мс на ${questions.length} вопросов');
    expect(questions.length, greaterThan(8000));
    expect(questions.every((q) => q.acceptVariants.isNotEmpty), isTrue);
    expect(questions.map((q) => q.id).toSet().length, questions.length);
  });

  // Гард против незаявленного ассета приёмов: `tehniki.json` коммитится, но
  // если он выпадет из `pubspec.yaml`, приложение узнает об этом только на
  // телефоне, при входе в режим.
  test('ассет приёмов грузится и связан с корпусом', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tehniki = await AssetTehnikaRepository().loadAll();
    expect(tehniki, isNotEmpty);

    final byId = {
      for (final q in await AssetQuestionRepository().loadAll()) q.id: q
    };
    for (final t in tehniki) {
      expect(t.explain, isNotEmpty, reason: t.id);
      expect(t.examples, isNotEmpty, reason: t.id);
      for (final e in t.examples) {
        final q = byId[e.questionId];
        expect(q, isNotNull, reason: '${t.id}: ${e.questionId}');
        expect(q!.tehniki, contains(t.id), reason: e.questionId);
      }
      // Эталон должен быть достаточно велик, чтобы приём реально попадался.
      expect(byId.values.where((q) => q.tehniki.contains(t.id)).length,
          greaterThanOrEqualTo(30),
          reason: t.id);
    }
  });

  test('второй loadAll не перечитывает ассет', () async {
    // Замер на телефоне: 871 мс при первом открытии и 890 при повторном —
    // кеш есть, но был бесполезен, потому что репозиторий пересоздавался.
    TestWidgetsFlutterBinding.ensureInitialized();
    final repo = AssetQuestionRepository();
    final first = await repo.loadAll();
    final sw = Stopwatch()..start();
    final second = await repo.loadAll();
    sw.stop();
    expect(identical(first, second), isTrue);
    expect(sw.elapsedMilliseconds, lessThan(50));
  });

  test('обрезанный ассет — исключение, а не короткий список', () {
    expect(
      () => parseQuestionAsset(
          '{"v":1,"count":9000,"questions":[{"id":"gq-1","corpus":"gq","question":"q","answer":"a","acceptVariants":["a"]}]}'),
      throwsA(isA<QuestionAssetException>()),
    );
  });

  test('пустой ассет — исключение, а не «вопросы кончились»', () {
    expect(
      () => parseQuestionAsset('{"v":1,"count":0,"questions":[]}'),
      throwsA(isA<QuestionAssetException>()),
    );
  });

  test('мусор вместо ассета — исключение с инструкцией', () {
    expect(
      () => parseQuestionAsset('не json'),
      throwsA(isA<QuestionAssetException>().having(
          (e) => e.message, 'message', contains('build_app_assets.py'))),
    );
    expect(() => parseQuestionAsset('[]'), throwsA(isA<QuestionAssetException>()));
  });
}
