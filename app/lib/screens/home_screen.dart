import 'dart:math';

import 'package:flutter/material.dart';
import '../data/question_repository.dart';
import '../data/tehnika_repository.dart';
import '../journal/journal_scope.dart';
import '../journal/projections.dart';
import '../model/question.dart';
import '../model/tehnika.dart';
import '../widgets/coming_soon_screen.dart';
import '../widgets/update_button.dart';
import 'classic_screen.dart';
import 'debug_journal_screen.dart';
import 'tehnika_card_screen.dart';

class _ModeInfo {
  final String title;
  final String subtitle;
  final IconData icon;
  const _ModeInfo(this.title, this.subtitle, this.icon);
}

const _modes = [
  _ModeInfo('Классика', 'Вопрос + таймер 60 сек', Icons.timer_outlined),
  _ModeInfo('Тренажёр рассуждений', 'Факты → версии → отсечение',
      Icons.psychology_outlined),
  _ModeInfo('Бинго', 'Сетка тем 3×3', Icons.grid_3x3),
];

class HomeScreen extends StatelessWidget {
  /// Репозиторий инжектируется — это seam для виджет-тестов главного экрана:
  /// иначе они тянули бы настоящий ассет на 8.6 МБ.
  final QuestionRepository? repository;
  final TehnikaRepository? tehnikaRepository;

  /// Флаг «карточку урока уже показывали». Прокидывается сверху, а не
  /// создаётся здесь: иначе экран режима и экран карточки не узнают друг
  /// о друге, и урок откроется дважды подряд.
  final TehnikaCardSeen? cardSeen;

  const HomeScreen({
    super.key,
    this.repository,
    this.tehnikaRepository,
    this.cardSeen,
  });

  Widget _screenFor(String title) => switch (title) {
        'Классика' => ClassicScreen(
            repository: repository ?? AssetQuestionRepository(),
            tehnikaRepository: tehnikaRepository,
            cardSeen: cardSeen,
          ),
        _ => ComingSoonScreen(
            title: title,
            icon: _modes.firstWhere((m) => m.title == title).icon,
          ),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Долгий тап по заголовку — вход в отладку. Не пункт меню: это
        // сверка с критериями MVP, а не функция приложения.
        title: GestureDetector(
          key: const Key('home-title'),
          onLongPress: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DebugJournalScreen(
                repository: repository ?? AssetQuestionRepository(),
              ),
            ),
          ),
          child: const Text('Панда будет?'),
        ),
        // Приложение раздаётся сборкой из CI, а не через маркет: свежая версия
        // ставится отсюда, без перекладывания APK на телефон руками.
        actions: const [UpdateButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                key: const Key('home-tehnika'),
                contentPadding: const EdgeInsets.all(16),
                leading: const Icon(Icons.school_outlined, size: 32),
                title: const Text('Приём недели'),
                subtitle: const Text('Карточка урока — полминуты'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _TehnikaCardScreen(
                      repository: repository ?? AssetQuestionRepository(),
                      tehnikaRepository:
                          tehnikaRepository ?? AssetTehnikaRepository(),
                      cardSeen: cardSeen,
                    ),
                  ),
                ),
              ),
            ),
            ..._modes
              .map((m) => Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Icon(m.icon, size: 32),
                      title: Text(m.title,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600)),
                      subtitle: Text(m.subtitle),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _screenFor(m.title),
                        ),
                      ),
                    ),
                  ))
              .toList(),
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tehniki = await widget.tehnikaRepository.loadAll();
      final pool = await widget.repository.loadAll();
      final events = (await JournalScope.of(context).readAll()).events;
      final byId = {for (final q in pool) q.id: q};
      final t = tehniki[min(weekIndex(events, DateTime.now()), tehniki.length - 1)];
      if (!mounted) return;
      // Урок прочитан — перед раундом его показывать уже не нужно.
      widget.cardSeen?.value = true;
      setState(() {
        _tehnika = t;
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
      appBar: AppBar(title: const Text('Приём недели')),
      body: SafeArea(
        child: switch ((_error, _tehnika)) {
          (final String e, _) => Center(child: Padding(
              padding: const EdgeInsets.all(24), child: Text(e))),
          (_, final Tehnika t) => TehnikaCard(
              tehnika: t,
              questions: _examples,
              onDone: () => Navigator.of(context).pop(),
              doneLabel: 'Закрыть',
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}
