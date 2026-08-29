/// Приём рассуждения — «приём недели» из T4a.
///
/// Контент авторский и лежит в `assets/tehniki.json`, который коммитится:
/// генерировать его нечем. Поле `detect` из ассета сюда **не едет** — правило
/// поиска эталона исполняет скрипт сборки, приложение регулярок не запускает.
class Tehnika {
  final String id;
  final String title;

  /// Как приём выглядит в тексте, своими словами. Читается за полминуты.
  final String explain;

  /// Что спросить себя, наткнувшись на такой вопрос.
  final String trigger;

  final List<TehnikaExample> examples;

  const Tehnika({
    required this.id,
    required this.title,
    required this.explain,
    required this.trigger,
    this.examples = const [],
  });

  static Tehnika? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final id = j['id'];
    final title = j['title'];
    final explain = j['explain'];
    if (id is! String || title is! String || explain is! String) return null;
    final examples = j['examples'];
    return Tehnika(
      id: id,
      title: title,
      explain: explain,
      trigger: j['trigger'] is String ? j['trigger'] as String : '',
      examples: examples is List
          ? examples.map(TehnikaExample.fromJson).whereType<TehnikaExample>().toList()
          : const [],
    );
  }
}

/// Разобранный вопрос из корпуса. `why` — разбор своими словами; он же
/// показывается как объяснение, когда игрок промахнулся тапом.
class TehnikaExample {
  final String questionId;
  final String why;

  const TehnikaExample({required this.questionId, required this.why});

  static TehnikaExample? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final questionId = j['questionId'];
    final why = j['why'];
    if (questionId is! String || why is! String) return null;
    return TehnikaExample(questionId: questionId, why: why);
  }
}
