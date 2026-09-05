import 'package:chgk_trainer/cycle/cycle_controller.dart';
import 'package:chgk_trainer/data/article_repository.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/theme_notes.dart';
import 'package:chgk_trainer/cycle/question_cycle.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _q = Question(
  id: 'gq-1',
  corpus: Corpus.gq,
  question: 'текст вопроса',
  answer: 'Уорхол.',
  acceptVariants: ['уорхол'],
  comment: 'комментарий',
  sources: ['источник'],
  author: 'автор',
);

/// Вопрос бинго-корпуса: у него есть клише, и только у такого под ответом
/// появляется справка.
const _bingoQ = Question(
  id: 'ix-koventri-1',
  corpus: Corpus.bingo,
  question: 'текст вопроса',
  answer: 'Ковентри.',
  acceptVariants: ['ковентри'],
  theme: 'Ковентри',
);

class FakeArticleRepository extends ArticleRepository {
  final Map<String, Article> articles;
  FakeArticleRepository(this.articles);

  @override
  Future<Map<String, Article>> loadAll() async => articles;
}

Future<void> _pump(
  WidgetTester tester,
  void Function(AnswerEvent) onFinished, {
  bool askBingoTap = false,
  List<String>? bingoGrid,
  Question question = _q,
  ArticleRepository? articles,
  ThemeNotes? notes,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: QuestionCycle(
        question: question,
        articles: articles,
        notes: notes,
        config: CycleConfig(
          mode: GameMode.classic,
          askBingoTap: askBingoTap,
          bingoGrid: bingoGrid,
        ),
        onFinished: onFinished,
      ),
    ),
  ));
}

const _grid = [
  'Ковентри', 'Мадлен', 'Гинденбург',
  'Мёртвые души', 'Плот «Медузы»', 'Ковчег',
  'Чукча', 'Павлов', 'Муха',
];

/// Довести цикл до конца после раскрытия — оценка и причина.
Future<void> _finishAfterReveal(WidgetTester tester) async {
  await _tap(tester, 'cycle-to-verdict');
  await tester.tap(find.text('Не взял'));
  await tester.pump();
  await _tap(tester, 'cycle-verdict-done');
  await _tap(tester, 'cycle-reason-done');
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

void main() {
  testWidgets('полный проход reading→done отдаёт событие', (tester) async {
    AnswerEvent? got;
    await _pump(tester, (e) => got = e);

    expect(find.text('текст вопроса'), findsOneWidget);
    await _tap(tester, 'cycle-start');
    await _tap(tester, 'cycle-ready');

    await tester.enterText(find.byKey(const Key('cycle-answer-field')), 'Уорхол');
    await tester.pump();
    await _tap(tester, 'cycle-answer-done');

    expect(find.text('комментарий'), findsOneWidget);
    await _tap(tester, 'cycle-to-verdict');
    await _tap(tester, 'cycle-verdict-done');

    expect(got, isNotNull);
    expect(got!.questionId, 'gq-1');
    expect(got!.answerWindowSec, kDefaultAnswerWindowSec);
    expect(got!.verdict, Verdict.taken); // предзаполнено матчером
    expect(got!.userAnswer, 'Уорхол');
  });

  // T18: версия сдаётся один раз, в окне записи. Во время минуты ввода нет —
  // иначе набранное в блокноте исчезает по «Готов отвечать» и выглядит как
  // потерянная работа.
  testWidgets('во время минуты поля ввода нет', (tester) async {
    await _pump(tester, (_) {});
    await _tap(tester, 'cycle-start');
    expect(find.byType(TextField), findsNothing);

    await _tap(tester, 'cycle-ready');
    expect(find.byKey(const Key('cycle-answer-field')), findsOneWidget);
  });

  testWidgets('пустая версия не блокирует переход', (tester) async {
    AnswerEvent? got;
    await _pump(tester, (e) => got = e);
    await _tap(tester, 'cycle-start');
    await _tap(tester, 'cycle-ready');
    await _tap(tester, 'cycle-answer-done');
    await _tap(tester, 'cycle-to-verdict');

    // Матчер ничего не предзаполнил — кнопка «дальше» ждёт выбора игрока.
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('cycle-verdict-done')))
            .onPressed,
        isNull);
    await tester.tap(find.text('Не взял'));
    await tester.pump();
    await _tap(tester, 'cycle-verdict-done');
    await _tap(tester, 'cycle-reason-done'); // причину пропустили

    expect(got, isNotNull);
    expect(got!.userAnswer, '');
    expect(got!.verdict, Verdict.missed);
    expect(got!.reason, isNull);
  });

  testWidgets('тап «это бинго?» показан до раскрытия', (tester) async {
    AnswerEvent? got;
    await _pump(tester, (e) => got = e, askBingoTap: true);
    await _tap(tester, 'cycle-start');
    await _tap(tester, 'cycle-ready');
    await _tap(tester, 'cycle-answer-done');

    expect(find.text('Узнал клише? Назови'), findsOneWidget);
    expect(find.text('комментарий'), findsNothing);

    await tester.enterText(find.byKey(const Key('cycle-bingo-field')), 'Ковентри');
    await _tap(tester, 'cycle-bingo-done');
    expect(find.text('комментарий'), findsOneWidget);

    await _tap(tester, 'cycle-to-verdict');
    await tester.tap(find.text('Почти'));
    await tester.pump();
    await _tap(tester, 'cycle-verdict-done');
    await _tap(tester, 'cycle-reason-done');

    expect(got!.themeGuess, 'Ковентри');
  });

  testWidgets('пустой открытый ввод — «не спрашивали», а не «ни к одной»',
      (tester) async {
    AnswerEvent? got;
    await _pump(tester, (e) => got = e, askBingoTap: true);
    await _tap(tester, 'cycle-start');
    await _tap(tester, 'cycle-ready');
    await _tap(tester, 'cycle-answer-done');
    await _tap(tester, 'cycle-bingo-done');
    await _finishAfterReveal(tester);
    expect(got!.themeGuess, isNull);
  });

  group('сетка клеток (T3)', () {
    testWidgets('выбор клетки пишет тему', (tester) async {
      AnswerEvent? got;
      await _pump(tester, (e) => got = e,
          askBingoTap: true, bingoGrid: _grid);
      await _tap(tester, 'cycle-start');

      // Девять подсказок во время минуты превратили бы узнавание в перебор.
      expect(find.byKey(const Key('cycle-bingo-grid')), findsNothing);
      expect(find.text('Гинденбург'), findsNothing);

      await _tap(tester, 'cycle-ready');
      expect(find.byKey(const Key('cycle-bingo-grid')), findsNothing);

      await _tap(tester, 'cycle-answer-done');
      expect(find.byKey(const Key('cycle-bingo-grid')), findsOneWidget);
      // Открытого ввода в режиме сетки нет.
      expect(find.byKey(const Key('cycle-bingo-field')), findsNothing);

      await tester.tap(find.text('Гинденбург'));
      await tester.pump();
      await _finishAfterReveal(tester);
      expect(got!.themeGuess, 'Гинденбург');
    });

    testWidgets('«ни к одной» пишет маркер отказа, а не null', (tester) async {
      // Красный→зелёный: наивное `submitBingoTap('')` кладёт null, и отказ
      // становится неотличим от «клетку не спрашивали».
      AnswerEvent? got;
      await _pump(tester, (e) => got = e,
          askBingoTap: true, bingoGrid: _grid);
      await _tap(tester, 'cycle-start');
      await _tap(tester, 'cycle-ready');
      await _tap(tester, 'cycle-answer-done');
      await tester.ensureVisible(find.byKey(const Key('cycle-bingo-none')));
      await tester.pump();
      await _tap(tester, 'cycle-bingo-none');
      await _finishAfterReveal(tester);

      expect(got!.themeGuess, kThemeGuessNone);
      expect(got!.themeGuess, isNotNull);
    });
  });

  group('справка по клише (T14)', () {
    final repo = FakeArticleRepository({
      'Ковентри': const Article(
        theme: 'Ковентри',
        text: 'Город разбомбили в 1940-м.\n\n## Как обыгрывают\n\nВот так.',
        source: 'wiki',
      ),
    });

    Future<void> toReveal(WidgetTester tester) async {
      await _tap(tester, 'cycle-start');
      await _tap(tester, 'cycle-ready');
      await _tap(tester, 'cycle-answer-done');
    }

    testWidgets('под ответом свёрнута и раскрывается тапом', (tester) async {
      await _pump(tester, (_) {}, question: _bingoQ, articles: repo);
      await toReveal(tester);

      expect(find.text('Клише: Ковентри'), findsOneWidget);
      // Свёрнута: разбор читают ради ответа, статья поверх него мешала бы.
      expect(find.byKey(const Key('cycle-article-body')), findsNothing);

      await _tap(tester, 'cycle-article-toggle');
      await tester.pumpAndSettle();
      expect(find.text('Город разбомбили в 1940-м.'), findsOneWidget);
      expect(find.text('Как обыгрывают'), findsOneWidget);
    });

    testWidgets('в карточке можно записать заметку на клише', (tester) async {
      final log = MemoryEventLog();
      final notes = ThemeNotes(log: log, events: const []);
      await _pump(tester, (_) {},
          question: _bingoQ, articles: repo, notes: notes);
      await toReveal(tester);
      await _tap(tester, 'cycle-article-toggle');
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('note-field')), 'бомбёжка 1940-го');
      await tester.pump();
      await _tap(tester, 'note-save');
      await tester.pumpAndSettle();

      final written =
          (await log.readAll()).events.whereType<NoteEvent>().single;
      expect(written.theme, 'Ковентри');
      expect(written.text, 'бомбёжка 1940-го');
    });

    testWidgets('у вопроса без клише карточки нет', (tester) async {
      await _pump(tester, (_) {}, articles: repo);
      await toReveal(tester);

      expect(find.byKey(const Key('cycle-article-toggle')), findsNothing);
    });

    testWidgets('режим без справок — карточки нет даже у бинго-вопроса',
        (tester) async {
      await _pump(tester, (_) {}, question: _bingoQ);
      await toReveal(tester);

      expect(find.byKey(const Key('cycle-article-toggle')), findsNothing);
    });
  });
}
