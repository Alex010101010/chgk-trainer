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
    // Промах в проверке недели (T4b) — неверно названный приём, а не
    // невзятый вопрос: возвращать его нечем и незачем.
    if (e is AnswerEvent && e.mode != GameMode.tehnika) {
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
  // Проверка недели (T4b) вопрос не берёт — её вердикт про узнавание приёма.
  final answers = events
      .whereType<AnswerEvent>()
      .where((a) => a.mode != GameMode.tehnika)
      .toList()
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

/// Нормализованный вид названия клише — для сверки, не для показа.
///
/// «ковентри», «Ковентри» и «Ковентри » для игрока одно и то же, а для
/// `Set<String>` это три разные строки: без нормализации дубль корпусной темы
/// заводится первым же вводом мимо всех проверок. Хранится при этом то, что
/// игрок написал, — приводится только ключ сравнения.
String normalizeTheme(String theme) => theme
    .trim()
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Свои реалии (T24) — клише, которых в корпусе нет: заметка на теме, которую
/// приложение не показывало и показать не может.
///
/// Отдельного хранилища у своей реалии нет, она живёт заметкой — поэтому
/// стёртая заметка снимает и саму реалию. Тема, приехавшая в корпус следующим
/// импортом, перестаёт быть своей и склеивается с корпусной вместе с заметкой.
Map<String, String> customThemes(
  Map<String, String> notes,
  Iterable<String> corpusThemes,
) {
  final known = {for (final t in corpusThemes) normalizeTheme(t)};
  return {
    for (final e in notes.entries)
      if (!known.contains(normalizeTheme(e.key))) e.key: e.value,
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
  // Проверка недели (T4b) урок не заменяет: сыгранная первой, она спрятала
  // бы карточку нового приёма до «Классики».
  return events
      .whereType<AnswerEvent>()
      .where((e) => e.mode != GameMode.tehnika)
      .any((e) => _weekOf(start, e.day) == week);
}

/// Сколько дней до следующей недели стажа, 1..7. На пустом журнале — 7:
/// первая неделя ещё не началась.
int daysToNextWeek(List<JournalEvent> events, DateTime now) {
  final start = _firstDay(events);
  if (start == null) return 7;
  final days = DateTime.parse(localDay(now)).difference(DateTime.parse(start)).inDays;
  return 7 - (days < 0 ? 0 : days % 7);
}

/// Вопросов в проверке недели (T4b).
const int kCheckSize = 5;

/// Ответы проверки недели на текущей неделе стажа. Проверка сыграна, когда их
/// набралось [kCheckSize]: вышел на середине — остаток доигрывается, а не
/// сгорает до следующей недели.
List<AnswerEvent> tehnikaCheckAnswers(List<JournalEvent> events, DateTime now) {
  final start = _firstDay(events);
  if (start == null) return const [];
  final week = _weekOf(start, localDay(now));
  return events
      .whereType<AnswerEvent>()
      .where((e) => e.mode == GameMode.tehnika && _weekOf(start, e.day) == week)
      .toList();
}

String? _firstDay(List<JournalEvent> events) => events.isEmpty
    ? null
    : events.map((e) => e.day).reduce((a, b) => a.compareTo(b) <= 0 ? a : b);

int _weekOf(String startDay, String day) {
  final days = DateTime.parse(day).difference(DateTime.parse(startDay)).inDays;
  return days <= 0 ? 0 : days ~/ 7;
}

/// Итоги «Вопроса дня» (T12) по дням: `день → вердикт`. Попытка одна, поэтому
/// берётся первый ответ дня — второго быть не должно, но если журнал его
/// всё же содержит, переиграть день он не даёт.
Map<String, Verdict> dailyResults(List<JournalEvent> events) {
  final out = <String, Verdict>{};
  for (final e in events.whereType<AnswerEvent>()) {
    if (e.mode == GameMode.daily) out.putIfAbsent(e.day, () => e.verdict);
  }
  return out;
}

/// Дни подряд с сыгранным вопросом дня. Как и [currentStreak], серия,
/// оборвавшаяся вчера, ещё жива: утром до игры она не должна показывать ноль.
int dailyStreak(List<JournalEvent> events, DateTime now) {
  final days = dailyResults(events).keys.toSet();
  var cursor = DateTime.parse(localDay(now));
  if (!days.contains(localDay(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (days.contains(localDay(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Интервалы коробок Лейтнера (T15), в днях. Коробки нумеруются с единицы:
/// новая карточка — в первой, «знал» переносит в следующую (выше пятой
/// некуда), «не знал» — обратно в первую.
const List<int> kLeitnerDays = [1, 2, 4, 8, 16];

/// Сколько новых карточек колода выдаёт за день. На колоду, а не на всё
/// приложение: общий лимит сжигался бы на первой открытой колоде.
const int kNewFactsPerDay = 10;

/// Где карточка сейчас: коробка 1..5 и день последнего ответа.
class FactState {
  final int box;
  final String lastDay;

  const FactState(this.box, this.lastDay);

  bool get learned => box == kLeitnerDays.length;

  /// Пора ли повторить. Считается по дням, а не по часам: карточка, отвеченная
  /// вечером, подходит на следующее утро, а не через сутки. Граница
  /// включительная — срок ровно сегодня значит «пора».
  bool isDue(DateTime now) {
    final due = DateTime.parse(lastDay).add(Duration(days: kLeitnerDays[box - 1]));
    return !DateTime.parse(localDay(now)).isBefore(due);
  }
}

/// Состояние карточек, на которые уже отвечали. Карточки без ответов в свёртку
/// не попадают — они новые.
Map<String, FactState> factStates(List<JournalEvent> events) {
  final facts = events.whereType<FactEvent>().toList()
    ..sort((a, b) => a.ts.compareTo(b.ts));
  final out = <String, FactState>{};
  for (final e in facts) {
    final box = out[e.cardId]?.box ?? 1;
    out[e.cardId] = FactState(
      e.known ? (box + 1).clamp(1, kLeitnerDays.length) : 1,
      e.day,
    );
  }
  return out;
}

/// Сколько новых карточек колоды уже открыто сегодня — первый ответ на них
/// пришёлся на сегодняшний день.
int newFactsToday(List<JournalEvent> events, String deck, DateTime now) {
  final today = localDay(now);
  final firstDay = <String, String>{};
  for (final e in events.whereType<FactEvent>()) {
    if (e.deck != deck) continue;
    final prev = firstDay[e.cardId];
    if (prev == null || e.day.compareTo(prev) < 0) firstDay[e.cardId] = e.day;
  }
  return firstDay.values.where((d) => d == today).length;
}
