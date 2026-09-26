import 'dart:math';

import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/data/tehnika_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/journal/projections.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/model/tehnika.dart';
import 'package:chgk_trainer/screens/daily_screen.dart';
import 'package:chgk_trainer/screens/home_screen.dart';
import 'package:chgk_trainer/screens/tehnika_check_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 25, 12);

Tehnika _t(String id) =>
    Tehnika(id: id, title: 'Приём $id', explain: '', trigger: 'признак $id');

final _four = [_t('a'), _t('b'), _t('c'), _t('d')];

Question _q(String id, List<String> tehniki) => Question(
      id: id,
      corpus: Corpus.gq,
      question: 'вопрос $id',
      answer: 'ответ $id',
      acceptVariants: ['ответ $id'],
      comment: 'комментарий $id',
      tehniki: tehniki,
    );

/// По десять эталонных на приём и десять вопросов без приёма.
final _pool = [
  for (final t in ['a', 'b', 'c', 'd'])
    for (var i = 0; i < 10; i++) _q('$t$i', [t]),
  for (var i = 0; i < 10; i++) _q('x$i', const []),
];

AnswerEvent _answer(String id,
    {GameMode mode = GameMode.classic,
    Verdict verdict = Verdict.missed,
    int daysAgo = 0,
    DateTime? now,
    String? pick}) {
  final at = (now ?? _now).subtract(Duration(days: daysAgo));
  return AnswerEvent(
    ts: at.millisecondsSinceEpoch,
    day: localDay(at),
    questionId: id,
    corpus: Corpus.gq,
    mode: mode,
    verdict: verdict,
    secondsUsed: 0,
    tehnikaPick: pick,
  );
}

/// Первая запись 22 дня назад — неделя стажа 3, открыты все четыре приёма.
List<JournalEvent> _week3({DateTime? now}) =>
    [SessionStartEvent.at((now ?? _now).subtract(const Duration(days: 22)))];

class FakeQuestions implements QuestionRepository {
  final List<Question> questions;
  FakeQuestions(this.questions);
  @override
  Future<List<Question>> loadAll() async => questions;
}

class FakeTehniki implements TehnikaRepository {
  final List<Tehnika> tehniki;
  FakeTehniki(this.tehniki);
  @override
  Future<List<Tehnika>> loadAll() async => tehniki;
}

Future<MemoryEventLog> _logWith(List<JournalEvent> events) async {
  final log = MemoryEventLog();
  for (final e in events) {
    await log.append(e);
  }
  return log;
}

Future<void> _pumpScreen(WidgetTester tester, EventLog log,
    {List<Question>? pool}) async {
  await tester.pumpWidget(JournalScope(
    log: log,
    child: MaterialApp(
      theme: buildLightTheme(),
      home: TehnikaCheckScreen(
        repository: FakeQuestions(pool ?? _pool),
        tehnikaRepository: FakeTehniki(_four),
        now: () => _now,
        random: Random(1),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// id вопроса на экране — по тексту «вопрос <id>».
String _shownId(WidgetTester tester) {
  final t = tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .firstWhere((s) => s.startsWith('вопрос '));
  return t.substring('вопрос '.length);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('событие', () {
    test('tehnikaPick переживает запись и чтение, старая строка — null', () {
      final e = _answer('a1', mode: GameMode.tehnika, pick: 'b');
      final back = JournalEvent.fromJson(e.toJson()) as AnswerEvent;
      expect(back.tehnikaPick, 'b');
      expect(back.mode, GameMode.tehnika);

      final old = e.toJson()..remove('tehnikaPick');
      expect((JournalEvent.fromJson(old) as AnswerEvent).tehnikaPick, isNull);
    });
  });

  group('статистика не видит проверку', () {
    final check = [_answer('a1', mode: GameMode.tehnika, daysAgo: 10)];
    final classic = [_answer('a1', daysAgo: 10)];

    test('dueQuestions', () {
      expect(dueQuestions(check, _now), isEmpty);
      expect(dueQuestions(classic, _now), ['a1']);
    });

    test('takenRate', () {
      expect(takenRate(check), isNull);
      expect(takenRate(classic), 0);
    });

    test('answeredThisWeek', () {
      final checkToday = [_answer('a1', mode: GameMode.tehnika)];
      expect(answeredThisWeek(checkToday, _now), isFalse);
      expect(answeredThisWeek([_answer('a1')], _now), isTrue);
    });
  });

  group('отбор', () {
    test('при четырёх открытых — все четыре, текущий дважды', () {
      final round = selectCheckRound(_pool, _four, _week3(), _now,
          random: Random(1));
      expect(round.length, kCheckSize);
      final by = <String, int>{};
      for (final q in round) {
        by[q.tehniki.single] = (by[q.tehniki.single] ?? 0) + 1;
      }
      expect(by, {'a': 1, 'b': 1, 'c': 1, 'd': 2});
      expect(round.map((q) => q.id).toSet().length, kCheckSize);
    });

    test('виденный эталон не берётся', () {
      final seen = [for (var i = 0; i < 9; i++) _answer('d$i', daysAgo: 1)];
      final round = selectCheckRound(
          _pool, _four, [..._week3(), ...seen], _now,
          random: Random(1));
      final ids = round.map((q) => q.id).toSet();
      expect(ids.intersection(seen.map((e) => e.questionId).toSet()), isEmpty);
      // У текущего остался один невиденный — второй слот добран другим.
      expect(round.where((q) => q.tehniki.single == 'd').length, 1);
      expect(round.length, kCheckSize);
    });

    test('после двух ответов проверки — остаток из трёх', () {
      final done = [
        _answer('d0', mode: GameMode.tehnika, pick: 'd'),
        _answer('a0', mode: GameMode.tehnika, pick: 'b'),
      ];
      final round = selectCheckRound(
          _pool, _four, [..._week3(), ...done], _now,
          random: Random(1));
      expect(round.length, 3);
      expect(round.where((q) => q.tehniki.single == 'd').length, 1);
    });

    test('проверка прошлой недели остаток не уменьшает', () {
      final lastWeek = [
        for (var i = 0; i < 5; i++)
          _answer('c$i', mode: GameMode.tehnika, daysAgo: 8, pick: 'c'),
      ];
      final events = [..._week3(), ...lastWeek];
      expect(tehnikaCheckAnswers(events, _now), isEmpty);
      expect(selectCheckRound(_pool, _four, events, _now).length, kCheckSize);
    });

    test('вопрос с двумя приёмами берётся один раз', () {
      final pool = [_q('ab', ['a', 'b'])];
      final round =
          selectCheckRound(pool, _four, _week3(), _now, random: Random(1));
      expect(round.map((q) => q.id), ['ab']);
    });

    test('кнопок не больше шести, верная среди них', () {
      final eight = [for (final id in 'abcdefgh'.split('')) _t(id)];
      final q = _q('g1', ['g']);
      final options = checkOptions(q, eight);
      expect(options.length, kCheckMaxOptions);
      expect(options.map((t) => t.id), contains('g'));
      expect(checkOptions(q, eight).map((t) => t.id),
          options.map((t) => t.id), reason: 'набор стабилен между показами');
      expect(checkOptions(q, _four), _four);
    });

    test('открытые приёмы — по неделе стажа', () {
      expect(openedTehniki(_four, 0).map((t) => t.id), ['a']);
      expect(openedTehniki(_four, 2).map((t) => t.id), ['a', 'b', 'c']);
      expect(openedTehniki(_four, 9).length, 4);
    });
  });

  group('экран', () {
    testWidgets('неверный выбор показывает оба приёма и пишет событие',
        (tester) async {
      final log = await _logWith(_week3());
      await _pumpScreen(tester, log);

      final id = _shownId(tester);
      final right = id.substring(0, 1);
      final wrong = right == 'a' ? 'b' : 'a';
      await _tap(tester, 'check-option-$wrong');

      expect(find.text('Мимо'), findsOneWidget);
      expect(find.text('«Приём $right»'), findsOneWidget);
      expect(find.text('Ты выбрал: «Приём $wrong»'), findsOneWidget);

      final e = (await log.readAll()).events.whereType<AnswerEvent>().single;
      expect(e.mode, GameMode.tehnika);
      expect(e.questionId, id);
      expect(e.tehnikaPick, wrong);
      expect(e.verdict, Verdict.missed);
    });

    testWidgets('пять вопросов — пять событий и итог', (tester) async {
      final log = await _logWith(_week3());
      await _pumpScreen(tester, log);
      for (var i = 0; i < kCheckSize; i++) {
        final right = _shownId(tester).substring(0, 1);
        await _tap(tester, 'check-option-$right');
        expect(find.text('Узнал'), findsOneWidget);
        await _tap(tester, 'check-next');
      }
      expect(find.byKey(const Key('check-summary')), findsOneWidget);
      expect(find.text('Узнал 5 из 5'), findsOneWidget);
      final events = (await log.readAll()).events.whereType<AnswerEvent>();
      expect(events.where((e) => e.mode == GameMode.tehnika).length, kCheckSize);
    });

    /// Эталонный вопрос приёма «a» рядом с одним вопросом без приёма, с id,
    /// подобранным так, чтобы он был (или не был) сегодняшним вопросом дня.
    List<Question> poolWhere({required bool isDaily, String? handoutText}) {
      for (var i = 0;; i++) {
        final q = Question(
          id: 'a$i',
          corpus: Corpus.gq,
          question: 'вопрос a$i',
          answer: 'ответ',
          acceptVariants: const ['ответ'],
          handoutText: handoutText,
          tehniki: const ['a'],
        );
        final pool = [q, _q('x0', const [])];
        if ((dailyQuestion(pool, localDay(_now))?.id == q.id) == isDaily) {
          return pool;
        }
      }
    }

    testWidgets('сегодняшний вопрос дня в проверку не попадает',
        (tester) async {
      final log = await _logWith(_week3());
      await _pumpScreen(tester, log, pool: poolWhere(isDaily: true));
      expect(find.byKey(const Key('check-empty')), findsOneWidget);
    });

    testWidgets('текстовая раздатка видна', (tester) async {
      final log = await _logWith(_week3());
      await _pumpScreen(tester, log,
          pool: poolWhere(isDaily: false, handoutText: 'листок'));
      expect(find.byKey(const Key('cycle-handout-text')), findsOneWidget);
    });
  });

  group('главный экран', () {
    Future<void> pumpHome(WidgetTester tester, List<JournalEvent> events) async {
      final log = await _logWith(events);
      await tester.pumpWidget(JournalScope(
        log: log,
        child: MaterialApp(
          theme: buildLightTheme(),
          home: HomeScreen(
            repository: FakeQuestions(_pool),
            tehnikaRepository: FakeTehniki(_four),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    final now = DateTime.now();
    final start = SessionStartEvent.at(now.subtract(const Duration(days: 8)));
    AnswerEvent check(String id) =>
        _answer(id, mode: GameMode.tehnika, now: now, pick: 'a');

    const plain = 'Карточка урока — полминуты';
    const waits = 'Карточка урока · ждёт проверка';

    Future<void> openLesson(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('home-tehnika')));
      await tester.pumpAndSettle();
    }

    testWidgets('отдельной карточки проверки на главном экране нет',
        (tester) async {
      await pumpHome(tester, [start]);
      expect(find.byKey(const Key('home-check')), findsNothing);
      expect(find.text('Проверка недели'), findsNothing);
    });

    testWidgets('неделя 0 — ни напоминания, ни кнопки в уроке', (tester) async {
      await pumpHome(tester, [SessionStartEvent.at(now)]);
      expect(find.text(plain), findsOneWidget);
      await openLesson(tester);
      expect(find.byKey(const Key('tehnika-card-check')), findsNothing);
    });

    testWidgets('неделя 1 — подпись напоминает, в уроке кнопка активна',
        (tester) async {
      await pumpHome(tester, [start]);
      expect(find.text(waits), findsOneWidget);
      await openLesson(tester);
      final b = tester.widget<OutlinedButton>(
          find.byKey(const Key('tehnika-card-check')));
      expect(b.onPressed, isNotNull);
      expect(find.text('Проверка недели'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('tehnika-card-check')));
      await tester.tap(find.byKey(const Key('tehnika-card-check')));
      await tester.pumpAndSettle();
      expect(find.byType(TehnikaCheckScreen), findsOneWidget);
    });

    testWidgets('после двух ответов — «осталось 3»', (tester) async {
      await pumpHome(tester, [start, check('a0'), check('a1')]);
      expect(find.text(waits), findsOneWidget);
      await openLesson(tester);
      expect(find.text('Проверка недели · осталось 3'), findsOneWidget);
    });

    testWidgets('после пяти — подпись обычная, кнопка неактивна',
        (tester) async {
      await pumpHome(tester, [start, for (var i = 0; i < 5; i++) check('a$i')]);
      expect(find.text(plain), findsOneWidget);
      await openLesson(tester);
      final b = tester.widget<OutlinedButton>(
          find.byKey(const Key('tehnika-card-check')));
      expect(b.onPressed, isNull);
      expect(find.textContaining('Проверка сыграна'), findsOneWidget);
    });
  });
}
