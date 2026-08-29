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

/// Клише, которые игрок хоть раз узнал верно. Насколько «надёжно» —
/// определяет T3 при сборке сетки, здесь только сырой факт узнавания.
Set<String> recognizedThemes(List<JournalEvent> events) {
  final themes = <String>{};
  for (final e in events) {
    if (e is AnswerEvent &&
        e.theme != null &&
        e.themeGuess != null &&
        e.themeGuess == e.theme) {
      themes.add(e.theme!);
    }
  }
  return themes;
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
