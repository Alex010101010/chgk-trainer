import 'dart:math';

import 'package:flutter/material.dart';

import '../cycle/cycle_controller.dart';
import '../cycle/question_cycle.dart';
import '../cycle/tehnika_tap.dart';
import '../data/question_repository.dart';
import '../data/tehnika_repository.dart';
import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../model/question.dart';
import '../model/tehnika.dart';
import '../panda/panda_voice.dart';
import '../widgets/panda_says.dart';
import 'tehnika_card_screen.dart';

const int kRoundSize = 5;

/// Отбор вопросов в раунд: **первый слот — созревший**, остальные случайные из
/// невиденных. Раунд целиком из созревших отвергнут — это зубрёжка, а Классика
/// по концепту поток новых.
///
/// Невиденные кончились (через ~1770 раундов) — берутся самые давние.
List<Question> selectRound(
  List<Question> pool,
  List<JournalEvent> events,
  DateTime now, {
  int size = kRoundSize,
  Random? random,
  String? tehnikaId,
}) {
  final rnd = random ?? Random();
  final answers = events.whereType<AnswerEvent>().toList();
  final seen = answers.map((e) => e.questionId).toSet();
  final byId = {for (final q in pool) q.id: q};

  final picked = <Question>[];
  final used = <String>{};

  final due = dueQuestions(events, now).where(byId.containsKey).toList();
  if (due.isNotEmpty) {
    final q = byId[due[rnd.nextInt(due.length)]]!;
    picked.add(q);
    used.add(q.id);
  }

  // Один слот — эталонный вопрос приёма недели. Их 91 на 8866, и случайно
  // такой вопрос не попадался бы неделями: тап показывался бы всегда на
  // вопросах без эталона, то есть без обратной связи.
  if (tehnikaId != null && picked.length < size) {
    final marked = pool
        .where((q) => q.tehniki.contains(tehnikaId) && !seen.contains(q.id))
        .toList();
    if (marked.isNotEmpty) {
      final q = marked[rnd.nextInt(marked.length)];
      if (used.add(q.id)) picked.add(q);
    }
  }

  final unseen = pool.where((q) => !seen.contains(q.id)).toList()..shuffle(rnd);
  for (final q in unseen) {
    if (picked.length >= size) break;
    if (used.add(q.id)) picked.add(q);
  }

  if (picked.length < size) {
    final lastTs = <String, int>{};
    for (final a in answers) {
      final prev = lastTs[a.questionId];
      if (prev == null || a.ts > prev) lastTs[a.questionId] = a.ts;
    }
    final oldest = pool.where((q) => !used.contains(q.id)).toList()
      ..sort((a, b) => (lastTs[a.id] ?? 0).compareTo(lastTs[b.id] ?? 0));
    for (final q in oldest) {
      if (picked.length >= size) break;
      if (used.add(q.id)) picked.add(q);
    }
  }
  return picked;
}

class ClassicScreen extends StatefulWidget {
  final QuestionRepository repository;
  final TehnikaRepository? tehnikaRepository;
  final TehnikaCardSeen? cardSeen;
  final Random? random;
  final DateTime Function()? now;

  const ClassicScreen({
    super.key,
    required this.repository,
    this.tehnikaRepository,
    this.cardSeen,
    this.random,
    this.now,
  });

  @override
  State<ClassicScreen> createState() => _ClassicScreenState();
}

class _ClassicScreenState extends State<ClassicScreen> {
  late EventLog _log;
  DateTime Function() get _now => widget.now ?? DateTime.now;

  List<Question>? _pool;
  String? _error;

  /// Журнал держится в памяти и дополняется по ходу: иначе вопрос, отвеченный
  /// в этом раунде, вернулся бы в следующем.
  List<JournalEvent> _events = [];
  int _skippedLines = 0;

  Tehnika? _tehnika;
  Map<String, Question> _tehnikaExamples = const {};

  /// Карточка урока перед раундом. Показывается один раз за неделю стажа.
  bool _showCard = false;

  List<Question> _round = [];
  int _index = 0;
  String _roundId = '';
  final List<AnswerEvent> _results = [];

  bool _started = false;

  // Не initState: `JournalScope.of` — это dependOnInheritedWidgetOfExactType,
  // а его нельзя звать до того, как зависимости смонтированы. Раньше это
  // сходило с рук лишь потому, что журнал читался после первого `await`.
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
      // Только gq: бинго-корпус конечен, и вопрос, потраченный здесь, стал бы
      // виденным — тема осталась бы в пуле сеток без непоказанного вопроса (T3).
      // Только gq: бинго-корпус конечен, и вопрос, потраченный здесь, стал бы
      // виденным — тема осталась бы в пуле сеток без непоказанного вопроса (T3).
      final pool = (await widget.repository.loadAll())
          .where((q) => q.corpus == Corpus.gq)
          .toList();
      final tehniki =
          await (widget.tehnikaRepository ?? AssetTehnikaRepository()).loadAll();
      final read = await _log.readAll();
      if (!mounted) return;
      final events = List.of(read.events);
      // Приёмы открываются по одному; когда они кончились, последний остаётся.
      final tehnika =
          tehniki[min(weekIndex(events, _now()), tehniki.length - 1)];
      final byId = {for (final q in pool) q.id: q};
      setState(() {
        _pool = pool;
        _events = events;
        _skippedLines = read.skippedLines;
        _tehnika = tehnika;
        _tehnikaExamples = {
          for (final e in tehnika.examples)
            if (byId[e.questionId] case final q?) e.questionId: q,
        };
        // Первый за неделю вход в режим — сперва урок. Но не второй раз
        // подряд, если игрок только что прочитал карточку с главного экрана.
        _showCard = !answeredThisWeek(events, _now()) &&
            !(widget.cardSeen?.value ?? false);
        if (_showCard) widget.cardSeen?.value = true;
      });
      _startRound();
    } on QuestionAssetException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось открыть режим: $e');
    }
  }

  void _startRound() {
    final now = _now();
    setState(() {
      _roundId = now.millisecondsSinceEpoch.toString();
      _round = selectRound(_pool!, _events, now,
          random: widget.random, tehnikaId: _tehnika?.id);
      _index = 0;
      _results.clear();
    });
  }

  /// Событие пишется после каждого вопроса: краш на четвёртом не имеет права
  /// стоить трёх предыдущих ответов.
  Future<void> _onFinished(AnswerEvent e) async {
    try {
      await _log.append(e);
    } catch (err) {
      debugPrint('[journal] не удалось записать ответ: $err');
    }
    if (!mounted) return;
    setState(() {
      _events = [..._events, e];
      _results.add(e);
      _index++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_index < _round.length && _round.isNotEmpty
            ? 'Классика · ${_index + 1}/${_round.length}'
            : 'Классика'),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(_error!, key: const Key('classic-error'))),
      );
    }
    if (_pool == null) return const Center(child: CircularProgressIndicator());
    if (_showCard && _tehnika != null) {
      return TehnikaCard(
        tehnika: _tehnika!,
        questions: _tehnikaExamples,
        onDone: () => setState(() => _showCard = false),
      );
    }

    return Column(
      children: [
        if (_skippedLines > 0) _journalWarning(),
        Expanded(
          child: _index >= _round.length ? _summary() : _current(),
        ),
      ],
    );
  }

  /// Молчать нельзя: отбор опирается на «уже виденные», и частично прочитанный
  /// журнал тихо вернёт в поток то, что игрок уже проходил.
  Widget _journalWarning() => Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.errorContainer,
        padding: const EdgeInsets.all(12),
        child: Text(
          'Часть журнала не прочитана ($_skippedLines строк) — '
          'вопросы могут повторяться',
          key: const Key('classic-journal-warning'),
          style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        ),
      );

  Widget _current() {
    final q = _round[_index];
    final inStandard = _tehnika != null && q.tehniki.contains(_tehnika!.id);
    final askTehnika = _tehnika != null &&
        shouldAskTehnika(q.id, inStandard: inStandard);
    return QuestionCycle(
      // Свой ключ на вопрос: без него Flutter переиспользует состояние цикла
      // и второй вопрос открывается на фазе раскрытия первого.
      key: ValueKey('${_roundId}_${q.id}'),
      question: q,
      config: CycleConfig(
        mode: GameMode.classic,
        roundId: _roundId,
        tehnika: askTehnika ? _tehnika : null,
        tehnikaInStandard: inStandard,
      ),
      onFinished: _onFinished,
      now: widget.now,
    );
  }

  static const _verdictLabels = {
    Verdict.taken: 'взял',
    Verdict.almost: 'почти',
    Verdict.missed: 'не взял',
  };

  Widget _summary() {
    final taken = _results.where((e) => e.verdict == Verdict.taken).length;
    return ListView(
      key: const Key('classic-summary'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Раунд закончен', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Взято $taken из ${_results.length}'),
        const SizedBox(height: 16),
        for (var i = 0; i < _results.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Text('${i + 1}'),
            title: Text(_round[i].question,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Text(_verdictLabels[_results[i].verdict]!),
          ),
        const SizedBox(height: 16),
        PandaSays(key: ValueKey(_roundId), moment: PandaMoments.roundEnd),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('classic-next-round'),
          onPressed: _startRound,
          child: const Text('Ещё раунд'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('В меню'),
        ),
      ],
    );
  }
}
