import 'dart:async';

import 'package:flutter/foundation.dart';

import '../journal/event.dart';
import '../model/question.dart';
import '../model/tehnika.dart';
import 'answer_match.dart';

/// Длина окна записи по умолчанию. Живёт в одном месте и пробрасывается
/// параметром: экрана настроек в фазе 1 нет, но подкрутка окна не должна
/// требовать правок в нескольких файлах — ради этого длина и пишется в каждое
/// событие журнала.
const int kDefaultAnswerWindowSec = 10;

/// Минута на обсуждение — турнирная конвенция.
const int kThinkingSec = 60;

enum CyclePhase {
  reading,
  thinking,
  writing,
  bingoTap,
  reveal,
  verdict,
  reason,
  tehnika,
  done,
}

/// Всё режимо-специфичное, что цикл получает снаружи. Сам цикл о режимах
/// не знает: T3 и T4b берут тот же контроллер с другой конфигурацией.
class CycleConfig {
  final GameMode mode;

  /// Спрашивать «узнал клише? назови» — до раскрытия.
  final bool askBingoTap;

  /// Приём недели (T4a). `null` — фазу тапа не показывать. Решает режим:
  /// тап попадается не на каждом вопросе.
  final Tehnika? tehnika;

  /// Говорит ли эталон, что приём недели в этом вопросе есть. `false` значит
  /// «эталон не нашёл», а не «приёма нет»: полнота эталона низкая, и вердикт
  /// на отрицательном ответе поэтому не выносится.
  final bool tehnikaInStandard;

  final int answerWindowSec;

  /// epoch millis старта раунда, строкой. `null` вне раунда.
  final String? roundId;

  const CycleConfig({
    required this.mode,
    this.askBingoTap = false,
    this.tehnika,
    this.tehnikaInStandard = false,
    this.answerWindowSec = kDefaultAnswerWindowSec,
    this.roundId,
  });
}

class CycleController extends ChangeNotifier {
  final Question question;
  final CycleConfig config;

  /// Часы инжектируются — это seam для тестов таймера, без него ни один такой
  /// тест не пишется.
  final DateTime Function() now;

  CycleController({
    required this.question,
    required this.config,
    DateTime Function()? now,
    Duration tick = const Duration(milliseconds: 200),
  })  : now = now ?? DateTime.now,
        _tick = tick;

  final Duration _tick;
  Timer? _timer;

  CyclePhase _phase = CyclePhase.reading;
  CyclePhase get phase => _phase;

  DateTime? _thinkingStartedAt;
  DateTime? _writingStartedAt;
  int? _committedSecondsUsed;

  String _userAnswer = '';
  String get userAnswer => _userAnswer;

  Verdict? _verdict;
  Verdict? get verdict => _verdict;

  MissReason? _reason;
  MissReason? get reason => _reason;

  String? _themeGuess;
  String? get themeGuess => _themeGuess;

  bool? _tehnikaGuess;
  bool? get tehnikaGuess => _tehnikaGuess;

  /// Предзаполнение самооценки. Считается один раз при раскрытии.
  MatchHint _hint = MatchHint.none;
  MatchHint get hint => _hint;

  /// Секунды минуты. Считаются **разницей часов**, а не счётчиком тиков:
  /// таймер на тиках при заморозке приложения в фоне тихо врёт в пользу
  /// игрока, и по журналу это не увидеть.
  int get secondsUsed {
    if (_committedSecondsUsed != null) return _committedSecondsUsed!;
    final started = _thinkingStartedAt;
    if (started == null) return 0;
    final elapsed = now().difference(started).inSeconds;
    return elapsed.clamp(0, kThinkingSec);
  }

  bool get thinkingExpired => secondsUsed >= kThinkingSec;

  /// Сколько осталось от окна записи. Ноль — поле заблокировано.
  int get writingRemainingSec {
    final started = _writingStartedAt;
    if (started == null) return config.answerWindowSec;
    final left = config.answerWindowSec - now().difference(started).inSeconds;
    return left.clamp(0, config.answerWindowSec);
  }

  bool get writingClosed => writingRemainingSec <= 0;

  void startThinking() {
    if (_phase != CyclePhase.reading) return;
    _phase = CyclePhase.thinking;
    _thinkingStartedAt = now();
    _startTimer();
    notifyListeners();
  }

  /// «Готов отвечать» — минута останавливается на текущей секунде.
  void readyToAnswer() {
    if (_phase != CyclePhase.thinking) return;
    _committedSecondsUsed = secondsUsed;
    _toWriting();
  }

  void _toWriting() {
    _committedSecondsUsed ??= kThinkingSec;
    _phase = CyclePhase.writing;
    _writingStartedAt = now();
    notifyListeners();
  }

  /// Поле записи. По истечении окна набранное остаётся, новое не принимается.
  void setUserAnswer(String text) {
    if (_phase != CyclePhase.writing || writingClosed) return;
    _userAnswer = text;
    notifyListeners();
  }

  /// Уйти из окна записи. Дальше — тап «это бинго?», если он включён:
  /// после раскрытия догадка о клише перестаёт быть догадкой.
  void finishWriting() {
    if (_phase != CyclePhase.writing) return;
    _phase = config.askBingoTap ? CyclePhase.bingoTap : CyclePhase.reveal;
    if (_phase == CyclePhase.reveal) _computeHint();
    _stopTimer();
    notifyListeners();
  }

  /// Непустой текст → догадка; пустое поле → `null`, «не спрашивали».
  /// Пустая строка здесь не пишется: по контракту T10 она значит «ни к одной»,
  /// а это осмысленный выбор только там, где показаны девять клеток (T3).
  void submitBingoTap(String text) {
    if (_phase != CyclePhase.bingoTap) return;
    final t = text.trim();
    _themeGuess = t.isEmpty ? null : t;
    _phase = CyclePhase.reveal;
    _computeHint();
    notifyListeners();
  }

  void _computeHint() {
    _hint = matchAnswer(_userAnswer, question.acceptVariants);
    // Предзаполняется только положительный матч. Предвыбранное «не взял»
    // систематически воровало бы корзину «почти» — диагностически самую ценную.
    _verdict = switch (_hint) {
      MatchHint.taken => Verdict.taken,
      MatchHint.almost => Verdict.almost,
      MatchHint.none => null,
    };
  }

  void toVerdict() {
    if (_phase != CyclePhase.reveal) return;
    _phase = CyclePhase.verdict;
    notifyListeners();
  }

  void setVerdict(Verdict v) {
    _verdict = v;
    if (v == Verdict.taken) _reason = null;
    notifyListeners();
  }

  /// Дальше из самооценки: роутер причины — только при почти/не взял.
  void confirmVerdict() {
    if (_phase != CyclePhase.verdict || _verdict == null) return;
    _phase = _verdict == Verdict.taken ? _afterReason() : CyclePhase.reason;
    notifyListeners();
  }

  /// Пропуск причины разрешён: обязательность даёт до пяти лишних тапов на
  /// раунд и провоцирует жать первое попавшееся.
  void setReason(MissReason? r) {
    _reason = r;
    notifyListeners();
  }

  void confirmReason() {
    if (_phase != CyclePhase.reason) return;
    _phase = _afterReason();
    notifyListeners();
  }

  CyclePhase _afterReason() =>
      config.tehnika != null ? CyclePhase.tehnika : CyclePhase.done;

  /// Догадка меняется свободно, пока не нажато «Ответить»: промах пальцем по
  /// сегменту не должен запирать игрока в случайном ответе.
  void setTehnikaGuess(bool? v) {
    if (_tehnikaAnswered) return;
    _tehnikaGuess = v;
    notifyListeners();
  }

  /// Ответ зафиксирован, показан разбор; менять решение уже нельзя — иначе,
  /// увидев вердикт, можно переписать догадку на правильную, и разметка,
  /// ради которой тап и существует, станет липовой.
  bool _tehnikaAnswered = false;
  bool get tehnikaAnswered => _tehnikaAnswered;

  /// Вердикт выносится **только когда эталон говорит «да»**. Эталон с низкой
  /// полнотой не даёт права сказать «приёма здесь не было»: игрок мог увидеть
  /// то, что правило поиска пропустило.
  bool get tehnikaVerdictKnown => config.tehnikaInStandard;
  bool get tehnikaGuessedRight =>
      config.tehnikaInStandard && _tehnikaGuess == true;

  void revealTehnika() {
    if (_phase != CyclePhase.tehnika || _tehnikaAnswered) return;
    if (_tehnikaGuess == null) return;
    _tehnikaAnswered = true;
    notifyListeners();
  }

  void confirmTehnika() {
    if (_phase != CyclePhase.tehnika) return;
    _phase = CyclePhase.done;
    notifyListeners();
  }

  /// Собранное событие. Писать его в журнал — дело режима, не цикла:
  /// у T12 «одна попытка в сутки», у T3 смешанный корпус в раунде.
  AnswerEvent buildEvent() {
    final ts = now();
    return AnswerEvent(
      ts: ts.toUtc().millisecondsSinceEpoch,
      day: localDay(ts),
      questionId: question.id,
      corpus: question.corpus,
      mode: config.mode,
      verdict: _verdict ?? Verdict.missed,
      secondsUsed: secondsUsed,
      answerWindowSec: config.answerWindowSec,
      userAnswer: _userAnswer,
      reason: _verdict == Verdict.taken ? null : _reason,
      roundId: config.roundId,
      theme: question.theme,
      themeGuess: _themeGuess,
      tehnikaGuess: _tehnikaGuess,
    );
  }

  void _startTimer() {
    _timer ??= Timer.periodic(_tick, (_) => _onTick());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Тик только перерисовывает и ловит истечение — источник правды часы.
  void _onTick() {
    if (_phase == CyclePhase.thinking && thinkingExpired) {
      _toWriting();
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
