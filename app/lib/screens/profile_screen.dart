import 'package:flutter/material.dart';

import '../data/fact_repository.dart';
import '../data/question_repository.dart';
import '../data/tehnika_repository.dart';
import '../journal/event.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../model/fact.dart';
import '../model/question.dart';
import '../model/tehnika.dart';
import '../panda/panda_voice.dart';
import '../widgets/panda_says.dart';
import 'tehnika_check_screen.dart';

/// Профиль (T9): сводка сверху и по блоку на ось — клише, приёмы, факты.
/// Всё — свёртки журнала, своего хранилища у профиля нет.
///
/// Журнал читается быстро, корпус вопросов — почти секунду. Поэтому сводка
/// показывается сразу, а блоки, которым нужны ассеты, догружаются: ждать
/// восемь мегабайт ради серии дней незачем.
class ProfileScreen extends StatefulWidget {
  final QuestionRepository repository;
  final TehnikaRepository tehnikaRepository;
  final FactRepository factRepository;
  final DateTime Function()? now;

  const ProfileScreen({
    super.key,
    required this.repository,
    required this.tehnikaRepository,
    required this.factRepository,
    this.now,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _started = false;
  List<JournalEvent>? _events;
  String? _error;

  // Ассеты. `null` — ещё грузятся.
  List<Question>? _questions;
  List<Tehnika>? _tehniki;
  FactBook? _facts;
  String? _assetError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final events = (await JournalScope.of(context).readAll()).events;
      if (!mounted) return;
      setState(() => _events = events);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось прочитать журнал: $e');
      return;
    }
    try {
      final questions = await widget.repository.loadAll();
      final tehniki = await widget.tehnikaRepository.loadAll();
      final facts = await widget.factRepository.loadAll();
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _tehniki = tehniki;
        _facts = facts;
      });
    } on QuestionAssetException catch (e) {
      if (mounted) setState(() => _assetError = e.message);
    } catch (e) {
      if (mounted) setState(() => _assetError = 'Не удалось загрузить данные: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : events == null
                ? const Center(child: CircularProgressIndicator())
                : _body(events),
      ),
    );
  }

  Widget _body(List<JournalEvent> events) {
    final now = (widget.now ?? DateTime.now)();
    final streak = currentStreak(events, now);
    final rate = takenRate(events, window: 50);
    final questions = _questions;
    final tehniki = _tehniki;
    final facts = _facts;
    final ready = questions != null && tehniki != null && facts != null;

    final opened = ready ? openedTehniki(tehniki, weekIndex(events, now)) : const <Tehnika>[];
    final states = ready
        ? tehnikaStates(
            events,
            {for (final q in questions) if (q.tehniki.isNotEmpty) q.id: q.tehniki},
            opened.map((t) => t.id),
          )
        : const <String, TehnikaState>{};
    List<Tehnika> inState(TehnikaState s) =>
        opened.where((t) => states[t.id] == s).toList();
    final weak = inState(TehnikaState.weak);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _block('Сводка', [
          _row('Дней подряд', '$streak', key: const Key('profile-streak')),
          _row('Вопросов сыграно', '${answeredCount(events)}',
              key: const Key('profile-answered')),
          _row('Доля «взял» (посл. 50)',
              rate == null ? '—' : '${(rate * 100).round()}%',
              key: const Key('profile-rate')),
        ]),
        if (!ready)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _assetError != null
                  ? Text(_assetError!)
                  : const CircularProgressIndicator(),
            ),
          )
        else ...[
          _clicheBlock(events, questions),
          _tehnikaBlock(opened, inState(TehnikaState.mastered).length, weak,
              inState(TehnikaState.unchecked)),
          _block('Факты', [
            _row('Выучено карточек',
                '${learnedFacts(events)} из ${facts.cards.length}',
                key: const Key('profile-facts')),
          ]),
          const SizedBox(height: 8),
          // Одна панда на экран: две позы подряд спорят за внимание. Слабое
          // место важнее серии — серия на профиле почти всегда жива, раз
          // приложение сегодня открыто.
          weak.isNotEmpty
              ? PandaSays(
                  moment: PandaMoments.weakmap,
                  vars: {'приём': weak.first.title},
                )
              : PandaSays(
                  moment: streak > 0
                      ? PandaMoments.streakAlive
                      : PandaMoments.streakBroken,
                  vars: {if (streak > 0) 'n': '$streak'},
                ),
        ],
      ],
    );
  }

  Widget _clicheBlock(List<JournalEvent> events, List<Question> questions) {
    final themes = corpusThemes(questions);
    final mastered = masteredThemes(events).where(themes.contains).length;
    final custom = customThemes(themeNotes(events), themes).length;
    return _block('Клише', [
      _row('Узнано в сетке', '$mastered из ${themes.length}',
          key: const Key('profile-mastered')),
      // Своя реалия — клише, пойманное на живой игре и записанное (T24).
      _row('Своих реалий записано', '$custom', key: const Key('profile-custom')),
    ]);
  }

  Widget _tehnikaBlock(List<Tehnika> opened, int mastered, List<Tehnika> weak,
      List<Tehnika> unchecked) {
    final text = Theme.of(context).textTheme;
    return _block('Приёмы', [
      _row('Освоено', '$mastered из ${opened.length} открытых',
          key: const Key('profile-tehniki')),
      if (weak.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Слабые места', style: text.titleSmall),
        for (final t in weak) Text(t.title, key: Key('profile-weak-${t.id}')),
      ],
      if (unchecked.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Ещё не было в проверке недели', style: text.titleSmall),
        for (final t in unchecked)
          Text(t.title, key: Key('profile-unchecked-${t.id}')),
      ],
    ]);
  }

  Widget _block(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  Widget _row(String label, String value, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
