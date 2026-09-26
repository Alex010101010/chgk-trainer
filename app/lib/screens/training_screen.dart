import 'dart:math';

import 'package:flutter/material.dart';

import '../data/fact_repository.dart';
import '../data/question_repository.dart';
import '../journal/event.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../model/fact.dart';
import 'fact_deck_screen.dart';

/// Счётчики колоды в списке (T15).
class DeckStats {
  final int due;
  final int fresh;
  final int learned;
  final int total;

  const DeckStats({
    required this.due,
    required this.fresh,
    required this.learned,
    required this.total,
  });
}

DeckStats deckStats(
    List<FactCard> deck, String deckId, List<JournalEvent> events, DateTime now) {
  final states = factStates(events);
  final unseen = deck.where((c) => !states.containsKey(c.id)).length;
  final room = max(0, kNewFactsPerDay - newFactsToday(events, deckId, now));
  return DeckStats(
    due: deck.where((c) => states[c.id]?.isDue(now) ?? false).length,
    fresh: min(unseen, room),
    learned: deck.where((c) => states[c.id]?.learned ?? false).length,
    total: deck.length,
  );
}

/// «Тренировка» (T15): колоды карточек фактов. Вход — с главного экрана, но
/// одной плиткой: колод семь, и каждая на главном его бы загромоздила.
class TrainingScreen extends StatefulWidget {
  final FactRepository repository;
  final DateTime Function()? now;
  final Random? random;

  const TrainingScreen({super.key, required this.repository, this.now, this.random});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  DateTime Function() get _now => widget.now ?? DateTime.now;
  bool _started = false;

  FactBook? _book;
  List<JournalEvent> _events = const [];
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final book = await widget.repository.loadAll();
      if (!mounted) return;
      final events = (await JournalScope.of(context).readAll()).events;
      if (!mounted) return;
      setState(() {
        _book = book;
        _events = events;
      });
    } on QuestionAssetException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось открыть колоды: $e');
    }
  }

  Future<void> _open(FactDeck deck, List<FactCard> cards) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FactDeckScreen(
        deck: deck,
        cards: cards,
        now: widget.now,
        random: widget.random,
      ),
    ));
    // Счётчики после колоды другие — перечитать журнал.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Тренировка')),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : book == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final deck in book.decks)
                        if (book.cardsOf(deck.id) case final cards
                            when cards.isNotEmpty)
                          _deckTile(deck, cards),
                      const SizedBox(height: 16),
                      Text(
                        'Карточки — из таблицы фактов команды Сергея Лобачёва',
                        textAlign: TextAlign.center,
                        style: text.bodySmall,
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _deckTile(FactDeck deck, List<FactCard> cards) {
    final s = deckStats(cards, deck.id, _events, _now());
    return Card(
      child: ListTile(
        key: Key('deck-${deck.id}'),
        contentPadding: const EdgeInsets.all(16),
        title: Text(deck.title, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(
            'Повторить: ${s.due} · новых: ${s.fresh} · выучено ${s.learned} из ${s.total}'),
        onTap: () => _open(deck, cards),
      ),
    );
  }
}
