import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'journal/event.dart';
import 'journal/event_log.dart';
import 'journal/event_log_factory.dart';
import 'journal/journal_scope.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  EventLog log;
  try {
    log = await createEventLog();
  } catch (e) {
    // Журнал не должен уметь не пускать в приложение. Но и молчать нельзя —
    // иначе «прогресс не сохраняется» выяснится через неделю игры.
    debugPrint('[journal] хранилище недоступно, журнал только в памяти: $e');
    log = MemoryEventLog();
  }
  runApp(ChgkTrainerApp(log: log));
}

class ChgkTrainerApp extends StatefulWidget {
  final EventLog log;

  const ChgkTrainerApp({super.key, required this.log});

  @override
  State<ChgkTrainerApp> createState() => _ChgkTrainerAppState();
}

class _ChgkTrainerAppState extends State<ChgkTrainerApp> {
  @override
  void initState() {
    super.initState();
    _recordSessionStart();
  }

  Future<void> _recordSessionStart() async {
    try {
      await widget.log.append(SessionStartEvent.at(DateTime.now()));
    } catch (e) {
      debugPrint('[journal] не удалось записать sessionStart: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return JournalScope(
      log: widget.log,
      child: MaterialApp(
        title: 'Панда будет?',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}
