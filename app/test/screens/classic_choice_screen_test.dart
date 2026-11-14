import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chgk_trainer/app_theme.dart';
import 'package:chgk_trainer/data/adult_consent.dart';
import 'package:chgk_trainer/data/adult_consent_io.dart' as disk;
import 'package:chgk_trainer/data/question_repository.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/journal/event_log.dart';
import 'package:chgk_trainer/journal/journal_scope.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/screens/classic_choice_screen.dart';
import 'package:chgk_trainer/screens/classic_screen.dart';
import 'classic_screen_test.dart' show FakeTehniki;

class _Consent implements AdultConsent {
  bool accepted = false;
  bool fail = false;
  @override
  Future<bool> isAccepted() async => accepted;
  @override
  Future<void> accept() async {
    if (fail) throw StateError('disk');
    accepted = true;
  }
}

class _Repo implements QuestionRepository {
  final String prefix;
  int loads = 0;
  _Repo(this.prefix);
  @override
  Future<List<Question>> loadAll() async {
    loads++;
    return List.generate(
        6,
        (i) => Question(
            id: '$prefix-$i',
            corpus: Corpus.gq,
            question: '$prefix question $i',
            answer: 'answer',
            packDate: '2013-04-27'));
  }
}

Future<void> _tap(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.tap(f);
  // Игровой таймер непрерывен: продвигаем кадры, не ждём его остановки.
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester t, MemoryEventLog log, _Consent consent,
    QuestionRepository adult,
    {QuestionRepository? standard}) async {
  await t.pumpWidget(JournalScope(
      log: log,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: ClassicChoiceScreen(
            repository: standard ?? _Repo('standard'),
            adultRepository: adult,
            consent: consent,
            tehnikaRepository: FakeTehniki()),
      )));
  await t.pumpAndSettle();
}

void main() {
  test('старый вопрос сохраняется только при явном adult-флаге', () {
    const q = Question(
        id: 'old',
        corpus: Corpus.gq,
        question: 'q',
        answer: 'a',
        packDate: '2013-04-27');
    final now = DateTime(2026, 11, 14);
    expect(selectRound([q], [], now), isEmpty);
    expect(selectRound([q], [], now, adult: true).single.id, 'old');
  });

  test('подтверждение сохраняется на диске и читается повторно', () async {
    final dir = await Directory.systemTemp.createTemp('adult-consent-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/consent');
    expect(await disk.isAccepted(file), isFalse);
    await disk.accept(file);
    expect(await disk.isAccepted(File(file.path)), isTrue);
    await file.writeAsString('broken');
    expect(await disk.isAccepted(file), isFalse);
  });

  testWidgets('отмена предупреждения не загружает вопросы 18+', (t) async {
    final adult = _Repo('adult');
    final consent = _Consent();
    await _pump(t, MemoryEventLog(), consent, adult);
    await _tap(t, 'classic-adult');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(adult.loads, 0);
    await t.tap(find.text('Отмена'));
    await t.pumpAndSettle();
    expect(consent.accepted, isFalse);
    expect(adult.loads, 0);
    expect(find.byKey(const Key('classic-standard')), findsOneWidget);
  });

  testWidgets('ошибка сохранения не открывает взрослый раунд', (t) async {
    final adult = _Repo('adult');
    await _pump(t, MemoryEventLog(), _Consent()..fail = true, adult);
    await _tap(t, 'classic-adult');
    await _tap(t, 'adult-confirm');
    expect(adult.loads, 0);
    expect(find.textContaining('Не удалось сохранить'), findsOneWidget);
  });

  testWidgets('18+: полный раунд, тег журнала и повторный вход', (t) async {
    final log = MemoryEventLog();
    final consent = _Consent();
    final adult = _Repo('adult');
    final standard = _Repo('standard');
    await _pump(t, log, consent, adult, standard: standard);
    await _tap(t, 'classic-adult');
    await _tap(t, 'adult-confirm');
    expect(consent.accepted, isTrue);
    expect(standard.loads, 0);
    for (var i = 0; i < 5; i++) {
      expect(find.textContaining('adult question'), findsOneWidget);
      await _tap(t, 'cycle-start');
      await _tap(t, 'cycle-ready');
      await _tap(t, 'cycle-answer-done');
      await _tap(t, 'cycle-verdict-taken');
    }
    expect(find.text('Взято 5 из 5'), findsOneWidget);
    final events =
        (await log.readAll()).events.whereType<AnswerEvent>().toList();
    expect(events.length, 5);
    expect(
        events.every(
            (e) => e.tags.contains('adult') && e.mode == GameMode.classic),
        isTrue);
    await t.pageBack();
    await t.pumpAndSettle();
    await _tap(t, 'classic-adult');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('cycle-start')), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await _tap(t, 'classic-standard');
    expect(standard.loads, 1);
    expect(adult.loads, 2);
  });

  testWidgets('настоящий ассет 18+ открывает цикл после согласия', (t) async {
    final repository =
        AssetQuestionRepository(assetPath: 'assets/adult_questions.json');
    await t.runAsync(repository.loadAll);
    await _pump(t, MemoryEventLog(), _Consent(), repository);
    await _tap(t, 'classic-adult');
    await _tap(t, 'adult-confirm');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('cycle-start')), findsOneWidget);
    await _tap(t, 'cycle-start');
    await _tap(t, 'cycle-ready');
    await _tap(t, 'cycle-answer-done');
    await _tap(t, 'cycle-verdict-missed');
    expect(find.byKey(const Key('cycle-start')), findsOneWidget);
  });
}
