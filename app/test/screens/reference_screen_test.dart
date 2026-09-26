import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/article_repository.dart';
import 'package:chgk_trainer/data/handout_store.dart';
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

NoteEvent _note(String theme, String text) => NoteEvent(
      ts: _now.millisecondsSinceEpoch,
      day: localDay(_now),
      theme: theme,
      text: text,
    );

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
    // Тема приложения, а не голая Material: у её кнопок задана только высота,
    // и вёрстка, которая на голой теме проходит, на настоящей падает.
    child: MaterialApp(
      theme: buildDarkTheme(),
      home: ReferenceScreen(
        repository: FakeRepository(_pool),
        articles: FakeArticleRepository({
          'Ковентри': const Article(
            theme: 'Ковентри',
            text: 'Город разбомбили в 1940-м.',
            source: 'wiki',
          ),
          'Титаник': const Article(
            theme: 'Титаник',
            text: 'Лайнер утонул в 1912-м.',
            source: 'wiki',
            images: ['art-a.jpg', 'art-b.jpg'],
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

  testWidgets('заметка из справочника пишется в журнал', (tester) async {
    final log = MemoryEventLog();
    await _pump(tester, log);

    await tester.tap(find.text('Мадлен'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-field')), 'про печенье');
    await tester.pump();
    await tester.tap(find.byKey(const Key('note-save')));
    await tester.pumpAndSettle();

    final notes = (await log.readAll()).events.whereType<NoteEvent>().toList();
    expect(notes.single.theme, 'Мадлен');
    expect(notes.single.text, 'про печенье');
  });

  testWidgets('своя реалия стоит отдельно и счётчик кампании не трогает',
      (tester) async {
    final log = MemoryEventLog();
    await log.append(_note('Тортуга', 'пиратский остров'));
    await _pump(tester, log);

    expect(find.text('Тортуга'), findsOneWidget);
    expect(find.text('пиратский остров'), findsOneWidget);
    expect(find.text('Свои'), findsOneWidget);
    // Дно кампании конечное — свои его не размывают.
    expect(find.text('Узнано 0 · встречалось 0 · всего 3'), findsOneWidget);
    expect(find.text('Своих: 1'), findsOneWidget);
  });

  testWidgets('ввод названия показывает совпадения корпуса', (tester) async {
    await _pump(tester, MemoryEventLog());

    await tester.tap(find.byKey(const Key('custom-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-name')), 'ковен');
    await tester.pump();

    expect(find.byKey(const Key('custom-match-Ковентри')), findsOneWidget);
  });

  testWidgets('имя корпусного клише своей реалии не создаёт', (tester) async {
    final log = MemoryEventLog();
    await _pump(tester, log);

    await tester.tap(find.byKey(const Key('custom-add')));
    await tester.pumpAndSettle();
    // Другой регистр и лишний пробел — то же клише, а не новое.
    await tester.enterText(find.byKey(const Key('custom-name')), ' ковентри ');
    await tester.enterText(find.byKey(const Key('custom-note')), 'бомбили');
    await tester.pump();
    await tester.tap(find.byKey(const Key('custom-save')));
    await tester.pumpAndSettle();

    expect((await log.readAll()).events.whereType<NoteEvent>(), isEmpty);
    // Вместо заведения дубля открылась справка корпусного клише.
    expect(find.text('Город разбомбили в 1940-м.'), findsOneWidget);
  });

  testWidgets('заведение пишет одну заметку и строку в «Своих»',
      (tester) async {
    final log = MemoryEventLog();
    await _pump(tester, log);

    await tester.tap(find.byKey(const Key('custom-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-name')), 'Тортуга');
    await tester.enterText(
        find.byKey(const Key('custom-note')), 'пиратский остров');
    await tester.pump();
    await tester.tap(find.byKey(const Key('custom-save')));
    await tester.pumpAndSettle();

    final notes = (await log.readAll()).events.whereType<NoteEvent>().toList();
    expect(notes.single.theme, 'Тортуга');
    expect(notes.single.text, 'пиратский остров');
    expect(find.text('Своих: 1'), findsOneWidget);
  });

  testWidgets('у своей реалии нет статьи, но и «не нашлось» не пишем',
      (tester) async {
    final log = MemoryEventLog();
    await log.append(_note('Тортуга', 'пиратский остров'));
    await _pump(tester, log);

    await tester.tap(find.text('Тортуга'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article-custom')), findsOneWidget);
    expect(find.byKey(const Key('article-missing')), findsNothing);
  });

  testWidgets('кнопка удаляет реалию, но сперва спрашивает', (tester) async {
    final log = MemoryEventLog();
    await log.append(_note('Тортуга', 'пиратский остров'));
    await _pump(tester, log);

    await tester.tap(find.text('Тортуга'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить реалию'), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-delete')));
    await tester.pumpAndSettle();
    // Отмена ничего не трогает: одним тапом теряется вся реалия.
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect((await log.readAll()).events.whereType<NoteEvent>().length, 1);

    await tester.tap(find.byKey(const Key('note-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-delete-confirm')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Тортуга'), findsNothing);
  });

  testWidgets('у корпусного клише кнопка стирает заметку, а не клише',
      (tester) async {
    final log = MemoryEventLog();
    await log.append(_note('Ковентри', 'город'));
    await _pump(tester, log);

    await tester.tap(find.text('Ковентри'));
    await tester.pumpAndSettle();
    expect(find.text('Стереть заметку'), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-delete-confirm')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Клише корпуса остаётся в оглавлении — стёрлась только заметка.
    expect(find.text('Ковентри'), findsOneWidget);
  });

  testWidgets('без заметки кнопки удаления нет', (tester) async {
    await _pump(tester, MemoryEventLog());
    await tester.tap(find.text('Мадлен'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-delete')), findsNothing);
  });

  testWidgets('стёртая заметка снимает и саму реалию', (tester) async {
    final log = MemoryEventLog();
    await log.append(_note('Тортуга', 'пиратский остров'));
    await _pump(tester, log);

    await tester.tap(find.text('Тортуга'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-field')), '');
    await tester.pump();
    await tester.tap(find.byKey(const Key('note-save')));
    await tester.pumpAndSettle();
    // Закрыть лист тапом по затемнению — как это делает игрок.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Тортуга'), findsNothing);
    expect(find.byKey(const Key('reference-custom-counter')), findsNothing);
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


  // T14: поиск по оглавлению.
  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('reference-search')), text);
    await tester.pumpAndSettle();
  }

  testWidgets('поиск без учёта регистра оставляет совпавшие', (tester) async {
    await _pump(tester, MemoryEventLog());
    await search(tester, 'КОВЕН');
    expect(find.text('Ковентри'), findsOneWidget);
    expect(find.text('Мадлен'), findsNothing);
    expect(find.text('Титаник'), findsNothing);
    // Счётчик кампании — про кампанию, а не про выдачу поиска.
    expect(find.text('Узнано 0 · встречалось 0 · всего 3'), findsOneWidget);
  });

  testWidgets('поиск находит и свои реалии', (tester) async {
    final log = MemoryEventLog();
    await log.append(_note('Ёжик в тумане', 'мультфильм Норштейна'));
    await _pump(tester, log);
    await search(tester, 'ежик');
    expect(find.text('Ёжик в тумане'), findsOneWidget);
    expect(find.text('Ковентри'), findsNothing);
  });

  testWidgets('ничего не нашлось — сообщение, крестик возвращает список',
      (tester) async {
    await _pump(tester, MemoryEventLog());
    await search(tester, 'щщщ');
    expect(find.byKey(const Key('reference-no-match')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reference-search-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reference-no-match')), findsNothing);
    expect(find.text('Титаник'), findsOneWidget);
  });

  // T14: иллюстрации статьи.
  testWidgets('у статьи с картинками лента есть, без картинок нет',
      (tester) async {
    final prev = HandoutStore.instance;
    HandoutStore.instance = _NoNetworkStore();
    addTearDown(() => HandoutStore.instance = prev);
    await _pump(tester, MemoryEventLog());

    await tester.tap(find.text('Титаник'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article-images')), findsOneWidget);
    // Без сети — значок на каждой картинке, а текст справки на месте.
    expect(find.byKey(const Key('article-image-missing')), findsNWidgets(2));
    expect(find.text('Лайнер утонул в 1912-м.'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // закрыть лист
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ковентри'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article-images')), findsNothing);
  });
}

class BrokenRepository implements QuestionRepository {
  @override
  Future<List<Question>> loadAll() async =>
      throw const QuestionAssetException('Ассет вопросов не собран.');
}

class _NoNetworkStore implements HandoutStore {
  @override
  Future<ImageProvider> resolve(String file) async => throw Exception('нет сети');
}
