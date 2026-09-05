import 'dart:convert';

/// Версия схемы журнала. Событие с версией больше известной читатель пропускает
/// и считает в `JournalRead.skippedLines` — не роняя чтение остальных.
const int kSchemaVersion = 1;

enum Corpus { gq, bingo }

enum GameMode { classic, bingo, tehnika, daily, facts }

enum Verdict { taken, almost, missed }

/// Диагностика-роутер: что помешало взять вопрос.
enum MissReason { fact, link, tehnika, time }

/// Маркер «ни к одной клетке» в [AnswerEvent.themeGuess].
/// `null` там означает «клетку не спрашивали» — это разные состояния.
const String kThemeGuessNone = '';

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Локальная дата в момент записи. Пишется полем, а не выводится из [ts]:
/// после смены таймзоны восстановить её будет неоткуда, а на ней держатся
/// streak (T9) и «одна попытка в сутки» (T12).
String localDay(DateTime now) {
  final d = now.toLocal();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

sealed class JournalEvent {
  /// epoch millis UTC.
  final int ts;

  /// YYYY-MM-DD локальной даты в момент записи.
  final String day;

  const JournalEvent({required this.ts, required this.day});

  String get type;

  Map<String, dynamic> toJson() => {
        'v': kSchemaVersion,
        'type': type,
        'ts': ts,
        'day': day,
        ...body(),
      };

  Map<String, dynamic> body();

  String toJsonLine() => jsonEncode(toJson());

  /// Возвращает `null` на любом непонятном входе — незнакомый тип, будущая
  /// версия схемы, битые поля. Решение «что делать с непонятным» принимает
  /// читатель журнала, а не парсер.
  static JournalEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final v = j['v'];
    if (v is! int || v > kSchemaVersion) return null;
    final ts = j['ts'];
    final day = j['day'];
    if (ts is! int || day is! String) return null;
    switch (j['type']) {
      case 'answer':
        return AnswerEvent._fromJson(j, ts, day);
      case 'note':
        return NoteEvent._fromJson(j, ts, day);
      case 'bingoGrid':
        return BingoGridEvent._fromJson(j, ts, day);
      case 'sessionStart':
        return SessionStartEvent(ts: ts, day: day);
      default:
        return null;
    }
  }
}

class AnswerEvent extends JournalEvent {
  final String questionId;
  final Corpus corpus;
  final GameMode mode;
  final Verdict verdict;

  /// Сколько секунд минуты израсходовано до «готов»/истечения, 0..60.
  final int secondsUsed;

  /// Длина окна записи, действовавшая на этом событии. T2a объявляет её
  /// настраиваемой — без неё доля `reason: time` до и после подкрутки
  /// становится несопоставимой, и границу восстановить будет неоткуда.
  final int answerWindowSec;

  /// Текст версии. Пустая строка — валидное значение, а не ошибка.
  final String userAnswer;

  final MissReason? reason;
  final bool hintUsed;

  /// epoch millis старта раунда, строкой. `null` вне раунда.
  final String? roundId;

  /// Настоящее клише. У gq-корпуса всегда `null`.
  final String? theme;

  /// `null` — клетку не спрашивали; [kThemeGuessNone] — «ни к одной».
  final String? themeGuess;

  final bool? tehnikaGuess;
  final List<String> tags;

  const AnswerEvent({
    required super.ts,
    required super.day,
    required this.questionId,
    required this.corpus,
    required this.mode,
    required this.verdict,
    required this.secondsUsed,
    this.answerWindowSec = 10,
    this.userAnswer = '',
    this.reason,
    this.hintUsed = false,
    this.roundId,
    this.theme,
    this.themeGuess,
    this.tehnikaGuess,
    this.tags = const [],
  });

  @override
  String get type => 'answer';

  @override
  Map<String, dynamic> body() => {
        'questionId': questionId,
        'corpus': corpus.name,
        'mode': mode.name,
        'verdict': verdict.name,
        'secondsUsed': secondsUsed,
        'answerWindowSec': answerWindowSec,
        'userAnswer': userAnswer,
        'reason': reason?.name,
        'hintUsed': hintUsed,
        'roundId': roundId,
        'theme': theme,
        'themeGuess': themeGuess,
        'tehnikaGuess': tehnikaGuess,
        'tags': tags,
      };

  static AnswerEvent? _fromJson(Map<String, dynamic> j, int ts, String day) {
    final questionId = j['questionId'];
    final corpus = _enumByName(Corpus.values, j['corpus']);
    final mode = _enumByName(GameMode.values, j['mode']);
    final verdict = _enumByName(Verdict.values, j['verdict']);
    final secondsUsed = j['secondsUsed'];
    if (questionId is! String ||
        corpus == null ||
        mode == null ||
        verdict == null ||
        secondsUsed is! int) {
      return null;
    }
    final tags = j['tags'];
    return AnswerEvent(
      ts: ts,
      day: day,
      questionId: questionId,
      corpus: corpus,
      mode: mode,
      verdict: verdict,
      secondsUsed: secondsUsed,
      answerWindowSec: j['answerWindowSec'] is int ? j['answerWindowSec'] as int : 10,
      userAnswer: j['userAnswer'] is String ? j['userAnswer'] as String : '',
      reason: _enumByName(MissReason.values, j['reason']),
      hintUsed: j['hintUsed'] == true,
      roundId: j['roundId'] is String ? j['roundId'] as String : null,
      theme: j['theme'] is String ? j['theme'] as String : null,
      themeGuess: j['themeGuess'] is String ? j['themeGuess'] as String : null,
      tehnikaGuess: j['tehnikaGuess'] is bool ? j['tehnikaGuess'] as bool : null,
      tags: tags is List ? tags.whereType<String>().toList() : const [],
    );
  }
}

/// Своя заметка на клише (T14). Пишется уже после того, как событие ответа
/// легло в append-only журнал, — ради этого случая у событий и есть `type`.
class NoteEvent extends JournalEvent {
  final String theme;
  final String text;
  final String? questionId;

  const NoteEvent({
    required super.ts,
    required super.day,
    required this.theme,
    required this.text,
    this.questionId,
  });

  @override
  String get type => 'note';

  @override
  Map<String, dynamic> body() => {
        'theme': theme,
        'text': text,
        'questionId': questionId,
      };

  static NoteEvent? _fromJson(Map<String, dynamic> j, int ts, String day) {
    final theme = j['theme'];
    final text = j['text'];
    if (theme is! String || text is! String) return null;
    return NoteEvent(
      ts: ts,
      day: day,
      theme: theme,
      text: text,
      questionId: j['questionId'] is String ? j['questionId'] as String : null,
    );
  }
}

/// Состав сетки «Бинго» (T3) — девять тем в порядке клеток.
///
/// Единственное, что нельзя вывести свёрткой: выбор тем случайный, и после
/// перезапуска приложение собрало бы другую сетку, потеряв прогресс игрока.
/// Закрашенность клеток при этом по-прежнему считается по ответам, отдельного
/// хранилища прогресса не появляется.
class BingoGridEvent extends JournalEvent {
  final List<String> themes;

  const BingoGridEvent({
    required super.ts,
    required super.day,
    required this.themes,
  });

  factory BingoGridEvent.at(DateTime now, List<String> themes) => BingoGridEvent(
        ts: now.toUtc().millisecondsSinceEpoch,
        day: localDay(now),
        themes: themes,
      );

  @override
  String get type => 'bingoGrid';

  @override
  Map<String, dynamic> body() => {'themes': themes};

  static BingoGridEvent? _fromJson(Map<String, dynamic> j, int ts, String day) {
    final themes = j['themes'];
    if (themes is! List) return null;
    final list = themes.whereType<String>().toList();
    // Сетка без тем — не сетка: пустой список означал бы, что клетки не к чему
    // привязать, а режим молча показал бы девять пустых квадратов.
    if (list.isEmpty) return null;
    return BingoGridEvent(ts: ts, day: day, themes: list);
  }
}

/// Холодный старт приложения. Streak в T9 считается по «дням, когда заходил»,
/// а не «отвечал», — без этого события день без ответа не виден вовсе.
class SessionStartEvent extends JournalEvent {
  const SessionStartEvent({required super.ts, required super.day});

  factory SessionStartEvent.at(DateTime now) => SessionStartEvent(
        ts: now.toUtc().millisecondsSinceEpoch,
        day: localDay(now),
      );

  @override
  String get type => 'sessionStart';

  @override
  Map<String, dynamic> body() => const {};
}
