import 'package:flutter/widgets.dart';

import 'event_log.dart';

/// Проброс журнала в дерево виджетов. Двадцать строк без пакета — достаточно
/// для единственного потребителя; T2a вправе заменить это своим решением по
/// состоянию, когда у него появятся собственные нужды.
class JournalScope extends InheritedWidget {
  final EventLog log;

  const JournalScope({super.key, required this.log, required super.child});

  static EventLog of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<JournalScope>();
    assert(scope != null, 'JournalScope не найден выше по дереву');
    return scope!.log;
  }

  @override
  bool updateShouldNotify(JournalScope oldWidget) => oldWidget.log != log;
}
