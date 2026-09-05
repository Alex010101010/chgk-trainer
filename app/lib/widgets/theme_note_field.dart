import 'package:flutter/material.dart';

import '../journal/theme_notes.dart';

/// Своя заметка на клише (T14): место, куда пишешь понятое после промаха.
///
/// Одно поле и кнопка. Кнопка активна только когда текст изменился — иначе
/// «Сохранить» на нетронутой заметке выглядит как несохранённая работа.
class ThemeNoteField extends StatefulWidget {
  final String theme;
  final ThemeNotes notes;

  const ThemeNoteField({super.key, required this.theme, required this.notes});

  @override
  State<ThemeNoteField> createState() => _ThemeNoteFieldState();
}

class _ThemeNoteFieldState extends State<ThemeNoteField> {
  late final TextEditingController _field =
      TextEditingController(text: widget.notes.textFor(widget.theme) ?? '');
  late String _saved = _field.text;
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _field.text;
    setState(() => _busy = true);
    final ok = await widget.notes.save(widget.theme, text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
      if (ok) _saved = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final changed = _field.text.trim() != _saved.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Моя заметка', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        TextField(
          key: const Key('note-field'),
          controller: _field,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'что понял об этом клише',
          ),
        ),
        const SizedBox(height: 8),
        // Кнопка во всю ширину, а не в строке: у кнопок темы задана только
        // высота, и в `Row` такая кнопка требует бесконечной ширины.
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('note-save'),
            onPressed: changed && !_busy ? _save : null,
            child: const Text('Сохранить'),
          ),
        ),
        if (_failed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Не записалось — попробуй ещё раз',
              key: const Key('note-failed'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
