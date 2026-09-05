import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/article_repository.dart';
import '../data/question_repository.dart';
import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../journal/theme_notes.dart';
import '../model/question.dart';
import '../widgets/article_sheet.dart';

/// Что игрок знает о клише. Три состояния, а не два: «встречалось, но не
/// узнал» — самое рабочее место справочника, и сливать его с «не встречалось»
/// значит прятать ровно тот список, который стоит читать.
enum ThemeState { mastered, met, unmet }

/// Справочник клише (T14, точка входа 3): оглавление корпуса и одновременно
/// карта кампании — сколько клише узнано из всех, что могут попасться.
///
/// Открывается с экрана «Бинго», а не из главного меню: справочник — награда
/// за игру, холодное чтение оглавления не делает никто.
class ReferenceScreen extends StatefulWidget {
  final QuestionRepository repository;
  final ArticleRepository? articles;
  final DateTime Function()? now;

  const ReferenceScreen({
    super.key,
    required this.repository,
    this.articles,
    this.now,
  });

  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends State<ReferenceScreen> {
  late final ArticleRepository _articles =
      widget.articles ?? ArticleRepository();

  List<String>? _themes;
  Set<String> _mastered = const {};
  Set<String> _met = const {};
  ThemeNotes? _notes;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(JournalScope.of(context));
  }

  Future<void> _load(EventLog log) async {
    try {
      final pool = await widget.repository.loadAll();
      final read = await log.readAll();
      final events = read.events;
      if (!mounted) return;
      setState(() {
        _themes = _corpusThemes(pool);
        _mastered = masteredThemes(events);
        _met = encounteredThemes(events);
        _notes = ThemeNotes(log: log, events: events, now: widget.now);
      });
    } on QuestionAssetException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось открыть справочник: $e');
    }
  }

  /// Все клише корпуса по алфавиту. Это оглавление: список того, что может
  /// попасться, а не того, что уже попадалось.
  static List<String> _corpusThemes(List<Question> pool) {
    final themes = <String>{
      for (final q in pool)
        if (q.corpus == Corpus.bingo && q.theme != null) q.theme!,
    }.toList()
      ..sort();
    return themes;
  }

  ThemeState _stateOf(String theme) {
    if (_mastered.contains(theme)) return ThemeState.mastered;
    if (_met.contains(theme)) return ThemeState.met;
    return ThemeState.unmet;
  }

  Future<void> _open(String theme) async {
    Map<String, Article> articles = const {};
    String? error;
    try {
      articles = await _articles.loadAll();
    } on ArticleAssetException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ArticleSheet(
        theme: theme,
        article: articles[theme],
        error: error,
        notes: _notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Справочник')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(_error!, key: const Key('reference-error'))),
      );
    }
    final themes = _themes;
    if (themes == null) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            'Узнано ${_mastered.length} · встречалось ${_met.length} · '
            'всего ${themes.length}',
            key: const Key('reference-counters'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            key: const Key('reference-list'),
            itemCount: themes.length,
            itemBuilder: (context, i) => _row(themes[i]),
          ),
        ),
      ],
    );
  }

  Widget _row(String theme) {
    final state = _stateOf(theme);
    // Те же цвета, что у клеток сетки: узнанное клише выглядит одинаково
    // и в кампании, и в оглавлении.
    final (Color color, String label) = switch (state) {
      ThemeState.mastered => (PandaPalette.gold, 'узнано'),
      ThemeState.met => (PandaPalette.clothLight, 'встречалось'),
      ThemeState.unmet => (Colors.transparent, 'не встречалось'),
    };
    return ListTile(
      dense: true,
      onTap: () => _open(theme),
      leading: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      title: Text(theme),
      subtitle: Text(label),
    );
  }
}
