import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/svoyak.dart';

/// Окно на решение «Знаю!/Пас» (T6). Отсчёт идёт после чтения — как на
/// турнире, где время пошло, когда ведущий дочитал. Первая версия считала
/// 10 секунд с показа и съедала время на чтение (обкатка 10.10.2026). Длина
/// пишется в событие — подкрутка не ломает сравнимость.
const int kSvoyakDecideSec = 30;

enum SvoyakPhase { reading, deciding, reveal }

/// Один вопрос «Своей игры»: чтение → «Прочитал» → «Знаю!» или пас →
/// раскрытие → самооценка без ввода версии.
///
/// Свой контроллер, а не [CycleController]: тот построен на минуте
/// обсуждения, а здесь её нет — решение «жать или нет» и есть навык.
class SvoyakController extends ChangeNotifier {
  final SvoyakQuestion item;

  /// Часы инжектируются — seam для тестов таймера, как у [CycleController].
  final DateTime Function() now;
  final int decideSec;

  SvoyakController({
    required this.item,
    DateTime Function()? now,
    this.decideSec = kSvoyakDecideSec,
    Duration tick = const Duration(milliseconds: 200),
  })  : now = now ?? DateTime.now,
        _tick = tick {
    _shownAt = this.now();
  }

  final Duration _tick;
  late final DateTime _shownAt;

  /// От появления вопроса до «Знаю!», включая чтение. При пасе — null.
  int? get responseSeconds => _responseSeconds;
  int? _responseSeconds;
  Timer? _timer;
  DateTime? _decideStartedAt;
  int? _committedSecondsUsed;

  SvoyakPhase _phase = SvoyakPhase.reading;
  SvoyakPhase get phase => _phase;

  bool _buzzed = false;
  bool get buzzed => _buzzed;

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

  /// «Знаю!» — отсчёт стоп, сразу ответ и самостоятельная оценка.
  void buzz() {
    if (_phase != SvoyakPhase.deciding) return;
    _committedSecondsUsed = secondsUsed;
    _responseSeconds = now().difference(_shownAt).inSeconds.clamp(0, 1 << 31);
    _buzzed = true;
    _toReveal();
  }

  /// Пас или истечение отсчёта — сразу раскрытие, очков ноль.
  void pass() {
    if (_phase != SvoyakPhase.deciding) return;
    _committedSecondsUsed = secondsUsed;
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
