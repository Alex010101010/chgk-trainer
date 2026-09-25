import 'package:flutter/material.dart';

/// Текстовая раздатка (T27) — листок в рамке, отдельно от текста вопроса:
/// на игре его выдают на бумаге, и читается он как предмет, а не как
/// продолжение вопроса. Переносы строк сохраняются — это стихи и шаблоны.
class HandoutText extends StatelessWidget {
  final String text;

  const HandoutText(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('cycle-handout-text'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
      );
}
