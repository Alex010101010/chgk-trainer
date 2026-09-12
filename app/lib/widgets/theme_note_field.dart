import 'package:flutter/material.dart';

import '../journal/theme_notes.dart';

/// Своя заметка на клише (T14): место, куда пишешь понятое после промаха.
///
/// Одно поле и кнопка. Кнопка активна только когда текст изменился — иначе
/// «Сохранить» на нетронутой заметке выглядит как несохранённая работа.
class ThemeNoteField extends StatefulWidget {
  final String theme;
  final ThemeNotes notes;

  /// Своя реалия (T24): заметка для неё не дополнение, а всё её содержимое —
  /// поэтому и кнопка называется «Удалить реалию», а не «Стереть заметку».
  final bool custom;

  const ThemeNoteField({
    super.key,
    required this.theme,
    required this.notes,
    this.custom = false,
  });

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

  /// Стереть — это записать пустое: журнал append-only, удалять строки не
  /// приходится. Спрашиваем перед этим: одним тапом теряется весь текст,
  /// а у своей реалии вместе с ним и сама реалия.
  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(widget.custom
            ? 'Удалить реалию «${widget.theme}» вместе с заметкой?'
            : 'Стереть заметку?'),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const Key('note-delete-confirm'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Удалить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _field.clear();
    await _save();
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
        // Удаление отдельной кнопкой, хотя «стереть текст и сохранить» делает
        // то же самое: догадаться до этого нельзя, а спрятанное действие — это
        // отсутствующее действие. Появляется, только когда стирать есть что.
        if (_saved.trim().isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: TextButton(
              key: const Key('note-delete'),
              onPressed: _busy ? null : _confirmDelete,
              child: Text(
                widget.custom ? 'Удалить реалию' : 'Стереть заметку',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
