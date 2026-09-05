import 'event.dart';

/// Правило возврата проваленного вопроса. Числа подбираются на практике —
/// важно, что они заданы в одном месте, а не размазаны по режимам.
class ReturnRule {
  static const int missedDays = 2;

  /// «Почти» и «взял с подсказкой» — одна корзина: вопрос не освоен.
  static const int almostDays = 7;

  /// Повторный промах того же вопроса возвращает его быстрее, а не медленнее.
  static const int repeatedMissedDays = 1;

  const ReturnRule._();
}

/// Вопросы, которым пора вернуться. `taken` без подсказки не возвращается вовсе.
///
/// Граница включительная: вопрос, у которого срок наступил ровно сейчас,
/// считается подошедшим.
List<String> dueQuestions(List<JournalEvent> events, DateTime now) {
  final byQuestion = <String, List<AnswerEvent>>{};
  for (final e in events) {
    if (e is AnswerEvent) {
      byQuestion.putIfAbsent(e.questionId, () => <AnswerEvent>[]).add(e);
    }
  }

  final nowUtc = now.toUtc();
  final due = <String>[];
  byQuestion.forEach((questionId, answers) {
    answers.sort((a, b) => a.ts.compareTo(b.ts));
    final last = answers.last;
    final previous = answers.length > 1 ? answers[answers.length - 2] : null;

    final int? days;
    if (last.verdict == Verdict.missed) {
      days = previous?.verdict == Verdict.missed
          ? ReturnRule.repeatedMissedDays
          : ReturnRule.missedDays;
    } else if (last.verdict == Verdict.almost || last.hintUsed) {
      days = ReturnRule.almostDays;
    } else {
      days = null;
    }
    if (days == null) return;

    final dueAt = DateTime.fromMillisecondsSinceEpoch(last.ts, isUtc: true)
        .add(Duration(days: days));
    if (!nowUtc.isBefore(dueAt)) due.add(questionId);
  });
  return due;
}

/// Дни подряд, когда игрок заходил. Считается по любому событию — заход без
/// ответа тоже заход, ради этого и пишется `sessionStart`.
///
/// Стрик, оборвавшийся вчера, ещё жив: иначе он показывал бы ноль каждое утро
/// до первой игры.
int currentStreak(List<JournalEvent> events, DateTime now) {
  final days = events.map((e) => e.day).toSet();
  if (days.isEmpty) return 0;

  final today = localDay(now);
  var cursor = DateTime.parse(today);
  if (!days.contains(today)) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!days.contains(localDay(cursor))) return 0;
  }

  var streak = 0;
  while (days.contains(localDay(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Доля «взял» на последних [window] ответах. `null`, если ответов ещё нет.
double? takenRate(List<JournalEvent> events, {int window = 50}) {
  final answers = events.whereType<AnswerEvent>().toList()
    ..sort((a, b) => a.ts.compareTo(b.ts));
  if (answers.isEmpty) return null;
  final slice = answers.length > window
      ? answers.sublist(answers.length - window)
      : answers;
  final taken = slice.where((a) => a.verdict == Verdict.taken).length;
  return taken / slice.length;
}

/// Клише, которые игрок узнаёт. Освоенной считается тема, где **последнее**
/// суждение оказалось верным (T3).
///
/// Порог «два верных подряд» отвергнут: у 42 тем корпуса меньше трёх вопросов,
/// и они не смогли бы стать освоенными в принципе. По последнему суждению
/// забытое клише само выпадает из освоенных после первого же промаха.
Set<String> masteredThemes(List<JournalEvent> events) {
  final last = <String, AnswerEvent>{};
  for (final e in events) {
    // Суждение — только там, где клетку спрашивали и настоящее клише известно.
    // У gq `theme` пуст: тап по клетке на отвлекающем вопросе — предложение
    // разметки для T14, а не узнавание.
    if (e is! AnswerEvent || e.theme == null || e.themeGuess == null) continue;
    final prev = last[e.theme!];
    if (prev == null || e.ts >= prev.ts) last[e.theme!] = e;
  }
  return {
    for (final e in last.values)
      if (e.themeGuess == e.theme) e.theme!,
  };
}

/// Клише, которые игроку уже попадались: по теме сыгран хотя бы один вопрос,
/// независимо от того, узнал он её или нет (T14, справочник).
///
/// Считается по настоящей теме вопроса, а не по догадке: «встречалось» — это
/// про то, что показали, а не про то, что ответили.
Set<String> encounteredThemes(List<JournalEvent> events) => {
      for (final e in events)
        if (e is AnswerEvent && e.theme != null) e.theme!,
    };

/// Своя заметка на клише — по последней записи (T14). Журнал append-only,
/// поэтому правка заметки это новая запись, а пустой текст — снятая заметка:
/// такие темы из свёртки выпадают, и «стереть» работает без удаления строк.
Map<String, String> themeNotes(List<JournalEvent> events) {
  final last = <String, NoteEvent>{};
  for (final e in events) {
    if (e is! NoteEvent) continue;
    final prev = last[e.theme];
    if (prev == null || e.ts >= prev.ts) last[e.theme] = e;
  }
  return {
    for (final e in last.values)
      if (e.text.trim().isNotEmpty) e.theme: e.text.trim(),
  };
}

/// Состав текущей сетки — темы последнего [BingoGridEvent]. `null`, если
/// сетку ещё ни разу не собирали.
List<String>? currentGrid(List<JournalEvent> events) {
  BingoGridEvent? last;
  for (final e in events) {
    if (e is BingoGridEvent && (last == null || e.ts >= last.ts)) last = e;
  }
  return last?.themes;
}

enum BingoCell { empty, filled, golden }

/// Состояние клеток текущей сетки, в порядке тем. Пустой список — сетки нет.
///
/// Считается только по ответам **после** старта сетки: узнавание из прошлой
/// кампании не закрашивает клетку в новой, иначе сетка открывалась бы уже
/// наполовину закрытой.
List<BingoCell> gridCells(List<JournalEvent> events) {
  BingoGridEvent? grid;
  for (final e in events) {
    if (e is BingoGridEvent && (grid == null || e.ts >= grid.ts)) grid = e;
  }
  if (grid == null) return const [];

  final cells = {for (final t in grid.themes) t: BingoCell.empty};
  for (final e in events) {
    if (e is! AnswerEvent || e.ts < grid.ts) continue;
    if (e.theme == null || e.themeGuess != e.theme) continue;
    if (!cells.containsKey(e.theme)) continue;
    // Золото — узнал клише И взял сам вопрос. Однажды полученное не сгорает:
    // повторный промах по той же клетке не отбирает уже закрытое.
    if (e.verdict == Verdict.taken) {
      cells[e.theme!] = BingoCell.golden;
    } else if (cells[e.theme] == BingoCell.empty) {
      cells[e.theme!] = BingoCell.filled;
    }
  }
  return [for (final t in grid.themes) cells[t]!];
}

/// Линии сетки 3×3: три ряда, три столбца, две диагонали.
const List<List<int>> kBingoLines = [
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [0, 3, 6],
  [1, 4, 7],
  [2, 5, 8],
  [0, 4, 8],
  [2, 4, 6],
];

/// Есть ли три в ряд. Золото — флекс, не гейт: линия считается по закрашенным
/// любого цвета.
bool hasLine(List<BingoCell> cells) {
  if (cells.length < 9) return false;
  return kBingoLines.any(
      (line) => line.every((i) => cells[i] != BingoCell.empty));
}

/// Номер недели стажа, с нуля. Считается по собственному журналу, а не по
/// календарю: сервер не нужен, `day` уже локальная дата, и первый запуск
/// в четверг не даёт огрызок в четыре дня вместо первого урока.
///
/// Граница включительная снизу: день 6 — ещё неделя 0, день 7 — уже неделя 1.
int weekIndex(List<JournalEvent> events, DateTime now) {
  final start = _firstDay(events);
  if (start == null) return 0;
  return _weekOf(start, localDay(now));
}

/// Был ли на этой неделе стажа хоть один ответ. По нему решается, показывать
/// ли карточку урока при входе в режим.
bool answeredThisWeek(List<JournalEvent> events, DateTime now) {
  final start = _firstDay(events);
  if (start == null) return false;
  final week = _weekOf(start, localDay(now));
  return events
      .whereType<AnswerEvent>()
      .any((e) => _weekOf(start, e.day) == week);
}

String? _firstDay(List<JournalEvent> events) => events.isEmpty
    ? null
    : events.map((e) => e.day).reduce((a, b) => a.compareTo(b) <= 0 ? a : b);

int _weekOf(String startDay, String day) {
  final days = DateTime.parse(day).difference(DateTime.parse(startDay)).inDays;
  return days <= 0 ? 0 : days ~/ 7;
}
