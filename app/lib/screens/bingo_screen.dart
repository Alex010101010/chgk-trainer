import 'dart:math';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../cycle/cycle_controller.dart';
import '../cycle/question_cycle.dart';
import '../data/article_repository.dart';
import '../data/question_repository.dart';
import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../model/question.dart';
import '../panda/panda_voice.dart';
import 'reference_screen.dart';
import '../widgets/article_sheet.dart';
import '../widgets/grid_label.dart';
import '../widgets/panda_says.dart';

/// Клеток в сетке. Девять — форма 3×3 из концепта, не настройка.
const int kGridSize = 9;

/// Сколько клеток отдаётся уже освоенным темам. Остальные — неосвоенные:
/// сетка целиком из знакомого не тренирует, целиком из нового не закрывается.
const int kGridMastered = 3;

/// Вопросов в раунде и сколько из них по темам сетки. Остальные — отвлекающие
/// из gq: «ни к одной» верна в двух случаях из пяти, то есть осмысленна, но не
/// выигрышна как стратегия по умолчанию.
const int kBingoRoundSize = 5;
const int kBingoThemed = 3;

/// Темы, у которых остался непоказанный вопрос. Тема без вопроса в клетке
/// бесполезна: закрасить её будет нечем.
Set<String> _themesWithFreshQuestions(
    List<Question> pool, Set<String> seen) {
  final themes = <String>{};
  for (final q in pool) {
    if (q.corpus != Corpus.bingo || q.theme == null) continue;
    if (seen.contains(q.id)) continue;
    themes.add(q.theme!);
  }
  return themes;
}

Set<String> _seenIds(List<JournalEvent> events) =>
    events.whereType<AnswerEvent>().map((e) => e.questionId).toSet();

/// Состав новой сетки: [kGridMastered] освоенных тем и остальные неосвоенные,
/// перемешаны. Освоенных меньше трёх — добираются неосвоенными: в начале игры
/// освоенных нет вовсе, и сетка обязана собираться всё равно.
///
/// Возвращает меньше девяти тем, только если их столько не набралось во всём
/// корпусе, — решает, что с этим делать, экран.
List<String> buildGrid(
  List<Question> pool,
  List<JournalEvent> events, {
  Random? random,
}) {
  final rnd = random ?? Random();
  final available = _themesWithFreshQuestions(pool, _seenIds(events));
  final mastered = masteredThemes(events).where(available.contains).toList()
    ..shuffle(rnd);
  final fresh = available.difference(mastered.toSet()).toList()..shuffle(rnd);

  final picked = <String>[
    ...fresh.take(kGridSize - kGridMastered),
    ...mastered.take(kGridMastered),
  ];
  // Добор в обе стороны: не хватило неосвоенных — берём знакомые, и наоборот.
  for (final t in [...fresh, ...mastered]) {
    if (picked.length >= kGridSize) break;
    if (!picked.contains(t)) picked.add(t);
  }
  return picked..shuffle(rnd);
}

/// Раунд: [kBingoThemed] вопросов по разным темам из [gridThemes] и добор
/// отвлекающими из gq. Перемешивается, иначе порядок выдавал бы, какой вопрос
/// «по сетке», — и выбор клетки перестал бы быть суждением.
///
/// Две темы одной клетки в один раунд не попадают: клетка закрывается с первого
/// узнавания, второй вопрос той же темы просто пропал бы зря.
List<Question> selectBingoRound(
  List<Question> pool,
  List<JournalEvent> events,
  List<String> gridThemes, {
  int size = kBingoRoundSize,
  int themed = kBingoThemed,
  Random? random,
}) {
  final rnd = random ?? Random();
  final seen = _seenIds(events);

  final byTheme = <String, List<Question>>{};
  for (final q in pool) {
    if (q.corpus != Corpus.bingo || q.theme == null) continue;
    if (seen.contains(q.id)) continue;
    if (!gridThemes.contains(q.theme)) continue;
    byTheme.putIfAbsent(q.theme!, () => <Question>[]).add(q);
  }

  final picked = <Question>[];
  final themes = byTheme.keys.toList()..shuffle(rnd);
  for (final t in themes.take(themed)) {
    final qs = byTheme[t]!;
    picked.add(qs[rnd.nextInt(qs.length)]);
  }

  final distractors = pool
      .where((q) => q.corpus == Corpus.gq && !seen.contains(q.id))
      .toList()
    ..shuffle(rnd);
  for (final q in distractors) {
    if (picked.length >= size) break;
    picked.add(q);
  }
  return picked..shuffle(rnd);
}

/// Режим «Бинго» (T3): сетка-кампания и раунды по её темам.
///
/// Сетка живёт между раундами и перезапусками — её состав лежит в журнале
/// отдельным событием. Закрывает сетку линия из трёх; следующий раунд начинает
/// новую.
class BingoScreen extends StatefulWidget {
  final QuestionRepository repository;

  /// Справка по клише. Отдельный ассет и отдельное чтение: он нужен только
  /// когда карточку открыли, и грузить его вместе с корпусом незачем.
  final ArticleRepository? articles;
  final Random? random;
  final DateTime Function()? now;

  const BingoScreen({
    super.key,
    required this.repository,
    this.articles,
    this.random,
    this.now,
  });

  @override
  State<BingoScreen> createState() => _BingoScreenState();
}

class _BingoScreenState extends State<BingoScreen> {
  late EventLog _log;
  late final ArticleRepository _articles =
      widget.articles ?? ArticleRepository();
  DateTime Function() get _now => widget.now ?? DateTime.now;

  List<Question>? _pool;
  String? _error;

  /// Журнал держится в памяти и дополняется по ходу: закрашенность клеток
  /// считается по нему же, и перечитывать файл после каждого ответа незачем.
  List<JournalEvent> _events = [];
  int _skippedLines = 0;

  List<Question> _round = [];
  int _index = 0;
  String _roundId = '';
  final List<AnswerEvent> _results = [];

  /// Раунд идёт. Между раундами показывается сетка.
  bool _playing = false;

  /// Линия, закрытая этим раундом. Держится до ухода с итога — иначе после
  /// пересборки сетки игрок не узнал бы, что кампания вообще завершилась.
  bool _lineClosed = false;

  bool _started = false;

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
      final pool = await widget.repository.loadAll();
      final read = await _log.readAll();
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _events = List.of(read.events);
        _skippedLines = read.skippedLines;
      });
      if (currentGrid(_events) == null) await _newGrid();
    } on QuestionAssetException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось открыть режим: $e');
    }
  }

  List<String> get _grid => currentGrid(_events) ?? const [];
  List<BingoCell> get _cells => gridCells(_events);

  /// Темы незакрашенных клеток. Закрытая клетка вопросов больше не получает:
  /// закрасить её второй раз нельзя, вопрос ушёл бы впустую.
  List<String> _openThemes() {
    final grid = _grid;
    final cells = _cells;
    return [
      for (var i = 0; i < grid.length; i++)
        if (i >= cells.length || cells[i] == BingoCell.empty) grid[i],
    ];
  }

  Future<void> _newGrid() async {
    final themes = buildGrid(_pool!, _events, random: widget.random);
    if (themes.length < kGridSize) {
      // Не молча: сетка из семи клеток выглядела бы поломкой интерфейса.
      if (mounted) {
        setState(() => _error =
            'Клише кончились: тем с непоказанными вопросами осталось '
            '${themes.length} из $kGridSize');
      }
      return;
    }
    final e = BingoGridEvent.at(_now(), themes);
    try {
      await _log.append(e);
    } catch (err) {
      debugPrint('[journal] не удалось записать сетку: $err');
    }
    if (!mounted) return;
    setState(() => _events = [..._events, e]);
  }

  Future<void> _startRound() async {
    // Линия закрыта — кампания кончилась, следующий раунд играется по новой.
    if (hasLine(_cells)) await _newGrid();
    if (_error != null) return;

    var round =
        selectBingoRound(_pool!, _events, _openThemes(), random: widget.random);
    if (!round.any((q) => q.corpus == Corpus.bingo)) {
      // По открытым клеткам вопросов не осталось — сетка бесполезна.
      await _newGrid();
      if (_error != null) return;
      round = selectBingoRound(_pool!, _events, _openThemes(),
          random: widget.random);
    }
    if (!mounted) return;
    setState(() {
      _roundId = _now().millisecondsSinceEpoch.toString();
      _round = round;
      _index = 0;
      _results.clear();
      _lineClosed = false;
      _playing = true;
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
      if (_index >= _round.length) {
        _playing = false;
        _lineClosed = hasLine(_cells);
      }
    });
  }

  /// Справка по клетке. Открывается тапом по клетке между раундами: читать
  /// справочник холодно не станет никто, а через пять секунд после промаха на
  /// этом клише — станет.
  Future<void> _openArticle(String theme) async {
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
      builder: (_) =>
          ArticleSheet(theme: theme, article: articles[theme], error: error),
    );
  }

  /// Справочник открывается отсюда, а не из главного меню: оглавление клише
  /// имеет смысл рядом с кампанией, которая по нему и идёт.
  void _openReference() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReferenceScreen(
        repository: widget.repository,
        articles: _articles,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_playing && _round.isNotEmpty
            ? 'Бинго · ${_index + 1}/${_round.length}'
            : 'Бинго'),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(_error!, key: const Key('bingo-error'))),
      );
    }
    if (_pool == null || _grid.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (_skippedLines > 0) _journalWarning(),
        Expanded(child: _playing ? _current() : _board()),
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
          key: const Key('bingo-journal-warning'),
          style:
              TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        ),
      );

  Widget _current() {
    final q = _round[_index];
    return QuestionCycle(
      // Свой ключ на вопрос: без него Flutter переиспользует состояние цикла
      // и второй вопрос открывается на фазе раскрытия первого.
      key: ValueKey('${_roundId}_${q.id}'),
      question: q,
      articles: _articles,
      config: CycleConfig(
        mode: GameMode.bingo,
        roundId: _roundId,
        askBingoTap: true,
        bingoGrid: _grid,
      ),
      onFinished: _onFinished,
      now: widget.now,
    );
  }

  /// Сетка между раундами: и стартовый экран режима, и итог отыгранного раунда.
  Widget _board() {
    final filled = _cells.where((c) => c != BingoCell.empty).length;
    return ListView(
      key: const Key('bingo-board'),
      padding: const EdgeInsets.all(16),
      children: [
        if (_lineClosed) ...[
          Text('Линия! Сетка закрыта',
              key: const Key('bingo-line-closed'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Следующий раунд начнёт новую сетку',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
        ],
        BingoBoard(themes: _grid, cells: _cells, onTapTheme: _openArticle),
        const SizedBox(height: 12),
        Text('Закрыто $filled из $kGridSize',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        // Без подписи справку не найдёт никто: клетка не выглядит кнопкой.
        Text('Тап по клетке — что это за клише',
            key: const Key('bingo-article-hint'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        if (_results.isNotEmpty) ...[
          for (var i = 0; i < _results.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text('${i + 1}'),
              title: Text(_round[i].question,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text(_guessLabel(_results[i])),
            ),
          const SizedBox(height: 8),
          PandaSays(key: ValueKey(_roundId), moment: PandaMoments.roundEnd),
          const SizedBox(height: 16),
        ],
        FilledButton(
          key: const Key('bingo-start-round'),
          onPressed: _startRound,
          child: Text(_results.isEmpty ? 'Играть раунд' : 'Ещё раунд'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('bingo-reference'),
          onPressed: _openReference,
          child: const Text('Справочник клише'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('В меню'),
        ),
      ],
    );
  }

  /// Итог строки — про клетку, а не про вопрос: режим тренирует узнавание
  /// клише, и «взял вопрос» здесь второстепенно.
  static String _guessLabel(AnswerEvent e) {
    if (e.theme == null) {
      return e.themeGuess == null || e.themeGuess == kThemeGuessNone
          ? 'мимо сетки'
          : 'не то клише';
    }
    if (e.themeGuess == e.theme) {
      return e.verdict == Verdict.taken ? 'золотая' : 'клетка';
    }
    return e.themeGuess == kThemeGuessNone ? 'пропустил' : 'не та клетка';
  }
}

/// Сетка 3×3 с состояниями клеток. Отдельный виджет: её показывает и экран
/// режима, и справочник (T14).
class BingoBoard extends StatelessWidget {
  final List<String> themes;
  final List<BingoCell> cells;

  /// Тап по клетке. Null — сетка только показывается (итог раунда в цикле).
  final void Function(String theme)? onTapTheme;

  const BingoBoard({
    super.key,
    required this.themes,
    required this.cells,
    this.onTapTheme,
  });

  static const double _spacing = 8;
  static const double _padding = 5;
  static const double _border = 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
    return LayoutBuilder(builder: (context, constraints) {
      // Клетка квадратная: приплюснутая давала на строку меньше, а длинное
      // название попадает в сетку из девяти случайных тем в половине случаев.
      final side = (constraints.maxWidth - _spacing * 2) / 3;
      // Рамка тоже съедает ширину: без неё расчёт обещал клетке на два
      // пикселя больше, чем есть, и слово рвалось по буквам.
      final inner = side - (_padding + _border) * 2;
      final label = gridLabelStyle(
        context,
        labels: themes,
        style: base,
        maxWidth: inner,
        maxHeight: inner,
      );
      return GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: _spacing,
        crossAxisSpacing: _spacing,
        childAspectRatio: 1,
        children: [
          for (var i = 0; i < themes.length; i++)
            _cell(context, scheme, base.copyWith(fontSize: label.fontSize),
                label.maxLines, themes[i],
                i < cells.length ? cells[i] : BingoCell.empty),
        ],
      );
    });
  }

  Widget _cell(BuildContext context, ColorScheme scheme, TextStyle style,
      int maxLines, String theme, BingoCell state) {
    // Закрытая клетка держит цвет: узнал клише — сукно, узнал и взял вопрос —
    // золото. Пустая живёт контуром, чтобы сетка читалась как сетка.
    final (Color bg, Color fg) = switch (state) {
      BingoCell.empty => (Colors.transparent, scheme.onSurfaceVariant),
      BingoCell.filled => (PandaPalette.cloth, PandaPalette.paperDim),
      BingoCell.golden => (PandaPalette.gold, PandaPalette.goldInk),
    };
    final radius = BorderRadius.circular(10);
    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        onTap: onTapTheme == null ? null : () => onTapTheme!(theme),
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(_padding),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: scheme.outlineVariant, width: _border),
          ),
          alignment: Alignment.center,
          child: Text(
            theme,
            textAlign: TextAlign.center,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}
