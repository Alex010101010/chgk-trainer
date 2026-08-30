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
      padding: const EdgeInsets.all(16),
      children: [
        Text('Приём недели', style: text.labelLarge),
        const SizedBox(height: 4),
        Text(tehnika.title, style: text.headlineSmall),
        const SizedBox(height: 12),
        Text(tehnika.explain, style: const TextStyle(height: 1.4)),
        if (tehnika.trigger.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(tehnika.trigger),
          ),
        ],
        const SizedBox(height: 20),
        Text('Как это выглядит', style: text.titleMedium),
        const SizedBox(height: 8),
        for (final e in tehnika.examples)
          if (questions[e.questionId] case final q?) _example(context, q, e.why),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('tehnika-card-done'),
          onPressed: onDone,
          child: Text(doneLabel),
        ),
      ],
    );
  }

  Widget _example(BuildContext context, Question q, String why) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.question, style: questionTextStyle(context)),
            const SizedBox(height: 4),
            Text('Ответ: ${q.answer}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(why,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}
