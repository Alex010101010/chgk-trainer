import '../model/question.dart';
import 'event.dart';

class FavoriteQuestion {
  final Question question;
  final String origin;
  final String? explanation;
  const FavoriteQuestion(this.question, this.origin, this.explanation);
}

/// Последнее действие в журнале важнее часов устройства. Повторное сохранение
/// не дублирует вопрос, удаление скрывает его; новые сохранения идут первыми.
List<FavoriteQuestion> favoriteQuestions(Iterable<JournalEvent> events) {
  final saved = <String, FavoriteQuestion>{};
  for (final e in events.whereType<FavoriteEvent>()) {
    if (!e.saved) {
      saved.remove(e.questionId);
      continue;
    }
    final q = Question.fromJson(e.snapshot);
    if (q == null || q.id != e.questionId) continue;
    saved.remove(e.questionId);
    saved[e.questionId] = FavoriteQuestion(q, e.origin, e.explanation);
  }
  return saved.values.toList().reversed.toList();
}
