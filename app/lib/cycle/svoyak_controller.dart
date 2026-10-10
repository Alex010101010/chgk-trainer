import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/svoyak.dart';
import 'answer_match.dart';
import 'cycle_controller.dart' show kDefaultAnswerWindowSec;

/// Окно на решение «Знаю!/Пас» (T6). Отсчёт идёт после чтения — как на
/// турнире, где время пошло, когда ведущий дочитал. Первая версия считала
/// 10 секунд с показа и съедала время на чтение (обкатка 10.10.2026). Длина
/// пишется в событие — подкрутка не ломает сравнимость.
const int kSvoyakDecideSec = 30;

enum SvoyakPhase { reading, deciding, writing, reveal }

/// Один вопрос «Своей игры»: чтение → «Прочитал» → «Знаю!» или пас →
/// версия → раскрытие.
///
/// Свой контроллер, а не [CycleController]: тот построен на минуте
/// обсуждения, а здесь её нет — решение «жать или нет» и есть навык.
class SvoyakController extends ChangeNotifier {
  final SvoyakQuestion item;

  /// Часы инжектируются — seam для тестов таймера, как у [CycleController].
  final DateTime Function() now;
  final int decideSec;
  final int answerWindowSec;

  SvoyakController({
    required this.item,
    DateTime Function()? now,
    this.decideSec = kSvoyakDecideSec,
    this.answerWindowSec = kDefaultAnswerWindowSec,
    Duration tick = const Duration(milliseconds: 200),
  })  : now = now ?? DateTime.now,
        _tick = tick;

  final Duration _tick;
  Timer? _timer;
  DateTime? _decideStartedAt;
  DateTime? _writingStartedAt;
  int? _committedSecondsUsed;

  SvoyakPhase _phase = SvoyakPhase.reading;
  SvoyakPhase get phase => _phase;

  bool _buzzed = false;
  bool get buzzed => _buzzed;

  String _userAnswer = '';
  String get userAnswer => _userAnswer;

  MatchHint _hint = MatchHint.none;
  MatchHint get hint => _hint;

  /// Секунды от «Прочитал» до нажатия или истечения; чтение не считается.
  /// Разницей часов, а не тиками — по той же причине, что в
  /// [CycleController.secondsUsed].
  int get secondsUsed {
    if (_committedSecondsUsed != null) return _committedSecondsUsed!;
    final started = _decideStartedAt;
    if (started == null) return 0;
    return now().difference(started).inSeconds.clamp(0, decideSec);
  }

  int get decideRemainingSec => decideSec - secondsUsed;

  int get writingRemainingSec {
    final started = _writingStartedAt;
    if (started == null) return answerWindowSec;
    final left = answerWindowSec - now().difference(started).inSeconds;
    return left.clamp(0, answerWindowSec);
  }

  bool get writingClosed => writingRemainingSec <= 0;

  /// «Прочитал» — пошёл отсчёт на решение.
  void startDeciding() {
    if (_phase != SvoyakPhase.reading) return;
    _phase = SvoyakPhase.deciding;
    _decideStartedAt = now();
    _timer = Timer.periodic(_tick, (_) => _onTick());
    notifyListeners();
  }

  void _onTick() {
    if (_phase == SvoyakPhase.deciding && decideRemainingSec <= 0) {
      pass();
    } else if (_phase != SvoyakPhase.reveal) {
      notifyListeners();
    }
  }

  /// «Знаю!» — отсчёт стоп, открывается окно записи.
  void buzz() {
    if (_phase != SvoyakPhase.deciding) return;
    _committedSecondsUsed = secondsUsed;
    _buzzed = true;
    _phase = SvoyakPhase.writing;
    _writingStartedAt = now();
    notifyListeners();
  }

  /// Пас или истечение отсчёта — сразу раскрытие, очков ноль.
  void pass() {
    if (_phase != SvoyakPhase.deciding) return;
    _committedSecondsUsed = secondsUsed;
    _toReveal();
  }

  /// По истечении окна набранное остаётся, новое не принимается.
  void setUserAnswer(String text) {
    if (_phase != SvoyakPhase.writing || writingClosed) return;
    _userAnswer = text;
    notifyListeners();
  }

  void finishWriting() {
    if (_phase != SvoyakPhase.writing) return;
    _hint = matchAnswer(_userAnswer, item.question.acceptVariants);
    _toReveal();
  }

  void _toReveal() {
    _phase = SvoyakPhase.reveal;
    _timer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
