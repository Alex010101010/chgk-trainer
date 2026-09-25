import 'package:flutter/material.dart';

import '../data/question_repository.dart';
import '../data/tehnika_repository.dart';
import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../data/handout_store.dart';
import '../model/question.dart';
import '../model/tehnika.dart';

/// Сырые числа для сверки с критериями MVP. Не подменяет T9: там профиль и
/// карта слабых мест с дизайном, здесь — строки текста, которые выбрасываются
/// или перерастают в T9 по её ходу.
///
/// Вход спрятан под долгий тап по заголовку: это отладка, а не функция.
class DebugJournalScreen extends StatefulWidget {
  final QuestionRepository repository;
  final TehnikaRepository? tehnikaRepository;
  final DateTime Function()? now;

  const DebugJournalScreen({
    super.key,
    required this.repository,
    this.tehnikaRepository,
    this.now,
  });

  @override
  State<DebugJournalScreen> createState() => _DebugJournalScreenState();
}

class _DebugJournalScreenState extends State<DebugJournalScreen> {
  List<JournalEvent>? _events;
  int _skippedLines = 0;
  String? _error;

  /// Замер из критерия успеха T2b: больше секунды — заводим шарды.
  int? _loadMs;
  int _questionCount = 0;

  /// Раздатки (T20): сколько вопросов их объявляют и лежит ли рядом сам файл.
  /// Поле в ассете и картинка в бандле — два разных канала, и «в вопросе есть
  /// `handout`» ещё не значит, что картинку будет чем показать.
  int _handoutCount = 0;
  bool? _handoutFileFound;

  /// Приём недели и его запас (T22). Неделя стажа и номер приёма расходятся,
  /// когда приёмы кончились, — и раньше это было видно только по тому, что
  /// урок не сменился. Эталоны кончаются ещё раньше: слот раунда тогда молча
  /// берёт случайный вопрос, и вердикты по приёму перестают появляться.
  List<Tehnika> _tehniki = const [];
  List<Question> _questions = const [];

  bool _started = false;

  // Не initState: `JournalScope.of` — это dependOnInheritedWidgetOfExactType,
  // а его нельзя звать до того, как зависимости смонтированы.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(JournalScope.of(context));
  }

  Future<void> _load(EventLog log) async {
    try {
      final read = await log.readAll();
      final sw = Stopwatch()..start();
      final questions = await widget.repository.loadAll();
      sw.stop();
      final tehniki = await widget.tehnikaRepository?.loadAll() ?? const [];
      if (!mounted) return;
      final withHandout = questions.where((q) => q.handout != null).toList();
      bool? fileFound;
      if (withHandout.isNotEmpty) {
        try {
          // С T30 картинки не в сборке, а на Pages: проверяется, что первую
          // из них можно получить — из кэша или скачав.
          await HandoutStore.instance.resolve(withHandout.first.handout!);
          fileFound = true;
        } catch (_) {
          fileFound = false;
        }
      }
      if (!mounted) return;
      setState(() {
        _events = read.events;
        _skippedLines = read.skippedLines;
        _loadMs = sw.elapsedMilliseconds;
        _questionCount = questions.length;
        _handoutCount = withHandout.length;
        _handoutFileFound = fileFound;
        _tehniki = tehniki;
        _questions = questions;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  List<Widget> _tehnikaRows(List<JournalEvent> events, DateTime now) {
    if (_tehniki.isEmpty) return const [];
    final pick = tehnikaForWeek(_tehniki, weekIndex(events, now));
    final seen = events.whereType<AnswerEvent>().map((e) => e.questionId).toSet();
    // Как в `selectRound`: эталон — невиденный вопрос gq с этим приёмом.
    final left = _questions
        .where((q) =>
            q.corpus == Corpus.gq &&
            q.tehniki.contains(pick.tehnika.id) &&
            !seen.contains(q.id))
        .length;
    return [
      _row(
        'Приём',
        '${pick.index + 1} из ${_tehniki.length}${pick.repeated ? ' · повтор' : ''}',
        alarm: pick.repeated,
        key: const Key('debug-tehnika'),
      ),
      _row('Эталонов приёма не видено', '$left',
          alarm: left == 0, key: const Key('debug-tehnika-left')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Журнал')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(_error!));
    }
    final events = _events;
    if (events == null) return const Center(child: CircularProgressIndicator());

    final now = (widget.now ?? DateTime.now)();
    final answers = events.whereType<AnswerEvent>().toList();
    final rate = takenRate(events, window: 50);
    final firstDay = events.isEmpty
        ? '—'
        : events.map((e) => e.day).reduce((a, b) => a.compareTo(b) <= 0 ? a : b);

    return ListView(
      key: const Key('debug-journal'),
      padding: const EdgeInsets.all(16),
      children: [
        _row('Событий в журнале', '${events.length}'),
        _row('Ответов', '${answers.length}'),
        _row('Streak, дней', '${currentStreak(events, now)}'),
        _row('Доля взятых (посл. 50)',
            rate == null ? '—' : '${(rate * 100).round()}%'),
        _row('Ждут возврата', '${dueQuestions(events, now).length}'),
        _row('Неделя стажа', '${weekIndex(events, now)}'),
        ..._tehnikaRows(events, now),
        _row('Первое событие', firstDay),
        // Битые строки прячутся последними по важности, но не прячутся вовсе:
        // журнал, часть которого не прочитана, не имеет права выглядеть целым.
        _row('Непрочитанных строк', '$_skippedLines',
            alarm: _skippedLines > 0, key: const Key('debug-skipped')),
        const Divider(height: 32),
        _row('Вопросов в ассете', '$_questionCount'),
        _row('Загрузка вопросов', _loadMs == null ? '—' : '$_loadMs мс',
            alarm: (_loadMs ?? 0) > 1000),
        _row('Вопросов с раздаткой', '$_handoutCount',
            alarm: _handoutCount == 0, key: const Key('debug-handouts')),
        _row(
          'Картинка раздатки',
          switch (_handoutFileFound) {
            true => 'на месте',
            false => 'не скачивается',
            null => '—',
          },
          alarm: _handoutFileFound == false,
          key: const Key('debug-handout-file'),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool alarm = false, Key? key}) {
    final color = alarm ? Theme.of(context).colorScheme.error : null;
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: color)),
        ],
      ),
    );
  }
}
