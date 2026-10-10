import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/svoyak.dart';
import 'answer_match.dart';
import 'cycle_controller.dart' show kDefaultAnswerWindowSec;

/// Окно на решение «Знаю!/Пас» (T6). Вопросы «Своей игры» — в одно-два
/// предложения; длина пишется в событие, подкрутка не ломает сравнимость.
const int kSvoyakDecideSec = 10;

enum SvoyakPhase { deciding, writing, reveal }

/// Один вопрос «Своей игры»: показ → «Знаю!» или пас → версия → раскрытие.
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
        _tick = tick {
    _shownAt = this.now();
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  final Duration _tick;
  Timer? _timer;
  late final DateTime _shownAt;
  DateTime? _writingStartedAt;
  int? _committedSecondsUsed;

  SvoyakPhase _phase = SvoyakPhase.deciding;
  SvoyakPhase get phase => _phase;

  bool _buzzed = false;
  bool get buzzed => _buzzed;

  String _userAnswer = '';
  String get userAnswer => _userAnswer;

  MatchHint _hint = MatchHint.none;
  MatchHint get hint => _hint;

  /// Секунды от показа до нажатия или истечения. Разницей часов, а не
  /// тиками — по той же причине, что в [CycleController.secondsUsed].
  int get secondsUsed {
    if (_committedSecondsUsed != null) return _committedSecondsUsed!;
    return now().difference(_shownAt).inSeconds.clamp(0, decideSec);
  }

  int get decideRemainingSec => decideSec - secondsUsed;

  int get writingRemainingSec {
    final started = _writingStartedAt;
    if (started == null) return answerWindowSec;
    final left = answerWindowSec - now().difference(started).inSeconds;
    return left.clamp(0, answerWindowSec);
  }

  bool get writingClosed => writingRemainingSec <= 0;

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
