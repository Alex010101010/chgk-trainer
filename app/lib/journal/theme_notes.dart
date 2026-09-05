import 'event.dart';
import 'event_log.dart';
import 'projections.dart';

/// Заметки на клише: прочитать последнюю и записать новую (T14).
///
/// Один объект на оба места, где заметку пишут, — карточку под раскрытым
/// ответом и справку из сетки или справочника. Иначе каждому экрану пришлось
/// бы знать про журнал, а виджету справки — про запись событий.
///
/// Журнал append-only: правка — это новая запись, стирание — запись с пустым
/// текстом. Кэш обновляется на месте, чтобы заново открытая справка показала
/// только что написанное, не перечитывая файл.
class ThemeNotes {
  final EventLog _log;
  final DateTime Function() _now;
  final Map<String, String> _byTheme;

  ThemeNotes({
    required EventLog log,
    required List<JournalEvent> events,
    DateTime Function()? now,
  })  : _log = log,
        _now = now ?? DateTime.now,
        _byTheme = themeNotes(events);

  String? textFor(String theme) => _byTheme[theme];

  /// Пишет заметку. Пустой текст снимает её — специального «удалить» нет.
  ///
  /// Возвращает `false`, если записать не удалось: заметку в поле игрок
  /// видит, и молчаливая потеря выглядела бы как сохранённая.
  Future<bool> save(String theme, String text) async {
    final trimmed = text.trim();
    final at = _now();
    try {
      await _log.append(NoteEvent(
        ts: at.millisecondsSinceEpoch,
        day: localDay(at),
        theme: theme,
        text: trimmed,
      ));
    } catch (_) {
      return false;
    }
    if (trimmed.isEmpty) {
      _byTheme.remove(theme);
    } else {
      _byTheme[theme] = trimmed;
    }
    return true;
  }
}
