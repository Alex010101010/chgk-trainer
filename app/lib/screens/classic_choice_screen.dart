import 'package:flutter/material.dart';
import '../data/adult_consent.dart';
import '../data/question_repository.dart';
import '../data/tehnika_repository.dart';
import 'classic_screen.dart';

class ClassicChoiceScreen extends StatefulWidget {
  final QuestionRepository repository;
  final QuestionRepository? adultRepository;
  final AdultConsent? consent;
  final TehnikaRepository? tehnikaRepository;
  final TehnikaCardSeen? cardSeen;
  const ClassicChoiceScreen(
      {super.key,
      required this.repository,
      this.adultRepository,
      this.consent,
      this.tehnikaRepository,
      this.cardSeen});

  @override
  State<ClassicChoiceScreen> createState() => _ClassicChoiceScreenState();
}

class _ClassicChoiceScreenState extends State<ClassicChoiceScreen> {
  late final AdultConsent _consent = widget.consent ?? LocalAdultConsent();
  bool _busy = false;
  String? _error;

  Future<void> _open(bool adult) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (adult && !await _consent.isAccepted()) {
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Чёрное ЧГК · 18+'),
            content: const Text('Вопросы для взрослых: откровенные темы, '
                'грубая лексика и чёрный юмор. Продолжить?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена')),
              TextButton(
                  key: const Key('adult-confirm'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Мне есть 18, продолжить')),
            ],
          ),
        );
        if (accepted != true) return;
        await _consent.accept();
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ClassicScreen(
                repository: adult
                    ? widget.adultRepository ??
                        AssetQuestionRepository(
                            assetPath: 'assets/adult_questions.json')
                    : widget.repository,
                adult: adult,
                tehnikaRepository: widget.tehnikaRepository,
                cardSeen: widget.cardSeen,
              )));
    } catch (_) {
      if (mounted)
        setState(() =>
            _error = 'Не удалось сохранить подтверждение. Попробуй ещё раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Классика')),
        body: SafeArea(
            child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton(
                key: const Key('classic-standard'),
                onPressed: _busy ? null : () => _open(false),
                child: const Text('Обычное ЧГК')),
            const SizedBox(height: 16),
            OutlinedButton(
                key: const Key('classic-adult'),
                onPressed: _busy ? null : () => _open(true),
                child: const Text('Чёрное ЧГК · 18+')),
            const SizedBox(height: 12),
            const Text('Раунд из пяти вопросов, по минуте на каждый.'),
            if (_error != null) Text(_error!),
          ],
        )),
      );
}
