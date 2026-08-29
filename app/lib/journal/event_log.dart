import 'event.dart';

/// Результат чтения журнала.
///
/// [skippedLines] существует, чтобы битый журнал нельзя было принять за пустой:
/// иначе сбой чтения схлопывается в то же значение, что и «игрок ещё не играл»,
/// и весь накопленный прогресс молча показывается нулевым.
class JournalRead {
  final List<JournalEvent> events;
  final int skippedLines;

  const JournalRead(this.events, this.skippedLines);

  static const JournalRead empty = JournalRead([], 0);
}

abstract class EventLog {
  Future<void> append(JournalEvent e);

  Future<JournalRead> readAll();
}

/// Журнал в памяти: тесты и web-превью. Прогресс не переживает перезагрузку —
/// на web это осознанно, превью там демка, а не рабочее приложение.
class MemoryEventLog implements EventLog {
  final List<JournalEvent> _events = [];

  @override
  Future<void> append(JournalEvent e) async => _events.add(e);

  @override
  Future<JournalRead> readAll() async =>
      JournalRead(List.unmodifiable(_events), 0);
}
