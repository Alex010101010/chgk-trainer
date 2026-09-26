import 'dart:math';

import 'package:flutter/material.dart';

import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../model/fact.dart';
import '../widgets/handout_image.dart';

/// Карточки колоды на сегодня (T15): сначала те, которым пора вернуться, потом
/// новые — сколько осталось от дневного лимита колоды. Внутри каждой группы
/// порядок случайный: в таблице похожие стоят подряд («Отец русской авиации»,
/// «Отец русского радио»), и соседняя подсказывала бы ответ.
List<FactCard> selectFactSession(
  List<FactCard> deck,
  String deckId,
  List<JournalEvent> events,
  DateTime now, {
  Random? random,
}) {
  final rnd = random ?? Random();
  final states = factStates(events);
  final due = [
    for (final c in deck)
      if (states[c.id]?.isDue(now) ?? false) c,
  ]..shuffle(rnd);
  final fresh = [
    for (final c in deck)
      if (!states.containsKey(c.id)) c,
  ]..shuffle(rnd);
  final room = max(0, kNewFactsPerDay - newFactsToday(events, deckId, now));
  return [...due, ...fresh.take(room)];
}

class FactDeckScreen extends StatefulWidget {
  final FactDeck deck;
  final List<FactCard> cards;
  final DateTime Function()? now;
  final Random? random;

  const FactDeckScreen({
    super.key,
    required this.deck,
    required this.cards,
    this.now,
    this.random,
  });

  @override
  State<FactDeckScreen> createState() => _FactDeckScreenState();
}

class _FactDeckScreenState extends State<FactDeckScreen> {
  late EventLog _log;
  DateTime Function() get _now => widget.now ?? DateTime.now;
  bool _started = false;

  List<FactCard>? _session;
  int _index = 0;
  bool _revealed = false;
  int _known = 0;
  String? _error;

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
      final events = (await _log.readAll()).events;
      if (!mounted) return;
      setState(() => _session = selectFactSession(
          widget.cards, widget.deck.id, events, _now(),
          random: widget.random));
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось открыть колоду: $e');
    }
  }

  /// Событие пишется сразу по ответу: выход на середине колоды не должен
  /// стоить уже отвеченных карточек.
  Future<void> _answer(bool known) async {
    final card = _session![_index];
    setState(() {
      if (known) _known++;
      _index++;
      _revealed = false;
    });
    try {
      await _log.append(
          FactEvent.at(_now(), cardId: card.id, deck: card.deck, known: known));
    } catch (err) {
      debugPrint('[journal] не удалось записать ответ на карточку: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deck.title),
        actions: [
          if (session != null && _index < session.length)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${_index + 1} / ${session.length}',
                    key: const Key('fact-progress')),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : session == null
                ? const Center(child: CircularProgressIndicator())
                : session.isEmpty
                    ? _done(
                        'В этой колоде на сегодня всё',
                        'Повторять пока нечего, а новые карточки на сегодня '
                            'уже открыты. Приходи завтра.')
                    : _index >= session.length
                        ? _done(
                            'На сегодня всё',
                            'Знал $_known из ${session.length}. '
                                'Карточки, которых не знал, вернутся завтра.')
                        : _card(session[_index]),
      ),
    );
  }

  Widget _card(FactCard card) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return ListView(
      key: ValueKey(card.id),
      padding: const EdgeInsets.all(16),
      children: [
        Text(card.ask,
            style: text.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Text(card.front, key: const Key('fact-front'), style: text.headlineSmall),
        if (card.image != null) ...[
          const SizedBox(height: 16),
          HandoutImage(file: card.image!),
        ],
        const SizedBox(height: 24),
        if (!_revealed)
          FilledButton(
            key: const Key('fact-reveal'),
            onPressed: () => setState(() => _revealed = true),
            child: const Text('Показать'),
          )
        else ...[
          const Divider(),
          const SizedBox(height: 8),
          Text(card.back, key: const Key('fact-back'), style: text.headlineSmall),
          if (card.note != null) ...[
            const SizedBox(height: 12),
            Text(card.note!, style: text.bodyMedium),
          ],
          const SizedBox(height: 24),
          // Кнопки темы задают только высоту, ширина у них бесконечная —
          // в ряду без Expanded вёрстка падает (грабля T3/T24).
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('fact-missed'),
                  onPressed: () => _answer(false),
                  child: const Text('Не знал'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('fact-known'),
                  onPressed: () => _answer(true),
                  child: const Text('Знал'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _done(String title, String body) {
    final text = Theme.of(context).textTheme;
    return ListView(
      key: const Key('fact-done'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(body),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('К колодам'),
        ),
      ],
    );
  }
}
