import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../model/question.dart';
import '../model/tehnika.dart';

/// Карточка урока: читается за полминуты и объясняет приём без обращения
/// к книге. Показывается при первом за неделю входе в режим и всегда доступна
/// кнопкой с главного экрана.
class TehnikaCard extends StatelessWidget {
  final Tehnika tehnika;

  /// Разобранные примеры, уже сопоставленные с вопросами корпуса. Пример,
  /// чей `questionId` не нашёлся, не показывается — молча, потому что тест
  /// сборки ассета такую опечатку и так не пропустит.
  final Map<String, Question> questions;
  final VoidCallback onDone;
  final String doneLabel;

  const TehnikaCard({
    super.key,
    required this.tehnika,
    required this.questions,
    required this.onDone,
    this.doneLabel = 'Понятно, играем',
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      key: const Key('tehnika-card'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Надзаголовок, а не дубль шапки: карточка открывается и как
        // отдельный экран, и посреди раунда — во втором случае без этой
        // строки непонятно, почему вместо вопроса урок.
        Text('Приём недели', style: _kicker(context)),
        const SizedBox(height: 6),
        Text(tehnika.title, style: text.headlineSmall),
        const SizedBox(height: 16),
        Text(tehnika.explain, style: text.bodyLarge),
        if (tehnika.trigger.isNotEmpty) ...[
          const SizedBox(height: 20),
          _triggerBlock(context),
        ],
        const SizedBox(height: 28),
        Text('Как это выглядит', style: text.titleMedium),
        const SizedBox(height: 12),
        for (final e in tehnika.examples)
          if (questions[e.questionId] case final q?) _example(context, q, e.why),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('tehnika-card-done'),
          onPressed: onDone,
          child: Text(doneLabel),
        ),
      ],
    );
  }

  /// Мелкая разрядка над заголовком — ею набраны все надписи-указатели
  /// («Приём недели», «Как заметить», «Ответ»), чтобы они читались как
  /// подписи, а не как ещё один уровень заголовков.
  TextStyle? _kicker(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );

  /// Признак приёма на сукне. Без подписи это был просто зелёный
  /// прямоугольник — непонятно, объяснение это, цитата или предупреждение.
  Widget _triggerBlock(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Как заметить',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSecondaryContainer.withValues(alpha: 0.75),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            tehnika.trigger,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
          ),
        ],
      ),
    );
  }

  /// Пример в отдельной карточке: три примера подряд сплошным текстом
  /// сливались в стену, и было не видно, где кончается один вопрос и
  /// начинается разбор следующего.
  Widget _example(BuildContext context, Question q, String why) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.question, style: questionTextStyle(context)),
            const SizedBox(height: 14),
            Text('Ответ', style: _kicker(context)),
            const SizedBox(height: 2),
            Text(q.answer, style: text.titleMedium),
            const SizedBox(height: 14),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 14),
            Text(
              why,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
