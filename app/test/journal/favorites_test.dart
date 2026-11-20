import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log_io.dart';
import 'package:chgk_trainer/journal/favorites.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:chgk_trainer/model/question.dart';

const question = Question(
    id: 'si-test',
    corpus: Corpus.gq,
    question: 'Полный вопрос',
    answer: 'Ответ',
    comment: 'Пояснение',
    acceptance: 'Вариант',
    sources: ['https://example.test/source'],
    author: 'Автор',
    handout: 'picture.jpg',
    handoutText: 'Первая строка\nВторая строка');
FavoriteEvent saved({bool value = true}) =>
    FavoriteEvent.at(DateTime(2026, 11, 19),
        questionId: question.id,
        saved: value,
        snapshot: value ? question.toJson() : null,
        origin: 'Своя игра',
        explanation: 'Дополнительный разбор');

void main() {
  test(
      'snapshot persists without corpus; duplicate, remove, resave and broken tail',
      () async {
    final dir = await Directory.systemTemp.createTemp('favorites-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/journal.jsonl');
    await FileEventLog(file).append(saved());
    await FileEventLog(file).append(saved());
    final reopened = FileEventLog(file);
    var read = await reopened.readAll();
    var favorites = favoriteQuestions(read.events);
    expect(favorites.length, 1);
    expect(favorites.single.question.toJson(), question.toJson());
    expect(favorites.single.explanation, 'Дополнительный разбор');
    expect(answeredCount(read.events), 0);
    expect(takenRate(read.events), isNull);
    await reopened.append(saved(value: false));
    expect(favoriteQuestions((await FileEventLog(file).readAll()).events),
        isEmpty);
    await file.writeAsString('{"v":1,"type":"favorite"', mode: FileMode.append);
    await FileEventLog(file).append(saved());
    read = await FileEventLog(file).readAll();
    expect(read.skippedLines, 1);
    expect(
        favoriteQuestions(read.events).single.question.answer, question.answer);
  });

  test('malformed additions cannot masquerade as removals', () {
    final good = saved().toJson();
    expect(JournalEvent.fromJson(jsonDecode(jsonEncode(good)))!.toJson(), good);
    expect(JournalEvent.fromJson({...good, 'saved': null}), isNull);
    expect(JournalEvent.fromJson({...good, 'snapshot': null}), isNull);
    expect(
        JournalEvent.fromJson({
          ...good,
          'snapshot': {...question.toJson(), 'id': 'other'}
        }),
        isNull);
    expect(JournalEvent.fromJson(saved(value: false).toJson()),
        isA<FavoriteEvent>());
  });
}
