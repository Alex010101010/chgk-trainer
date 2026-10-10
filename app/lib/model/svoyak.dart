import 'question.dart';

/// Вопрос «Своей игры» (T6): обычный вопрос плюс номинал. Сам вопрос — тот
/// же [Question], чтобы раскрытие и подсказка зачёта работали как везде.
class SvoyakQuestion {
  final int nominal;
  final Question question;

  const SvoyakQuestion({required this.nominal, required this.question});
}

/// Тема — пять вопросов от 10 до 50, играются подряд, как на турнире.
class SvoyakTheme {
  /// id тура gotquestions, строкой.
  final String id;
  final String title;

  /// Турнир, откуда тема, — показывается при выборе.
  final String pack;
  final String? year;
  final List<SvoyakQuestion> questions;

  const SvoyakTheme({
    required this.id,
    required this.title,
    required this.pack,
    required this.year,
    required this.questions,
  });

  /// `null` на теме без обязательных полей или не из пяти вопросов: тема
  /// без вопроса — не тема, и испорченная запись не роняет загрузку всех.
  static SvoyakTheme? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final id = j['id'];
    final title = j['title'];
    final list = j['questions'];
    if (id is! String || title is! String || list is! List) return null;
    final questions = <SvoyakQuestion>[];
    for (final q in list) {
      if (q is! Map) return null;
      final nominal = q['nominal'];
      // Вопросы «Своей игры» — из gotquestions; поле корпуса в ассет не едет.
      final question = Question.fromJson({...q, 'corpus': 'gq'});
      if (nominal is! int || question == null) return null;
      questions.add(SvoyakQuestion(nominal: nominal, question: question));
    }
    if (questions.length != kSvoyakThemeSize) return null;
    questions.sort((a, b) => a.nominal.compareTo(b.nominal));
    return SvoyakTheme(
      id: id,
      title: title,
      pack: j['pack'] is String ? j['pack'] as String : '',
      year: j['year'] is String ? j['year'] as String : null,
      questions: questions,
    );
  }
}

const int kSvoyakThemeSize = 5;
