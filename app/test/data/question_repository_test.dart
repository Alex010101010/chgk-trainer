import 'package:chgk_trainer/data/question_repository.dart';
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
