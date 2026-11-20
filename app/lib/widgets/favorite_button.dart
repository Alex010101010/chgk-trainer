import 'package:flutter/material.dart';
import '../journal/event.dart';
import '../journal/event_log.dart';
import '../journal/favorites.dart';
import '../journal/journal_scope.dart';
import '../model/question.dart';

class FavoriteButton extends StatefulWidget {
  final Question question;
  final String origin;
  final String? explanation;
  const FavoriteButton(
      {super.key,
      required this.question,
      required this.origin,
      this.explanation});

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  EventLog? _log;
  bool? _saved;
  bool _busy = false;
  bool _error = false;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final log = JournalScope.maybeOf(context);
    if (log != _log) {
      _log = log;
      if (log != null) _load();
    }
  }

  @override
  void didUpdateWidget(FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id && _log != null) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _saved = null;
      _error = false;
    });
    try {
      final read = await _log!.readAll();
      if (!mounted || request != _request) return;
      setState(() => _saved = favoriteQuestions(read.events)
          .any((f) => f.question.id == widget.question.id));
    } catch (e) {
      debugPrint('[favorites] read failed: $e');
      if (mounted && request == _request) setState(() => _error = true);
    }
  }

  Future<void> _toggle() async {
    if (_busy || _saved == null) return;
    final q = widget.question;
    final saved = !_saved!;
    setState(() => _busy = true);
    try {
      await _log!.append(FavoriteEvent.at(DateTime.now(),
          questionId: q.id,
          saved: saved,
          snapshot: saved ? q.toJson() : null,
          origin: widget.origin,
          explanation: widget.explanation));
      if (mounted && widget.question.id == q.id) setState(() => _saved = saved);
    } catch (e) {
      debugPrint('[favorites] write failed: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(saved
                ? 'Не удалось сохранить вопрос. Попробуй ещё раз.'
                : 'Не удалось удалить вопрос из избранного. Попробуй ещё раз.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // В изолированных превью цикла журнала может не быть; в приложении он есть.
    if (_log == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: Key('favorite-${widget.question.id}'),
      onPressed: _busy
          ? null
          : _error
              ? _load
              : _saved == null
                  ? null
                  : _toggle,
      icon: Icon(_error
          ? Icons.refresh
          : _saved == true
              ? Icons.bookmark
              : Icons.bookmark_border),
      label: Text(_error
          ? 'Повторить загрузку избранного'
          : _busy
              ? 'Сохраняю…'
              : _saved == true
                  ? 'В избранном · убрать'
                  : 'В избранное'),
    );
  }
}
