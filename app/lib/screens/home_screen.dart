import 'package:flutter/material.dart';
import '../data/question_repository.dart';
import '../widgets/coming_soon_screen.dart';
import 'classic_screen.dart';

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

  const HomeScreen({super.key, this.repository});

  Widget _screenFor(String title) => switch (title) {
        'Классика' => ClassicScreen(
            repository: repository ?? AssetQuestionRepository(),
          ),
        _ => ComingSoonScreen(
            title: title,
            icon: _modes.firstWhere((m) => m.title == title).icon,
          ),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ЧГК-тренажёр')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _modes
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
        ),
      ),
    );
  }
}
