import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../journal/event.dart';
import '../model/question.dart';
import '../model/tehnika.dart';
import '../panda/panda_voice.dart';
import '../widgets/grid_label.dart';
import '../widgets/handout_image.dart';
import '../widgets/panda_says.dart';
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
  final DateTime Function()? now;

  const QuestionCycle({
    super.key,
    required this.question,
    required this.config,
    required this.onFinished,
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
        CyclePhase.verdict => _verdict(),
        CyclePhase.reason => _reason(),
        CyclePhase.tehnika => _tehnika(),
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
        Text(
          widget.question.question,
          style: questionTextStyle(context),
        ),
      ],
    );
  }

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
        _labelled('Ответ', q.answer),
        _labelled('Зачёт', q.acceptance),
        _labelled('Комментарий', q.comment),
        _labelled('Источник', q.sources.join('\n')),
        _labelled('Автор', q.author),
        _labelled('Твоя версия', _c.userAnswer.isEmpty ? '—' : _c.userAnswer),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('cycle-to-verdict'),
          onPressed: _c.toVerdict,
          child: const Text('Оценить'),
        ),
      ],
    );
  }

  Widget _verdict() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Взял?'),
          const SizedBox(height: 8),
          SegmentedButton<Verdict>(
            segments: const [
              ButtonSegment(value: Verdict.taken, label: Text('Взял')),
              ButtonSegment(value: Verdict.almost, label: Text('Почти')),
              ButtonSegment(value: Verdict.missed, label: Text('Не взял')),
            ],
            // Пустой набор — матчер не сработал, не предвыбрано ничего.
            selected: _c.verdict == null ? const {} : {_c.verdict!},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) => _c.setVerdict(s.first),
          ),
          // Панда комментирует самооценку, а не эталон: она реагирует на то,
          // что игрок сам про себя решил. Key по вердикту — чтобы при смене
          // оценки реплика бралась заново, а не досталась от прошлой.
          if (_c.verdict case final v?) ...[
            const SizedBox(height: 16),
            PandaSays(key: ValueKey(v), moment: _momentFor(v)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('cycle-verdict-done'),
            onPressed: _c.verdict == null ? null : _c.confirmVerdict,
            child: const Text('Дальше'),
          ),
        ],
      );

  static String _momentFor(Verdict v) => switch (v) {
        Verdict.taken => PandaMoments.took,
        Verdict.almost => PandaMoments.almost,
        Verdict.missed => PandaMoments.missed,
      };

  static const _reasonLabels = {
    MissReason.fact: 'Не знал факт',
    MissReason.link: 'Не увидел связку',
    MissReason.tehnika: 'Не узнал приём',
    MissReason.time: 'Не хватило времени',
  };

  Widget _reason() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Что помешало?'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final e in _reasonLabels.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _c.reason == e.key,
                  onSelected: (_) => _c.setReason(e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Пропуск разрешён: обязательность провоцирует жать первое попавшееся.
          FilledButton(
            key: const Key('cycle-reason-done'),
            onPressed: _c.confirmReason,
            child: Text(_c.reason == null ? 'Пропустить' : 'Дальше'),
          ),
        ],
      );

  Widget _tehnika() {
    final t = widget.config.tehnika!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Здесь был приём «${t.title}»?'),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Да')),
            ButtonSegment(value: false, label: Text('Нет')),
          ],
          selected: _c.tehnikaGuess == null ? const {} : {_c.tehnikaGuess!},
          emptySelectionAllowed: true,
          // Пока не нажато «Ответить», решение можно переменить.
          onSelectionChanged:
              _c.tehnikaAnswered ? null : (s) => _c.setTehnikaGuess(s.first),
        ),
        if (_c.tehnikaAnswered) ...[
          const SizedBox(height: 16),
          _tehnikaFeedback(t),
        ],
        const SizedBox(height: 16),
        if (!_c.tehnikaAnswered)
          FilledButton(
            key: const Key('cycle-tehnika-answer'),
            onPressed: _c.tehnikaGuess == null ? null : _c.revealTehnika,
            child: const Text('Ответить'),
          )
        else
          FilledButton(
            key: const Key('cycle-tehnika-done'),
            onPressed: _c.confirmTehnika,
            child: const Text('Дальше'),
          ),
      ],
    );
  }

  /// Вердикт — только там, где эталон говорит «да». На остальных вопросах
  /// честное «записал»: эталона нет, и притворяться, что он есть, нельзя.
  Widget _tehnikaFeedback(Tehnika t) {
    if (!_c.tehnikaVerdictKnown) {
      return const Text('Записал.', key: Key('cycle-tehnika-noted'));
    }
    final right = _c.tehnikaGuessedRight;
    final why = t.examples
        .where((e) => e.questionId == widget.question.id)
        .map((e) => e.why)
        .firstOrNull;
    return Column(
      key: const Key('cycle-tehnika-verdict'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(right ? 'Да, приём здесь был.' : 'Приём здесь был — пропустил.',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(why ?? t.trigger),
      ],
    );
  }
}
