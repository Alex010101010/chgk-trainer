import 'dart:io';

import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/event_log_io.dart';
import 'package:flutter_test/flutter_test.dart';

SessionStartEvent _event(int ts) =>
    SessionStartEvent(ts: ts, day: '2026-08-29');

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('journal_test');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  File journalFile() => File('${dir.path}/journal.jsonl');

  test('память: порядок событий сохраняется', () async {
    final log = MemoryEventLog();
    await log.append(_event(1));
    await log.append(_event(2));
    final read = await log.readAll();
    expect(read.events.map((e) => e.ts), [1, 2]);
    expect(read.skippedLines, 0);
  });

  test('записанное переживает «перезапуск» — новый экземпляр видит журнал',
      () async {
    final file = journalFile();
    final first = FileEventLog(file);
    await first.append(_event(1));
    await first.append(_event(2));
    await first.append(_event(3));

    final second = FileEventLog(file);
    final read = await second.readAll();
    expect(read.events.map((e) => e.ts), [1, 2, 3]);
    expect(read.skippedLines, 0);
  });

  test('битая строка посреди файла пропускается и считается', () async {
    final file = journalFile();
    await file.writeAsString(
      '${_event(1).toJsonLine()}\nне json совсем\n${_event(3).toJsonLine()}\n',
    );
    final read = await FileEventLog(file).readAll();
    expect(read.events.map((e) => e.ts), [1, 3]);
    expect(read.skippedLines, 1);
  });

  test('оборванный хвост не утаскивает следующее событие', () async {
    final file = journalFile();
    // Краш посреди записи: файл кончается без перевода строки.
    await file.writeAsString('${_event(1).toJsonLine()}\n{"v":1,"type":"ses');

    final log = FileEventLog(file);
    await log.append(_event(2));

    final read = await log.readAll();
    expect(read.events.map((e) => e.ts), [1, 2],
        reason: 'новое событие должно читаться целым');
    expect(read.skippedLines, 1, reason: 'потеряться должен только обрывок');
  });

  test('несуществующий файл — пустой журнал, а не исключение', () async {
    final read = await FileEventLog(File('${dir.path}/нет/такого.jsonl')).readAll();
    expect(read.events, isEmpty);
    expect(read.skippedLines, 0);
  });

  test('ошибка чтения, кроме отсутствия файла, летит наружу', () async {
    // Каталог вместо файла: это сбой, и он не имеет права выглядеть
    // как «игрок ещё не играл».
    final asDirectory = Directory('${dir.path}/journal.jsonl');
    await asDirectory.create(recursive: true);
    expect(FileEventLog(journalFile()).readAll(),
        throwsA(isA<FileSystemException>()));
  });

  test('параллельные append не перемешиваются', () async {
    final file = journalFile();
    final log = FileEventLog(file);
    await Future.wait([for (var i = 1; i <= 20; i++) log.append(_event(i))]);

    final read = await FileEventLog(file).readAll();
    expect(read.events.length, 20);
    expect(read.skippedLines, 0);
    expect(read.events.map((e) => e.ts).toSet(),
        {for (var i = 1; i <= 20; i++) i});
  });

  test('каталог под журнал создаётся сам', () async {
    final file = File('${dir.path}/глубже/ещё/journal.jsonl');
    await FileEventLog(file).append(_event(1));
    expect(file.existsSync(), isTrue);
  });
}
