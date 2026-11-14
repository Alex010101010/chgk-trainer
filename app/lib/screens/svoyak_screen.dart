import 'dart:math';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../cycle/screen_wakelock.dart';
import '../cycle/svoyak_controller.dart';
import '../data/svoyak_repository.dart';
import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/journal_scope.dart';
import '../model/svoyak.dart';
import '../panda/panda_voice.dart';
import '../widgets/panda_says.dart';
import '../widgets/play_surface.dart';

/// Сколько тем предлагается на выбор.
const int kSvoyakChoice = 3;

/// Темы на выбор (T6): несыгранные в случайном порядке. Сыгранная — та, на
/// любой вопрос которой есть событие: выход посреди темы её не возвращает.
/// Несыгранные кончились — добираются самые давно сыгранные.
List<SvoyakTheme> selectSvoyakThemes(
  List<SvoyakTheme> themes,
  List<JournalEvent> events, {
  int count = kSvoyakChoice,
  Random? random,
}) {
  final lastPlayed = <String, int>{};
  for (final e in events.whereType<SvoyakEvent>()) {
    lastPlayed[e.themeId] = max(lastPlayed[e.themeId] ?? 0, e.ts);
  }
  final fresh = themes.where((t) => !lastPlayed.containsKey(t.id)).toList()
    ..shuffle(random ?? Random());
  final played = themes.where((t) => lastPlayed.containsKey(t.id)).toList()
    ..sort((a, b) => lastPlayed[a.id]!.compareTo(lastPlayed[b.id]!));
  return [...fresh, ...played].take(count).toList();
}

/// «Своя игра» (T6): тема из пяти вопросов от 10 до 50, как на турнире.
/// «Знаю!» и взял — плюс номинал, нажал и не взял — минус, пас — ноль.
class SvoyakScreen extends StatefulWidget {
  final SvoyakRepository repository;
  final DateTime Function()? now;
  final Random? random;

  /// Шаг таймера контроллера: в виджет-тестах часы подменяются, а тик
  /// оставляется коротким, чтобы `pump` успевал его увидеть.
  final Duration tick;

  const SvoyakScreen({
    super.key,
    required this.repository,
    this.now,
    this.random,
    this.tick = const Duration(milliseconds: 200),
  });

  @override
  State<SvoyakScreen> createState() => _SvoyakScreenState();
}

class _SvoyakScreenState extends State<SvoyakScreen> {
  late EventLog _log;
  bool _started = false;
  String? _error;

  List<SvoyakTheme>? _all;
  List<JournalEvent> _events = const [];
  List<SvoyakTheme> _choice = const [];

  SvoyakTheme? _theme;
  String _roundId = '';
  int _index = 0;
  SvoyakController? _c;
  final List<SvoyakEvent> _results = [];

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
      final all = await widget.repository.loadAll();
      final events = (await _log.readAll()).events;
      if (!mounted) return;
      setState(() {
        _all = all;
        _events = events;
        _choice = selectSvoyakThemes(all, events, random: widget.random);
      });
    } catch (e) {
      if (mounted)
        setState(() => _error = 'Не удалось открыть «Свою игру»: $e');
    }
  }

  void _startTheme(SvoyakTheme t) {
    setState(() {
      _theme = t;
      _roundId = _now().millisecondsSinceEpoch.toString();
      _index = 0;
      _results.clear();
    });
    _startQuestion();
  }

  void _startQuestion() {
    _c?.dispose();
    final c = SvoyakController(
      item: _theme!.questions[_index],
      now: widget.now,
      tick: widget.tick,
    );
    c.addListener(() {
      // Экран держится только на отсчёте: 30 секунд без касаний —
      // ровно тот срок, после которого телефон гасит экран.
      if (c.phase == SvoyakPhase.reveal) holdScreenAwake(false);
      if (mounted) setState(() {});
    });
    setState(() => _c = c);
  }

  /// Событие пишется сразу: краш на четвёртом вопросе не имеет права стоить
  /// трёх предыдущих ответов. Двойной тап не пишет вопрос дважды.
  Future<void> _finish(SvoyakController c, {required bool taken}) async {
    if (_results.any((e) => e.questionId == c.item.question.id)) return;
    final e = SvoyakEvent.at(
      _now(),
      questionId: c.item.question.id,
      themeId: _theme!.id,
      nominal: c.item.nominal,
      buzzed: c.buzzed,
      taken: c.buzzed && taken,
      secondsUsed: c.secondsUsed,
      responseSeconds: c.responseSeconds,
      decideSec: c.decideSec,
      // Поле журнала остаётся совместимым со старыми записями.
      userAnswer: '',
      roundId: _roundId,
    );
    setState(() {
      _results.add(e);
      _events = [..._events, e];
      _index++;
    });
    try {
      await _log.append(e);
    } catch (err) {
      debugPrint('[journal] не удалось записать ответ «Своей игры»: $err');
    }
    if (_index < _theme!.questions.length) _startQuestion();
  }

  void _toChoice() {
    _c?.dispose();
    setState(() {
      _c = null;
      _theme = null;
      _choice = selectSvoyakThemes(_all!, _events, random: widget.random);
    });
  }

  @override
  void dispose() {
    holdScreenAwake(false);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Своя игра')),
      body: SafeArea(child: PlaySurface(child: _body())),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(_error!));
    }
    if (_all == null) return const Center(child: CircularProgressIndicator());
    final theme = _theme;
    if (theme == null) return _choiceList();
    if (_index >= theme.questions.length) return _summary(theme);
    return _question(theme, _c!);
  }

  Widget _choiceList() {
    final text = Theme.of(context).textTheme;
    return ListView(
      key: const Key('svoyak-choice'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Выбери тему', style: text.titleLarge),
        const SizedBox(height: 4),
        const Text(
            'Пять вопросов от 10 до 50. Прочитал — $kSvoyakDecideSec секунд на «Знаю!» '
            'или «Пас». Не взял после «Знаю!» — минус номинал.'),
        const SizedBox(height: 16),
        for (final t in _choice)
          Card(
            child: ListTile(
              key: Key('svoyak-theme-${t.id}'),
              contentPadding: const EdgeInsets.all(16),
              title: Text(t.title, style: text.titleMedium),
              subtitle: Text([t.pack, if (t.year != null) t.year].join(' · ')),
              onTap: () => _startTheme(t),
            ),
          ),
      ],
    );
  }

  int get _score => _results.fold(0, (s, e) => s + e.score);

  Widget _question(SvoyakTheme theme, SvoyakController c) {
    final text = Theme.of(context).textTheme;
    final header = switch (c.phase) {
      SvoyakPhase.reading => '',
      SvoyakPhase.deciding => 'Решай: ${c.decideRemainingSec} сек',
      SvoyakPhase.reveal => '',
    };
    return ListView(
      key: ValueKey(c.item.question.id),
      padding: const EdgeInsets.all(16),
      children: [
        Text(theme.title, style: text.titleMedium),
        Text('Счёт: ${_signed(_score)}', key: const Key('svoyak-score')),
        const SizedBox(height: 12),
        Text('${c.item.nominal}',
            key: const Key('svoyak-nominal'),
            textAlign: TextAlign.center,
            style: text.displaySmall),
        Text(header,
            key: const Key('svoyak-header'),
            textAlign: TextAlign.center,
            style: text.titleMedium),
        const SizedBox(height: 12),
        Text(c.item.question.question, style: questionTextStyle(context)),
        const SizedBox(height: 24),
        ...switch (c.phase) {
          SvoyakPhase.reading => _reading(c),
          SvoyakPhase.deciding => _decide(c),
          SvoyakPhase.reveal => _reveal(c),
        },
      ],
    );
  }

  /// Отсчёт запускает сам игрок, когда дочитал, — как «Начал» в «Классике».
  List<Widget> _reading(SvoyakController c) => [
        FilledButton(
          key: const Key('svoyak-start'),
          onPressed: () {
            holdScreenAwake(true);
            c.startDeciding();
          },
          child: const Text('Прочитал'),
        ),
      ];

  /// `Expanded` обязателен: у кнопок темы задана только высота, ширина
  /// бесконечна, и в `Row` без него вёрстка падает (грабля T3 и T24).
  List<Widget> _decide(SvoyakController c) => [
        Row(children: [
          Expanded(
            child: FilledButton(
              key: const Key('svoyak-buzz'),
              onPressed: c.buzz,
              child: const Text('Знаю!'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('svoyak-pass'),
              onPressed: c.pass,
              child: const Text('Пас'),
            ),
          ),
        ]),
      ];

  Widget _labelled(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          Text(value),
        ],
      ),
    );
  }

  List<Widget> _reveal(SvoyakController c) {
    final q = c.item.question;
    final n = c.item.nominal;
    return [
      if (c.responseSeconds != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Ответил за ${c.responseSeconds} с'),
        ),
      _labelled('Ответ', q.answer),
      _labelled('Зачёт', q.acceptance),
      _labelled('Комментарий', q.comment),
      _labelled('Источник', q.sources.join('\n')),
      _labelled('Автор', q.author),
      const SizedBox(height: 16),
      if (!c.buzzed)
        FilledButton(
          key: const Key('svoyak-next'),
          onPressed: () => _finish(c, taken: false),
          child: const Text('Дальше'),
        )
      else
        // Обе оценки равноправны: письменной версии и матчера здесь нет.
        Row(children: [
          Expanded(
            child: _verdict(
              key: const Key('svoyak-taken'),
              label: 'Взял +$n',
              onPressed: () => _finish(c, taken: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _verdict(
              key: const Key('svoyak-missed'),
              label: 'Не взял −$n',
              onPressed: () => _finish(c, taken: false),
            ),
          ),
        ]),
    ];
  }

  Widget _verdict({
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) =>
      OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
        child: Text(label, textAlign: TextAlign.center),
      );

  Widget _summary(SvoyakTheme theme) {
    final text = Theme.of(context).textTheme;
    return ListView(
      key: const Key('svoyak-summary'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(theme.title, style: text.titleMedium),
        Text('Счёт за тему: ${_signed(_score)}',
            key: const Key('svoyak-total'), style: text.headlineSmall),
        const SizedBox(height: 12),
        for (final (i, e) in _results.indexed)
          ListTile(
            dense: true,
            leading: Text('${e.nominal}', style: text.titleMedium),
            title: Text(theme.questions[i].question.answer),
            subtitle: Text(e.buzzed ? (e.taken ? 'взял' : 'не взял') : 'пас'),
            trailing: Text(_signed(e.score), style: text.titleMedium),
          ),
        const SizedBox(height: 16),
        PandaSays(key: ValueKey(_roundId), moment: PandaMoments.roundEnd),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('svoyak-again'),
          onPressed: _toChoice,
          child: const Text('Ещё тема'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('svoyak-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('На главную'),
        ),
      ],
    );
  }
}

String _signed(int n) => n > 0 ? '+$n' : (n < 0 ? '−${-n}' : '0');
