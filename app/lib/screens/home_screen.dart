import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../data/fact_repository.dart';
import '../data/question_repository.dart';
import '../data/svoyak_repository.dart';
import '../data/tehnika_repository.dart';
import '../journal/event_log.dart';
import '../journal/event.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../model/question.dart';
import '../model/tehnika.dart';
import 'classic_screen.dart';
import 'daily_screen.dart';
import 'profile_screen.dart';
import 'debug_journal_screen.dart';
import 'bingo_screen.dart';
import 'svoyak_screen.dart';
import 'tehnika_card_screen.dart';
import 'tehnika_check_screen.dart';
import 'training_screen.dart';

class _ModeInfo {
  final String title;
  final String subtitle;
  final IconData icon;
  const _ModeInfo(this.title, this.subtitle, this.icon);
}

const _modes = [
  _ModeInfo('Классика', 'Вопрос и 60 секунд', Icons.timer_outlined),
  _ModeInfo('Тренировка', 'Карточки фактов', Icons.style_outlined),
  _ModeInfo('Бинго', 'Девять тем для игры', Icons.grid_3x3),
  _ModeInfo('Своя игра', 'Пять вопросов по теме', Icons.emoji_events_outlined),
];

class HomeScreen extends StatelessWidget {
  /// Репозиторий инжектируется — это seam для виджет-тестов главного экрана:
  /// иначе они тянули бы настоящий ассет на 8.6 МБ.
  final QuestionRepository? repository;
  final TehnikaRepository? tehnikaRepository;
  final FactRepository? factRepository;
  final SvoyakRepository? svoyakRepository;

  /// Флаг «карточку урока уже показывали». Прокидывается сверху, а не
  /// создаётся здесь: иначе экран режима и экран карточки не узнают друг
  /// о друге, и урок откроется дважды подряд.
  final TehnikaCardSeen? cardSeen;

  const HomeScreen({
    super.key,
    this.repository,
    this.tehnikaRepository,
    this.factRepository,
    this.svoyakRepository,
    this.cardSeen,
  });

  Widget _screenFor(String title) => switch (title) {
        'Классика' => ClassicScreen(
            repository: repository ?? AssetQuestionRepository(),
            tehnikaRepository: tehnikaRepository,
            cardSeen: cardSeen,
          ),
        'Бинго' => BingoScreen(
            repository: repository ?? AssetQuestionRepository(),
          ),
        'Своя игра' => SvoyakScreen(
            repository: svoyakRepository ?? AssetSvoyakRepository(),
          ),
        _ => TrainingScreen(
            repository: factRepository ?? AssetFactRepository(),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF121B17)
          : colors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                        child: LayoutBuilder(builder: (context, constraints) {
                      final compact = constraints.maxWidth < 320;
                      final titleStyle = (compact
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineSmall)
                          ?.copyWith(fontWeight: FontWeight.w700);
                      Widget panda(String pose) => Image.asset(
                            'assets/panda/panda_header_$pose.png',
                            width: compact ? 40 : 48,
                            height: 56,
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                          );
                      return Row(children: [
                        panda('stance'),
                        const SizedBox(width: 2),
                        Flexible(
                          child: GestureDetector(
                            key: const Key('home-title'),
                            onLongPress: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => DebugJournalScreen(
                                        repository: repository ??
                                            AssetQuestionRepository(),
                                        tehnikaRepository: tehnikaRepository ??
                                            AssetTehnikaRepository(),
                                      )),
                            ),
                            child: Text.rich(
                              TextSpan(children: [
                                const TextSpan(text: 'Панда '),
                                TextSpan(
                                    text: 'будет?',
                                    style: TextStyle(color: colors.primary)),
                              ]),
                              textAlign: TextAlign.center,
                              style: titleStyle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        panda('dumpling'),
                      ]);
                    })),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const Key('home-profile'),
                      tooltip: 'Профиль',
                      icon: const Icon(Icons.account_circle_outlined),
                      color: colors.secondary,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ProfileScreen(
                                  repository:
                                      repository ?? AssetQuestionRepository(),
                                  tehnikaRepository: tehnikaRepository ??
                                      AssetTehnikaRepository(),
                                  factRepository:
                                      factRepository ?? AssetFactRepository(),
                                )),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _DailyCard(repository: repository ?? AssetQuestionRepository()),
                const SizedBox(height: 24),
                Text('Выбери свой формат', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, constraints) {
                  // При крупном системном тексте карточки растут по содержимому.
                  final single = constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(17) > 23;
                  Widget tile(_ModeInfo mode) => _ModeTile(
                        mode: mode,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => _screenFor(mode.title)),
                        ),
                      );
                  return Column(children: [
                    if (single)
                      for (final mode in _modes)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: tile(mode))
                    else
                      for (var i = 0; i < _modes.length; i += 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: IntrinsicHeight(
                              child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: tile(_modes[i])),
                              const SizedBox(width: 12),
                              Expanded(child: tile(_modes[i + 1])),
                            ],
                          )),
                        ),
                  ]);
                }),
                const SizedBox(height: 8),
                _TehnikaTile(
                  repository: repository ?? AssetQuestionRepository(),
                  tehnikaRepository:
                      tehnikaRepository ?? AssetTehnikaRepository(),
                  cardSeen: cardSeen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _cardColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1D3027)
        : Theme.of(context).colorScheme.surfaceContainerHighest;

class _ModeTile extends StatelessWidget {
  final _ModeInfo mode;
  final VoidCallback onTap;
  const _ModeTile({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: _cardColor(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(mode.icon, size: 30, color: theme.colorScheme.secondary),
              const SizedBox(height: 12),
              Text(mode.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(mode.subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyCard extends StatefulWidget {
  final QuestionRepository repository;
  const _DailyCard({required this.repository});

  @override
  State<_DailyCard> createState() => _DailyCardState();
}

class _DailyCardState extends State<_DailyCard> with WidgetsBindingObserver {
  EventLog? _log;
  Verdict? _verdict;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final log = context.dependOnInheritedWidgetOfExactType<JournalScope>()?.log;
    if (log == _log) return;
    _log = log;
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final events = (await _log?.readAll())?.events ?? [];
      final verdict = dailyResults(events)[localDay(DateTime.now())];
      if (mounted) setState(() => _verdict = verdict);
    } catch (e) {
      debugPrint('[home] результат вопроса дня: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = switch (_verdict) {
      Verdict.taken => 'Сегодня: взял!',
      Verdict.almost => 'Сегодня: почти',
      Verdict.missed => 'Сегодня: не взял',
      null => 'Один вопрос, одна попытка',
    };
    return Card(
      margin: EdgeInsets.zero,
      color: _cardColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ЕЖЕДНЕВНЫЙ ВЫЗОВ',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.secondary,
                )),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(17) > 23;
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Вопрос дня', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              );
              if (largeText) return copy;
              return Row(children: [
                Expanded(child: copy),
                const SizedBox(width: 8),
                Image.asset(
                  'assets/panda/panda_home_v2.png',
                  width: constraints.maxWidth * .44,
                  height: 132,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ]);
            }),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('home-daily'),
              style: FilledButton.styleFrom(
                backgroundColor: PandaPalette.gold,
                foregroundColor: PandaPalette.goldInk,
              ).copyWith(
                  backgroundBuilder: (context, states, child) =>
                      child ?? const SizedBox.shrink()),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DailyScreen(repository: widget.repository),
                ));
                if (mounted) _load();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    _verdict == null ? 'Начать →' : 'Посмотреть результат →',
                    textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка урока, открытая с главного экрана. Тот же виджет, что показывается
/// перед первым за неделю раундом, — просто с другой кнопкой выхода.
class _TehnikaCardScreen extends StatefulWidget {
  final QuestionRepository repository;
  final TehnikaRepository tehnikaRepository;
  final TehnikaCardSeen? cardSeen;

  const _TehnikaCardScreen({
    required this.repository,
    required this.tehnikaRepository,
    this.cardSeen,
  });

  @override
  State<_TehnikaCardScreen> createState() => _TehnikaCardScreenState();
}

class _TehnikaCardScreenState extends State<_TehnikaCardScreen> {
  Tehnika? _tehnika;
  Map<String, Question> _examples = const {};
  bool _repeated = false;
  ({int left, int daysLeft})? _check;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openCheck() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TehnikaCheckScreen(
        repository: widget.repository,
        tehnikaRepository: widget.tehnikaRepository,
      ),
    ));
    if (mounted) _load();
  }

  Future<void> _load() async {
    try {
      final tehniki = await widget.tehnikaRepository.loadAll();
      final pool = await widget.repository.loadAll();
      final events = (await JournalScope.of(context).readAll()).events;
      final byId = {for (final q in pool) q.id: q};
      final pick = tehnikaForWeek(tehniki, weekIndex(events, DateTime.now()));
      final t = pick.tehnika;
      if (!mounted) return;
      // Урок прочитан — перед раундом его показывать уже не нужно.
      widget.cardSeen?.value = true;
      setState(() {
        _tehnika = t;
        _repeated = pick.repeated;
        _check = checkStatus(tehniki, events, DateTime.now());
        _examples = {
          for (final e in t.examples)
            if (byId[e.questionId] case final q?) e.questionId: q,
        };
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Без заголовка: он есть в теле карточки, и две одинаковые
      // строки подряд читались как ошибка вёрстки.
      appBar: AppBar(),
      body: SafeArea(
        child: switch ((_error, _tehnika)) {
          (final String e, _) => Center(
              child:
                  Padding(padding: const EdgeInsets.all(24), child: Text(e))),
          (_, final Tehnika t) => TehnikaCard(
              tehnika: t,
              questions: _examples,
              repeated: _repeated,
              onDone: () => Navigator.of(context).pop(),
              doneLabel: 'Закрыть',
              checkLabel: switch (_check) {
                null => null,
                (left: 0, :final daysLeft) =>
                  'Проверка сыграна · следующая через $daysLeft дн.',
                (left: kCheckSize, daysLeft: _) => 'Проверка недели',
                (:final left, daysLeft: _) =>
                  'Проверка недели · осталось $left',
              },
              onCheck: (_check?.left ?? 0) > 0 ? _openCheck : null,
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

/// «Приём недели» на главном экране. Сама проверка недели (T4b) живёт внутри
/// карточки урока, чтобы не занимать главный экран, — а подпись напоминает о
/// ней, пока она не сыграна: вход, о котором нельзя догадаться, всё равно что
/// отсутствующий.
///
/// Журнал читается здесь, потому что `HomeScreen` без состояния, а подпись
/// должна обновиться после возврата с урока. Без журнала выше по дереву
/// (тесты голого главного экрана) подпись обычная.
class _TehnikaTile extends StatefulWidget {
  final QuestionRepository repository;
  final TehnikaRepository tehnikaRepository;
  final TehnikaCardSeen? cardSeen;

  const _TehnikaTile({
    required this.repository,
    required this.tehnikaRepository,
    this.cardSeen,
  });

  @override
  State<_TehnikaTile> createState() => _TehnikaTileState();
}

class _TehnikaTileState extends State<_TehnikaTile> {
  EventLog? _log;
  bool _checkWaits = false;
  String? _title;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `dependOn…`, а не `get…`: второй не подписывает, и смена журнала до
    // подписи не доходила бы.
    final log = context.dependOnInheritedWidgetOfExactType<JournalScope>()?.log;
    if (log == null || log == _log) return;
    _log = log;
    _load();
  }

  Future<void> _load() async {
    try {
      final tehniki = await widget.tehnikaRepository.loadAll();
      final events = (await _log!.readAll()).events;
      final status = checkStatus(tehniki, events, DateTime.now());
      if (!mounted) return;
      setState(() {
        _checkWaits = (status?.left ?? 0) > 0;
        _title = tehnikaForWeek(tehniki, weekIndex(events, DateTime.now()))
            .tehnika
            .title;
      });
    } catch (e) {
      debugPrint('[home] проверка недели: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: _cardColor(context),
      child: ListTile(
        key: const Key('home-tehnika'),
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(Icons.menu_book_outlined,
            size: 30, color: Theme.of(context).colorScheme.secondary),
        trailing: const Icon(Icons.chevron_right),
        title: const Text('Приём недели'),
        subtitle: Text([
          _title ?? 'Карточка урока — полминуты',
          if (_checkWaits) 'Ждёт проверка',
        ].join(' · ')),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _TehnikaCardScreen(
              repository: widget.repository,
              tehnikaRepository: widget.tehnikaRepository,
              cardSeen: widget.cardSeen,
            ),
          ));
          if (mounted && _log != null) _load();
        },
      ),
    );
  }
}
