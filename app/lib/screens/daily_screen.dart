import 'package:flutter/material.dart';

import '../cycle/cycle_controller.dart';
import '../cycle/question_cycle.dart';
import '../data/question_repository.dart';
import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../model/question.dart';
import '../panda/panda_voice.dart';
import '../widgets/panda_says.dart';

/// FNV-1a 32 бита — хеш, устойчивый между запусками и устройствами:
/// `String.hashCode` в Dart этого не обещает, а вопрос дня обязан совпасть
/// у всех, кто играет в этот день.
int fnv1a(String s) {
  var hash = 0x811c9dc5;
  for (final c in s.codeUnits) {
    hash ^= c & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
    if (c > 0xff) {
      hash ^= (c >> 8) & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
  }
  return hash;
}

/// Вопрос дня (T12): у каждого вопроса по дате считается хеш, побеждает
/// наименьший. Не `pool[hash(day) % length]`: там пересборка корпуса (T21,
/// T27 вернули в него сотни вопросов) сдвигала бы индекс, и сегодняшний
/// вопрос у двух сборок разошёлся бы. Здесь он меняется, только если новый
/// вопрос обыгрывает прежнего победителя.
Question? dailyQuestion(List<Question> pool, String day) {
  Question? best;
  var bestHash = 0;
  for (final q in pool) {
    final h = fnv1a('$day|${q.id}');
    if (best == null || h < bestHash) {
      best = q;
      bestHash = h;
    }
  }
  return best;
}

class DailyScreen extends StatefulWidget {
  final QuestionRepository repository;
  final DateTime Function()? now;

  const DailyScreen({super.key, required this.repository, this.now});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  late EventLog _log;
  DateTime Function() get _now => widget.now ?? DateTime.now;
  bool _started = false;

  Question? _question;
  List<JournalEvent> _events = [];
  String? _error;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _log = JournalScope.of(context);
    _load();
  }

  Future<void> _load() async {
    try {
      // Только gq, как в Классике: бинго-корпус конечен и тратится сеткой.
      final pool = (await widget.repository.loadAll())
          .where((q) => q.corpus == Corpus.gq)
          .toList();
      final read = await _log.readAll();
      if (!mounted) return;
      setState(() {
        _question = dailyQuestion(pool, localDay(_now()));
        _events = List.of(read.events);
        _loaded = true;
      });
    } on QuestionAssetException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось открыть вопрос дня: $e');
    }
  }

  Future<void> _onFinished(AnswerEvent e) async {
    try {
      await _log.append(e);
    } catch (err) {
      debugPrint('[journal] не удалось записать ответ: $err');
    }
    if (mounted) setState(() => _events = [..._events, e]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вопрос дня')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(_error!, key: const Key('daily-error'))),
      );
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final q = _question;
    if (q == null) {
      return const Center(child: Text('Вопросов в корпусе нет'));
    }
    final today = localDay(_now());
    // Одна попытка: сыгранный сегодня вопрос показывается итогом, а не заново.
    if (dailyResults(_events)[today] case final verdict?) {
      return _result(q, verdict);
    }
    return QuestionCycle(
      question: q,
      config: const CycleConfig(mode: GameMode.daily),
      onFinished: _onFinished,
      now: widget.now,
    );
  }

  static const _verdictLabels = {
    Verdict.taken: 'Взял',
    Verdict.almost: 'Почти',
    Verdict.missed: 'Не взял',
  };

  static const _verdictMarks = {
    Verdict.taken: '●',
    Verdict.almost: '◐',
    Verdict.missed: '○',
  };

  Widget _result(Question q, Verdict verdict) {
    final now = _now();
    final results = dailyResults(_events);
    final streak = dailyStreak(_events, now);
    final today = DateTime.parse(localDay(now));
    // Неделя назад → сегодня: история читается слева направо, как календарь.
    final week = [
      for (var i = 6; i >= 0; i--) localDay(today.subtract(Duration(days: i))),
    ];
    final text = Theme.of(context).textTheme;
    return ListView(
      key: const Key('daily-result'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Сегодня: ${_verdictLabels[verdict]!.toLowerCase()}',
            style: text.headlineSmall),
        const SizedBox(height: 8),
        Text('Ответ: ${q.answer}'),
        const SizedBox(height: 16),
        Text('Дней подряд: $streak', key: const Key('daily-streak')),
        const SizedBox(height: 8),
        Row(
          key: const Key('daily-week'),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final day in week)
              Column(
                children: [
                  Text(results[day] == null ? '·' : _verdictMarks[results[day]]!,
                      style: text.titleLarge),
                  Text(day.substring(8), style: text.labelSmall),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Реплика на вердикт: из цикла её убрали (T26), а здесь вопрос один,
        // и реакция на него — часть ритуала.
        PandaSays(
          key: ValueKey(verdict),
          moment: switch (verdict) {
            Verdict.taken => PandaMoments.took,
            Verdict.almost => PandaMoments.almost,
            Verdict.missed => PandaMoments.missed,
          },
        ),
        const SizedBox(height: 16),
        const Text('Следующий вопрос — завтра.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('В меню'),
        ),
      ],
    );
  }
}
