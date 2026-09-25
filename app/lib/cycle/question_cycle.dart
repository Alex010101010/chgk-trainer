import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../journal/event.dart';
import '../journal/theme_notes.dart';
import '../model/question.dart';
import '../data/article_repository.dart';
import '../model/tehnika.dart';
import '../widgets/article_card.dart';
import '../widgets/grid_label.dart';
import '../widgets/handout_image.dart';
import 'cycle_controller.dart';
import 'screen_wakelock.dart';

/// Один вопрос по турнирной конвенции. Режимо-специфичного здесь нет ничего:
/// T3 и T4b получают этот же виджет с другой [CycleConfig].
///
/// Собранное событие уезжает в [onFinished] — пишет его в журнал режим.
class QuestionCycle extends StatefulWidget {
  final Question question;
  final CycleConfig config;
  final void Function(AnswerEvent) onFinished;

  /// Справка по клише (T14). `null` — карточки под ответом не будет: у режима
  /// без бинго-корпуса раскрывать нечего, у вопроса без темы — тем более.
  final ArticleRepository? articles;

  /// Заметки на клише (T14). В журнал пишет их этот объект, а не цикл: цикл
  /// по-прежнему только собирает событие ответа и отдаёт его режиму.
  final ThemeNotes? notes;
  final DateTime Function()? now;

  const QuestionCycle({
    super.key,
    required this.question,
    required this.config,
    required this.onFinished,
    this.articles,
    this.notes,
    this.now,
  });

  @override
  State<QuestionCycle> createState() => _QuestionCycleState();
}

class _QuestionCycleState extends State<QuestionCycle> {
  late final CycleController _c;
  final _answerField = TextEditingController();
  final _bingoField = TextEditingController();
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _c = CycleController(
      question: widget.question,
      config: widget.config,
      now: widget.now,
    )..addListener(_onPhase);
  }

  void _onPhase() {
    if (!_finished && _c.phase == CyclePhase.done) {
      _finished = true;
      holdScreenAwake(false);
      widget.onFinished(_c.buildEvent());
    }
    setState(() {});
  }

  @override
  void dispose() {
    holdScreenAwake(false);
    _c.removeListener(_onPhase);
    _c.dispose();
    _answerField.dispose();
    _bingoField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 12),
          Expanded(child: SingleChildScrollView(child: _phaseBody())),
        ],
      ),
    );
  }

  Widget _header() {
    final text = switch (_c.phase) {
      CyclePhase.thinking => 'Осталось ${kThinkingSec - _c.secondsUsed} сек',
      CyclePhase.writing => _c.writingClosed
          ? 'Время записи вышло'
          : 'Запись: ${_c.writingRemainingSec} сек',
      _ => '',
    };
    return Text(
      text,
      key: const Key('cycle-header'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }

  Widget _phaseBody() => switch (_c.phase) {
        CyclePhase.reading => _reading(),
        CyclePhase.thinking => _thinking(),
        CyclePhase.writing => _writing(),
        CyclePhase.bingoTap => _bingoTap(),
        CyclePhase.reveal => _reveal(),
        CyclePhase.done => const SizedBox.shrink(),
      };

  /// Текст вопроса и раздатка над ним. Раздатку выдают до вопроса и не
  /// отбирают: она видна на чтении, минуте, записи и раскрытии — всюду, где
  /// показан сам вопрос.
  Widget _questionText() {
    final handout = widget.question.handout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (handout != null) ...[
          HandoutImage(file: handout),
          const SizedBox(height: 12),
        ],
        if (widget.question.handoutText case final text?) ...[
          _handoutText(text),
          const SizedBox(height: 12),
        ],
        Text(
          widget.question.question,
          style: questionTextStyle(context),
        ),
      ],
    );
  }

  /// Текстовая раздатка (T27) — листок в рамке, отдельно от текста вопроса:
  /// на игре его выдают на бумаге, и читается он как предмет, а не как
  /// продолжение вопроса. Переносы строк сохраняются — это стихи и шаблоны.
  Widget _handoutText(String text) => Container(
        key: const Key('cycle-handout-text'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
      );

  Widget _reading() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _questionText(),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('cycle-start'),
            onPressed: () {
              holdScreenAwake(true);
              _c.startThinking();
            },
            child: const Text('Начал'),
          ),
        ],
      );

  Widget _thinking() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _questionText(),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('cycle-ready'),
            onPressed: _c.readyToAnswer,
            child: const Text('Готов отвечать'),
          ),
        ],
      );

  Widget _writing() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _questionText(),
          const SizedBox(height: 16),
          TextField(
            key: const Key('cycle-answer-field'),
            controller: _answerField,
            enabled: !_c.writingClosed,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Ответ'),
            onChanged: _c.setUserAnswer,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('cycle-answer-done'),
            onPressed: _c.finishWriting,
            child: const Text('Дальше'),
          ),
        ],
      );

  /// Спрашивается ДО раскрытия: после него догадка перестаёт быть догадкой.
  Widget _bingoTap() {
    final grid = widget.config.bingoGrid;
    return grid == null ? _bingoOpenInput() : _bingoGrid(grid);
  }

  Widget _bingoOpenInput() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Узнал клише? Назови'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('cycle-bingo-field'),
            controller: _bingoField,
            decoration: const InputDecoration(hintText: 'название клише'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('cycle-bingo-done'),
            onPressed: () {
              final t = _bingoField.text.trim();
              // Пустой ввод — «не спрашивали», а не «ни к одной»: девяти
              // вариантов здесь не показывали, отрицать нечего.
              _c.submitBingoTap(t.isEmpty ? null : t);
            },
            child: const Text('Дальше'),
          ),
        ],
      );

  /// Девять клеток (T3). Показываются только здесь: во время минуты они были бы
  /// девятью подсказками, и узнавание клише подменилось бы перебором.
  Widget _bingoGrid(List<String> grid) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('К какой клетке?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            const spacing = 8.0;
            // Клетки шире, чем высокие: квадратные заняли бы всю высоту экрана,
            // и «ни к одной» оказалась бы за краем — то есть невидимой.
            const aspect = 1.6;
            // Родные отступы кнопки съедали половину ширины клетки — на них
            // обрезалось даже то, что по кеглю влезало.
            const padding = EdgeInsets.all(8);
            final side = (constraints.maxWidth - spacing * 2) / 3;
            final style =
                Theme.of(context).textTheme.bodySmall ?? const TextStyle();
            final label = gridLabelStyle(
              context,
              labels: grid,
              style: style,
              // Плюс рамка кнопки, по пикселю с каждой стороны.
              maxWidth: side - padding.horizontal - 2,
              maxHeight: side / aspect - padding.vertical - 2,
            );
            return GridView.count(
              key: const Key('cycle-bingo-grid'),
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: aspect,
              children: [
                for (final theme in grid)
                  OutlinedButton(
                    onPressed: () => _c.submitBingoTap(theme),
                    style: OutlinedButton.styleFrom(padding: padding),
                    child: Text(
                      theme,
                      textAlign: TextAlign.center,
                      maxLines: label.maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(fontSize: label.fontSize),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('cycle-bingo-none'),
            onPressed: () => _c.submitBingoTap(kThemeGuessNone),
            child: const Text('Ни к одной'),
          ),
        ],
      );

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

  Widget _reveal() {
    final q = widget.question;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Раздатка остаётся и на разборе: комментарий часто объясняет именно
        // то, что на картинке, и без неё читается как ребус.
        if (q.handout case final file?) ...[
          HandoutImage(file: file),
          const SizedBox(height: 12),
        ],
        if (q.handoutText case final text?) ...[
          _handoutText(text),
          const SizedBox(height: 12),
        ],
        _labelled('Ответ', q.answer),
        _labelled('Зачёт', q.acceptance),
        // Клише — сразу под ответом, до комментария: комментарий объясняет
        // этот вопрос, а клише — все остальные вопросы того же рода.
        if (widget.articles case final repo?)
          if (q.theme case final theme?)
            ArticleCard(theme: theme, repository: repo, notes: widget.notes),
        _labelled('Комментарий', q.comment),
        _labelled('Источник', q.sources.join('\n')),
        _labelled('Автор', q.author),
        _labelled('Твоя версия', _c.userAnswer.isEmpty ? '—' : _c.userAnswer),
        if (widget.config.tehnika case final t?) _tehnikaHint(t),
        const SizedBox(height: 16),
        _verdictButtons(),
      ],
    );
  }

  /// Приём недели, который эталон точно нашёл в этом вопросе. Не вопрос, а
  /// строка: увидеть приём в живом вопросе — цель, угадывать его здесь — нет,
  /// угадывание живёт в воскресном разборе (T4b).
  Widget _tehnikaHint(Tehnika t) {
    final why = t.examples
        .where((e) => e.questionId == widget.question.id)
        .map((e) => e.why)
        .firstOrNull;
    return Padding(
      key: const Key('cycle-tehnika-hint'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Здесь был приём недели: «${t.title}»',
              style: Theme.of(context).textTheme.labelLarge),
          Text(why ?? t.trigger),
        ],
      ),
    );
  }

  static const _verdictLabels = {
    Verdict.taken: 'Взял',
    Verdict.almost: 'Почти',
    Verdict.missed: 'Не взял',
  };

  /// Самооценка в одно нажатие — оно же закрывает вопрос. Подсказка матчера
  /// выделена заливкой, но не выбрана за игрока.
  ///
  /// `Expanded` обязателен: у кнопок темы задана только высота, ширина
  /// бесконечна, и в `Row` без него вёрстка падает (грабля из T3 и T24).
  /// Боковой отступ ужат: треть ширины телефона минус штатные 24+24 — это
  /// ~56 точек, и «Не взял» переносилось на вторую строку.
  static const _verdictPadding = EdgeInsets.symmetric(horizontal: 8);

  Widget _verdictButtons() => Row(
        children: [
          for (final (i, e) in _verdictLabels.entries.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: e.key == _c.verdict
                  ? FilledButton(
                      key: Key('cycle-verdict-${e.key.name}'),
                      style: FilledButton.styleFrom(padding: _verdictPadding),
                      onPressed: () => _c.finish(e.key),
                      child: Text(e.value),
                    )
                  : OutlinedButton(
                      key: Key('cycle-verdict-${e.key.name}'),
                      style: OutlinedButton.styleFrom(padding: _verdictPadding),
                      onPressed: () => _c.finish(e.key),
                      child: Text(e.value),
                    ),
            ),
          ],
        ],
      );
}
