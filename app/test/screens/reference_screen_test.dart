import 'package:chgk_trainer/data/article_repository.dart';
import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/screens/reference_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 9, 5, 12);

Question _bingo(String theme) => Question(
      id: 'b-$theme',
      corpus: Corpus.bingo,
      question: 'вопрос $theme',
      answer: 'ответ',
      acceptVariants: ['ответ'],
      theme: theme,
    );

const _gq = Question(
  id: 'gq-1',
  corpus: Corpus.gq,
  question: 'отвлекающий',
  answer: 'ответ',
  acceptVariants: ['ответ'],
);

final _pool = [_bingo('Ковентри'), _bingo('Мадлен'), _bingo('Титаник'), _gq];

AnswerEvent _answer(String theme, {String? guess}) => AnswerEvent(
      ts: _now.millisecondsSinceEpoch,
      day: localDay(_now),
      questionId: 'b-$theme',
      corpus: Corpus.bingo,
      mode: GameMode.bingo,
      verdict: Verdict.taken,
      secondsUsed: 60,
      theme: theme,
      themeGuess: guess,
    );

class FakeRepository implements QuestionRepository {
  final List<Question> questions;
  FakeRepository(this.questions);

  @override
  Future<List<Question>> loadAll() async => questions;
}

class FakeArticleRepository extends ArticleRepository {
  final Map<String, Article> articles;
  FakeArticleRepository(this.articles);

  @override
  Future<Map<String, Article>> loadAll() async => articles;
}

Future<void> _pump(WidgetTester tester, EventLog log) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      home: ReferenceScreen(
        repository: FakeRepository(_pool),
        articles: FakeArticleRepository({
          'Ковентри': const Article(
            theme: 'Ковентри',
            text: 'Город разбомбили в 1940-м.',
            source: 'wiki',
          ),
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('оглавление — все клише корпуса, а не только виденные',
      (tester) async {
    await _pump(tester, MemoryEventLog());

    expect(find.text('Ковентри'), findsOneWidget);
    expect(find.text('Мадлен'), findsOneWidget);
    expect(find.text('Титаник'), findsOneWidget);
    // Отвлекающие gq-вопросы клише не имеют и в справочник не едут.
    expect(find.text('отвлекающий'), findsNothing);
    expect(find.text('Узнано 0 · встречалось 0 · всего 3'), findsOneWidget);
  });

  testWidgets('три состояния: узнано, встречалось, не встречалось',
      (tester) async {
    final log = MemoryEventLog();
    await log.append(_answer('Ковентри', guess: 'Ковентри'));
    await log.append(_answer('Мадлен', guess: kThemeGuessNone));
    await _pump(tester, log);

    expect(find.text('Узнано 1 · встречалось 2 · всего 3'), findsOneWidget);
    expect(find.text('узнано'), findsOneWidget);
    expect(find.text('встречалось'), findsOneWidget);
    expect(find.text('не встречалось'), findsOneWidget);
  });

  testWidgets('тап по строке открывает справку', (tester) async {
    await _pump(tester, MemoryEventLog());

    await tester.tap(find.text('Ковентри'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article-title')), findsOneWidget);
    expect(find.text('Город разбомбили в 1940-м.'), findsOneWidget);
  });

  testWidgets('несобранный ассет вопросов — сообщение, а не пустой список',
      (tester) async {
    await tester.pumpWidget(JournalScope(
      log: MemoryEventLog(),
      child: MaterialApp(
        home: ReferenceScreen(repository: BrokenRepository()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reference-error')), findsOneWidget);
  });
}

class BrokenRepository implements QuestionRepository {
  @override
  Future<List<Question>> loadAll() async =>
      throw const QuestionAssetException('Ассет вопросов не собран.');
}
