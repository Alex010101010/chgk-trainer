import 'dart:convert';
import 'dart:io';

import 'event.dart';
import 'event_log.dart';

/// Append-only журнал в JSONL-файле.
///
/// Путь инжектируется — это seam, который делает журнал тестируемым без
/// устройства и без плагинов.
class FileEventLog implements EventLog {
  final File file;

  /// Очередь записи. Два неотожданных `append` подряд в одном изоляте — это
  /// два конкурирующих дописывания в конец файла и шанс получить перемешанные
  /// куски двух строк.
  Future<void> _tail = Future.value();

  bool _tailRepaired = false;

  FileEventLog(this.file);

  @override
  Future<void> append(JournalEvent e) {
    final next = _tail.then((_) => _appendRaw(e));
    // Ошибка одной записи не должна отравлять очередь следующим; вызывающему
    // она при этом возвращается — глотать её здесь нельзя.
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _appendRaw(JournalEvent e) async {
    var prefix = '';
    if (!_tailRepaired) {
      _tailRepaired = true;
      await file.parent.create(recursive: true);
      prefix = await _brokenTailPrefix();
    }
    await file.writeAsString('$prefix${e.toJsonLine()}\n',
        mode: FileMode.append, flush: true);
  }

  /// Краш посреди записи оставляет файл без завершающего перевода строки.
  /// Если не дописать его, следующее событие приклеится к обрывку и битой
  /// станет не одна строка, а две — то есть потеряется и валидное новое.
  Future<String> _brokenTailPrefix() async {
    if (!await file.exists()) return '';
    final length = await file.length();
    if (length == 0) return '';
    final handle = await file.open();
    try {
      await handle.setPosition(length - 1);
      final last = await handle.read(1);
      return (last.isNotEmpty && last[0] == 0x0A) ? '' : '\n';
    } finally {
      await handle.close();
    }
  }

  @override
  Future<JournalRead> readAll() async {
    final String content;
    try {
      content = await file.readAsString();
    } on PathNotFoundException {
      // Первый запуск — это пустой журнал, а не ошибка. Глотать так можно
      // ТОЛЬКО отсутствие файла: нет прав, каталог вместо файла и прочее
      // летит наружу, иначе сбой неотличим от «игрок ещё не играл».
      return JournalRead.empty;
    }

    final events = <JournalEvent>[];
    var skipped = 0;
    for (final line in const LineSplitter().convert(content)) {
      if (line.trim().isEmpty) continue;
      JournalEvent? event;
      try {
        event = JournalEvent.fromJson(jsonDecode(line));
      } on FormatException {
        event = null;
      }
      if (event == null) {
        skipped++;
      } else {
        events.add(event);
      }
    }
    return JournalRead(events, skipped);
  }
}
