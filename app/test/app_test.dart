import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('старт приложения пишет ровно одно событие sessionStart',
      (tester) async {
    final log = MemoryEventLog();
    await tester.pumpWidget(ChgkTrainerApp(log: log));
    await tester.pumpAndSettle();

    final read = await log.readAll();
    expect(read.events, hasLength(1));
    expect(read.events.single, isA<SessionStartEvent>());
    expect(read.skippedLines, 0);
  });

  testWidgets('журнал доступен экранам через JournalScope', (tester) async {
    final log = MemoryEventLog();
    late EventLog seen;
    await tester.pumpWidget(JournalScope(
      log: log,
      child: Builder(builder: (context) {
        seen = JournalScope.of(context);
        return const SizedBox();
      }),
    ));
    expect(identical(seen, log), isTrue);
  });
}
