import 'dart:math';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/question_repository.dart';
import '../data/tehnika_repository.dart';
import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../model/question.dart';
import '../model/tehnika.dart';
import '../panda/panda_voice.dart';
import '../widgets/handout_image.dart';
import '../widgets/handout_text.dart';
import '../widgets/panda_says.dart';
import 'daily_screen.dart';

/// Больше кнопок приёмов не показываем: список из девятнадцати строк —
/// это перебор, а не узнавание.
const int kCheckMaxOptions = 6;

/// Приёмы, открытые к неделе стажа [week]: по одному в неделю, и все прошлые
/// остаются в игре.
List<Tehnika> openedTehniki(List<Tehnika> tehniki, int week) =>
    tehniki.isEmpty ? const [] : tehniki.sublist(0, tehnikaForWeek(tehniki, week).index + 1);

/// Отбор вопросов проверки недели (T4b): невиденные эталонные вопросы
/// открытых приёмов. Два слота из [kCheckSize] — приёму текущей недели,
/// остальные по кругу прочим. У приёма без невиденных слот уходит следующему.
///
/// Уже сыгранные на этой неделе ответы вычитаются из плана: вышедший на
/// середине доигрывает остаток, и новый приём не получает третий слот.
///
/// Только эталонные: вне эталона «приёма нет» не знание, а незнание, и
/// спрашивать «какой?» там не о чем.
List<Question> selectCheckRound(
  List<Question> pool,
  List<Tehnika> opened,
  List<JournalEvent> events,
  DateTime now, {
  Random? random,
}) {
  if (opened.isEmpty) return const [];
  final rnd = random ?? Random();
  final seen = events.whereType<AnswerEvent>().map((e) => e.questionId).toSet();
  final byId = {for (final q in pool) q.id: q};

  final current = opened.last;
  final plan = <Tehnika>[current, current];
  for (var i = 0; plan.length < kCheckSize; i++) {
    final t = opened[i % opened.length];
    if (opened.length > 1 && t == current) continue;
    plan.add(t);
  }
  for (final a in tehnikaCheckAnswers(events, now)) {
    final ids = byId[a.questionId]?.tehniki ?? const [];
    final i = plan.indexWhere((t) => ids.contains(t.id));
    if (i >= 0) {
      plan.removeAt(i);
    } else if (plan.isNotEmpty) {
      plan.removeLast();
    }
  }

  final unseen = {
    for (final t in opened)
      t.id: pool
          .where((q) =>
              q.corpus == Corpus.gq &&
              q.tehniki.contains(t.id) &&
              !seen.contains(q.id))
          .toList()
        ..shuffle(rnd),
  };
  final used = <String>{};
  Question? take(Tehnika t) {
    final list = unseen[t.id]!;
    while (list.isNotEmpty) {
      final q = list.removeLast();
      if (used.add(q.id)) return q;
    }
    return null;
  }

  final round = <Question>[];
  for (final t in plan) {
    final start = opened.indexOf(t);
    for (var k = 0; k < opened.length; k++) {
      final q = take(opened[(start + k) % opened.length]);
      if (q != null) {
        round.add(q);
        break;
      }
    }
  }
  return round..shuffle(rnd);
}

/// Кнопки приёмов для вопроса. Открытых не больше [kCheckMaxOptions] — все, в
/// порядке открытия; больше — верный и пять других, выбранных сидом от id
/// вопроса, чтобы при повторном показе набор не менялся.
List<Tehnika> checkOptions(Question q, List<Tehnika> opened) {
  if (opened.length <= kCheckMaxOptions) return opened;
  final right = opened.firstWhere((t) => q.tehniki.contains(t.id),
      orElse: () => opened.last);
  final others = opened.where((t) => t != right).toList()
    ..shuffle(Random(fnv1a(q.id)));
  final chosen = {right, ...others.take(kCheckMaxOptions - 1)};
  return opened.where(chosen.contains).toList();
}

/// Проверка недели (T4b): вопрос → «какой здесь приём?» → ответ и верный
/// приём. Без минуты и без самооценки: проверяется узнавание приёма, а не
/// взятие вопроса, поэтому `CycleController` с его таймером здесь не нужен.
class TehnikaCheckScreen extends StatefulWidget {
  final QuestionRepository repository;
  final TehnikaRepository tehnikaRepository;
  final DateTime Function()? now;
  final Random? random;

  const TehnikaCheckScreen({
    super.key,
    required this.repository,
    required this.tehnikaRepository,
    this.now,
    this.random,
  });

  @override
  State<TehnikaCheckScreen> createState() => _TehnikaCheckScreenState();
}

class _TehnikaCheckScreenState extends State<TehnikaCheckScreen> {
  late EventLog _log;
  bool _started = false;
  String? _error;

  List<Tehnika>? _opened;
  List<JournalEvent> _events = const [];
  List<Question> _round = const [];
  String _roundId = '';
  int _index = 0;

  /// Выбранный на текущем вопросе приём; `null` — ещё выбирает.
  Tehnika? _pick;

  DateTime _now() => (widget.now ?? DateTime.now)();

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
      final gq = (await widget.repository.loadAll())
          .where((q) => q.corpus == Corpus.gq)
          .toList();
      // Сегодняшний вопрос дня проверке не отдаётся — иначе она испортила бы
      // ритуал T12, как испортила бы его «Классика».
      final daily = dailyQuestion(gq, localDay(_now()));
      final pool = gq.where((q) => q.id != daily?.id).toList();
      final tehniki = await widget.tehnikaRepository.loadAll();
      final events = (await _log.readAll()).events;
      if (!mounted) return;
      final opened = openedTehniki(tehniki, weekIndex(events, _now()));
      setState(() {
        _opened = opened;
        _events = events;
        _roundId = _now().millisecondsSinceEpoch.toString();
        _round = selectCheckRound(pool, opened, events, _now(),
            random: widget.random);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось открыть проверку: $e');
    }
  }

  /// Событие пишется сразу по выбору: краш на четвёртом вопросе не имеет
  /// права стоить трёх предыдущих ответов.
  Future<void> _choose(Tehnika t) async {
    final q = _round[_index];
    final ts = _now();
    final e = AnswerEvent(
      ts: ts.millisecondsSinceEpoch,
      day: localDay(ts),
      questionId: q.id,
      corpus: q.corpus,
      mode: GameMode.tehnika,
      verdict: q.tehniki.contains(t.id) ? Verdict.taken : Verdict.missed,
      secondsUsed: 0,
      answerWindowSec: 0,
      roundId: _roundId,
      tehnikaPick: t.id,
    );
    setState(() {
      _pick = t;
      _events = [..._events, e];
    });
    try {
      await _log.append(e);
    } catch (err) {
      debugPrint('[journal] не удалось записать ответ проверки: $err');
    }
  }

  void _next() => setState(() {
        _index++;
        _pick = null;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка недели')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(_error!));
    }
    final opened = _opened;
    if (opened == null) return const Center(child: CircularProgressIndicator());
    final answered = tehnikaCheckAnswers(_events, _now()).length;
    if (_index >= _round.length) {
      if (answered < kCheckSize && _round.isEmpty) {
        return const Center(
          child: Text('Вопросы для проверки кончились',
              key: Key('check-empty')),
        );
      }
      return _summary();
    }
    final q = _round[_index];
    return ListView(
      key: ValueKey(q.id),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Вопрос ${answered + (_pick == null ? 1 : 0)} из $kCheckSize',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        if (q.handout case final file?) ...[
          HandoutImage(file: file),
          const SizedBox(height: 12),
        ],
        if (q.handoutText case final text?) ...[
          HandoutText(text),
          const SizedBox(height: 12),
        ],
        Text(q.question, style: questionTextStyle(context)),
        const SizedBox(height: 24),
        if (_pick == null) ..._options(q, opened) else ..._reveal(q, opened),
      ],
    );
  }

  List<Widget> _options(Question q, List<Tehnika> opened) => [
        Text('Какой здесь приём?',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final t in checkOptions(q, opened))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              key: Key('check-option-${t.id}'),
              onPressed: () => _choose(t),
              child: Text(t.title),
            ),
          ),
      ];

  List<Widget> _reveal(Question q, List<Tehnika> opened) {
    final text = Theme.of(context).textTheme;
    final right = opened.where((t) => q.tehniki.contains(t.id)).toList();
    final pick = _pick!;
    final ok = right.contains(pick);
    final main = ok ? pick : right.first;
    final why = main.examples
        .where((e) => e.questionId == q.id)
        .map((e) => e.why)
        .firstOrNull;
    return [
      Text(ok ? 'Узнал' : 'Мимо',
          key: const Key('check-result'), style: text.titleLarge),
      const SizedBox(height: 12),
      Text('Приём', style: text.labelLarge),
      Text(right.map((t) => '«${t.title}»').join(', '),
          key: const Key('check-right')),
      Text(why ?? main.trigger),
      if (!ok) ...[
        const SizedBox(height: 8),
        Text('Ты выбрал: «${pick.title}»', key: const Key('check-pick')),
      ],
      const SizedBox(height: 16),
      Text('Ответ', style: text.labelLarge),
      Text(q.answer),
      if (q.comment case final c? when c.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Комментарий', style: text.labelLarge),
        Text(c),
      ],
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('check-next'),
        onPressed: _next,
        child: const Text('Дальше'),
      ),
    ];
  }

  /// Итог — по всем ответам проверки за неделю, а не по этому заходу: вышедший
  /// на середине доигрывает ту же проверку, а не начинает новую.
  Widget _summary() {
    final week = tehnikaCheckAnswers(_events, _now());
    final taken = week.where((e) => e.verdict == Verdict.taken).length;
    return ListView(
      key: const Key('check-summary'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Узнал $taken из ${week.length}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        PandaSays(key: ValueKey(_roundId), moment: PandaMoments.roundEnd),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('check-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('На главную'),
        ),
      ],
    );
  }
}
