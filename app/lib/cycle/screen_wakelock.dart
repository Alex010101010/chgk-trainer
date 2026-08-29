import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Минуту думаешь не касаясь экрана, а автоблокировка на телефоне срабатывает
/// через 30 секунд — минуту. Без удержания режим ломается на ровном месте.
///
/// Ошибки глотаются намеренно: в тестах плагина нет, а погасший экран — повод
/// пожаловаться в лог, но не уронить вопрос посреди минуты.
Future<void> holdScreenAwake(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } catch (e) {
    debugPrint('[wakelock] недоступен: $e');
  }
}
