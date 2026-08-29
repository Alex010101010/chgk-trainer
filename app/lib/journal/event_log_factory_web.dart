import 'event_log.dart';

/// На web персистентности нет: превью на github.io — демка, а не рабочее
/// приложение. Прогресс там не переживает перезагрузку, и это осознанно.
Future<EventLog> createEventLog() async => MemoryEventLog();
