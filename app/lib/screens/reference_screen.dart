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

  /// Свои реалии: название → заметка, по алфавиту названий.
  Map<String, String> _custom = const {};
  ThemeNotes? _notes;
  String? _error;
  bool _started = false;

  /// Поиск по оглавлению: 329 строк листаются, но искать по ним глазами
  /// нельзя. Нормализация та же, что у своих реалий (T24): регистр и «ё».
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String theme) =>
      _query.isEmpty || normalizeTheme(theme).contains(_query);

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
      final themes = _corpusThemes(pool);
      setState(() {
        _themes = themes;
        _mastered = masteredThemes(events);
        _met = encounteredThemes(events);
        _custom = customThemes(themeNotes(events), themes);
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

  Future<void> _open(String theme, {bool custom = false}) async {
    Map<String, Article> articles = const {};
    String? error;
    // У своей реалии статьи нет и быть не может — ассет для неё не читаем.
    if (!custom) {
      try {
        articles = await _articles.loadAll();
      } on ArticleAssetException catch (e) {
        error = e.message;
      }
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
        custom: custom,
        notes: _notes,
      ),
    );
    // Заметку могли переписать или стереть прямо в листе, а стёртая заметка
    // снимает и саму реалию — иначе строка осталась бы висеть пустой.
    _refreshCustom();
  }

  void _refreshCustom() {
    final notes = _notes;
    final themes = _themes;
    if (notes == null || themes == null || !mounted) return;
    setState(() => _custom = customThemes(notes.all, themes));
  }

  /// Заведение своей реалии. Название и заметка обязательны оба: пустой текст
  /// по контракту T14 снимает заметку, а вместе с ней и реалию.
  Future<void> _addCustom() async {
    final notes = _notes;
    final themes = _themes;
    if (notes == null || themes == null) return;
    final corpusMatch = await showDialog<String>(
      context: context,
      builder: (_) => _CustomThemeDialog(corpus: themes, notes: notes),
    );
    _refreshCustom();
    // Ввод совпал с клише корпуса — своей не заводим, открываем корпусное.
    if (corpusMatch != null && mounted) await _open(corpusMatch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Справочник')),
      body: SafeArea(child: _body()),
      floatingActionButton: _themes == null || _error != null
          ? null
          : FloatingActionButton.extended(
              key: const Key('custom-add'),
              onPressed: _addCustom,
              icon: const Icon(Icons.add),
              label: const Text('Своя реалия'),
            ),
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

    final custom = _custom.keys.where(_matches).toList()..sort();
    final shown = themes.where(_matches).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Узнано ${_mastered.length} · встречалось ${_met.length} · '
            'всего ${themes.length}',
            key: const Key('reference-counters'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        // Свои в счётчик кампании не входят: у неё конечное дно, и своё его
        // размывало бы. Поэтому отдельной строкой и только когда они есть.
        if (custom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Своих: ${custom.length}',
              key: const Key('reference-custom-counter'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            key: const Key('reference-search'),
            controller: _search,
            onChanged: (v) => setState(() => _query = normalizeTheme(v)),
            decoration: InputDecoration(
              hintText: 'Найти клише',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('reference-search-clear'),
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
          ),
        ),
        const Divider(height: 1),
        if (custom.isEmpty && shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Ничего не нашлось', key: Key('reference-no-match')),
          ),
        Expanded(
          child: CustomScrollView(
            key: const Key('reference-list'),
            slivers: [
              // Своих единицы против трёх сотен корпусных: вперемешку по
              // алфавиту своё в списке не найти.
              if (custom.isNotEmpty) ...[
                SliverToBoxAdapter(child: _sectionTitle('Свои')),
                SliverList.builder(
                  itemCount: custom.length,
                  itemBuilder: (context, i) => _customRow(custom[i]),
                ),
                if (shown.isNotEmpty)
                  SliverToBoxAdapter(child: _sectionTitle('Все клише')),
              ],
              SliverList.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) => _row(shown[i]),
              ),
              // Место под кнопкой: без него она накрывает последнюю строку.
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );

  /// Строка своей реалии. Состояний «узнано / встречалось» у неё нет —
  /// вопросов корпуса под неё нет вовсе; вместо метки показываем заметку,
  /// ради которой реалия и заводилась.
  Widget _customRow(String theme) => ListTile(
        dense: true,
        onTap: () => _open(theme, custom: true),
        leading: Icon(Icons.bookmark_outline,
            size: 18, color: Theme.of(context).colorScheme.outline),
        title: Text(theme),
        subtitle: Text(_custom[theme] ?? '',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      );

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

/// Заведение своей реалии (T24): название и что это такое.
///
/// Подсказка совпадений из корпуса — не удобство, а защита от дубля: клише
/// в справочнике три сотни, точного написания не помнит никто, и «Ковентри»
/// завелось бы своей реалией рядом с корпусным «Ковентри».
///
/// Возвращает название корпусного клише, если ввод в него попал, — и `null`
/// во всех остальных случаях, включая удачную запись.
class _CustomThemeDialog extends StatefulWidget {
  final List<String> corpus;
  final ThemeNotes notes;

  const _CustomThemeDialog({required this.corpus, required this.notes});

  @override
  State<_CustomThemeDialog> createState() => _CustomThemeDialogState();
}

class _CustomThemeDialogState extends State<_CustomThemeDialog> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  bool _failed = false;

  /// Сколько совпадений показываем. Больше пяти — это уже список, который
  /// читают вместо того, чтобы дописать название.
  static const int _maxMatches = 5;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  List<String> get _matches {
    final q = normalizeTheme(_name.text);
    if (q.isEmpty) return const [];
    return widget.corpus
        .where((t) => normalizeTheme(t).contains(q))
        .take(_maxMatches)
        .toList();
  }

  String? get _exactCorpusMatch {
    final q = normalizeTheme(_name.text);
    for (final t in widget.corpus) {
      if (normalizeTheme(t) == q) return t;
    }
    return null;
  }

  Future<void> _save() async {
    final exact = _exactCorpusMatch;
    if (exact != null) {
      Navigator.of(context).pop(exact);
      return;
    }
    setState(() => _busy = true);
    final ok = await widget.notes.save(_name.text, _note.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final matches = _matches;
    final filled =
        _name.text.trim().isNotEmpty && _note.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Своя реалия'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('custom-name'),
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            if (matches.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Уже в справочнике:', style: text.bodySmall),
              for (final m in matches)
                TextButton(
                  key: Key('custom-match-$m'),
                  onPressed: () => Navigator.of(context).pop(m),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text(m),
                ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('custom-note'),
              controller: _note,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Что это',
                hintText: 'чем это клише обыгрывают',
              ),
            ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Не записалось — попробуй ещё раз',
                  key: const Key('custom-failed'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      // Кнопки делят строку поровну: у кнопок темы объявлена только высота,
      // то есть ширина бесконечная, и в обычном ряду диалога «Сохранить»
      // растягивается на всю строку, выдавливая «Отмену» на второй ряд.
      // `Expanded` даёт конечную ширину при любом размере шрифта.
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const Key('custom-save'),
                onPressed: filled && !_busy ? _save : null,
                child: const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
