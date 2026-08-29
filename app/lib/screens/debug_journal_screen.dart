import 'package:flutter/material.dart';

import '../data/question_repository.dart';
import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';

/// Сырые числа для сверки с критериями MVP. Не подменяет T9: там профиль и
/// карта слабых мест с дизайном, здесь — строки текста, которые выбрасываются
/// или перерастают в T9 по её ходу.
///
/// Вход спрятан под долгий тап по заголовку: это отладка, а не функция.
class DebugJournalScreen extends StatefulWidget {
  final QuestionRepository repository;
  final DateTime Function()? now;

  const DebugJournalScreen({super.key, required this.repository, this.now});

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
      if (!mounted) return;
      setState(() {
        _events = read.events;
        _skippedLines = read.skippedLines;
        _loadMs = sw.elapsedMilliseconds;
        _questionCount = questions.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
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
        _row('Первое событие', firstDay),
        // Битые строки прячутся последними по важности, но не прячутся вовсе:
        // журнал, часть которого не прочитана, не имеет права выглядеть целым.
        _row('Непрочитанных строк', '$_skippedLines',
            alarm: _skippedLines > 0, key: const Key('debug-skipped')),
        const Divider(height: 32),
        _row('Вопросов в ассете', '$_questionCount'),
        _row('Загрузка вопросов', _loadMs == null ? '—' : '$_loadMs мс',
            alarm: (_loadMs ?? 0) > 1000),
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
