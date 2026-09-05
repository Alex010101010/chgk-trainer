import '../journal/event.dart';

/// Вопрос из дампа. Читается из `data/*_clean.json` в форме после T11.
///
/// Все необязательные поля берутся с проверкой типа, а не по ключу напрямую:
/// в корпусе `comment` отсутствует у 2769 вопросов, `sources` пуст у 1710,
/// `author` — у 470. Прямое обращение упало бы на каждом третьем.
class Question {
  final String id;
  final Corpus corpus;
  final String question;
  final String answer;

  /// Формулировка зачёта из пакета. Заполнена у 28% — промах матчера норма.
  final String? acceptance;

  /// Нормализованные варианты зачёта из T11. Вход матчера.
  final List<String> acceptVariants;

  final String? comment;
  final List<String> sources;
  final String? author;

  /// Настоящее клише. У gq-корпуса всегда `null` — поле осмысленно только для
  /// бинго. Цикл его не читает; его переносит в событие режим.
  final String? theme;

  /// Эталон приёмов, проставленный при сборке ассета (T4a). Точность высокая,
  /// полнота низкая: пустой список значит «не нашли», а не «приёма нет».
  final List<String> tehniki;

  /// Имя файла раздатки в `assets/handouts/` (T20). `null` — раздатки нет.
  /// Вопрос с непустым полем без картинки не играется: сборщик ассета следит,
  /// чтобы такого не случилось.
  final String? handout;

  const Question({
    required this.id,
    required this.corpus,
    required this.question,
    required this.answer,
    this.acceptance,
    this.acceptVariants = const [],
    this.comment,
    this.sources = const [],
    this.author,
    this.theme,
    this.tehniki = const [],
    this.handout,
  });

  /// Возвращает `null` на записи без обязательных полей: испорченная строка
  /// дампа не должна ронять загрузку всего корпуса.
  static Question? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final id = j['id'];
    final question = j['question'];
    final answer = j['answer'];
    final corpus = switch (j['corpus']) {
      'gq' => Corpus.gq,
      'bingo' => Corpus.bingo,
      _ => null,
    };
    if (id is! String || question is! String || answer is! String || corpus == null) {
      return null;
    }
    final variants = j['acceptVariants'];
    final sources = j['sources'];
    final tehniki = j['tehniki'];
    return Question(
      id: id,
      corpus: corpus,
      question: question,
      answer: answer,
      acceptance: j['acceptance'] is String ? j['acceptance'] as String : null,
      acceptVariants:
          variants is List ? variants.whereType<String>().toList() : const [],
      comment: j['comment'] is String ? j['comment'] as String : null,
      sources: sources is List ? sources.whereType<String>().toList() : const [],
      author: j['author'] is String ? j['author'] as String : null,
      theme: j['theme'] is String ? j['theme'] as String : null,
      tehniki:
          tehniki is List ? tehniki.whereType<String>().toList() : const [],
      handout: j['handout'] is String ? j['handout'] as String : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'corpus': corpus.name,
        'question': question,
        'answer': answer,
        'acceptance': acceptance,
        'acceptVariants': acceptVariants,
        'comment': comment,
        'sources': sources,
        'author': author,
        'theme': theme,
        'tehniki': tehniki,
        'handout': handout,
      };
}
