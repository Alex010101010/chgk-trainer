import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'event_log.dart';
import 'event_log_io.dart';

Future<EventLog> createEventLog() async {
  final dir = await getApplicationDocumentsDirectory();
  return FileEventLog(File('${dir.path}/journal.jsonl'));
}
