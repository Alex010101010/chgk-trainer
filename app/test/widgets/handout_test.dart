import 'dart:convert';

import 'package:chgk_trainer/cycle/cycle_controller.dart';
import 'package:chgk_trainer/cycle/question_cycle.dart';
import 'package:chgk_trainer/journal/event.dart';
import 'package:chgk_trainer/model/question.dart';
import 'package:chgk_trainer/widgets/handout_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _withHandout = Question(
  id: 'ix-hal-9000-1',
  corpus: Corpus.bingo,
  question: 'текст вопроса с раздаткой',
  answer: 'HAL 9000.',
  acceptVariants: ['hal 9000'],
  comment: 'комментарий',
  theme: 'HAL 9000',
  handout: 'ix-hal-9000-1.jpg',
);

const _plain = Question(
  id: 'gq-1',
  corpus: Corpus.gq,
  question: 'текст вопроса без раздатки',
  answer: 'Уорхол.',
  acceptVariants: ['уорхол'],
  comment: 'комментарий',
);

/// Подменный PNG 64×64 вместо настоящего ассета: тест проверяет показ
/// раздатки, а не содержимое файла, и тянуть в него 4 МБ картинок незачем.
/// Размер не единица: виджет высотой в один пиксель не поймает тап.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x40,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x25, 0x0B, 0xE6, 0x89, 0x00, 0x00, 0x00,
  0x51, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0xED, 0xCF, 0x31, 0x0D, 0x00,
  0x30, 0x08, 0x00, 0x30, 0x98, 0x6A, 0x84, 0x21, 0x02, 0x59, 0x53, 0xC1,
  0x41, 0xD2, 0x3A, 0x68, 0x4E, 0x57, 0x5C, 0xF6, 0xE2, 0x38, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x81, 0x7D, 0x1F, 0x7F, 0xDE,
  0x02, 0x74, 0x80, 0x4C, 0xB8, 0x54, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Подменяет ТОЛЬКО файлы раздаток. Глобальная подмена канала ассетов ломает
/// чтение манифеста (`AssetManifest.bin` приходит PNG-байтами и падает с
/// «Message corrupted»), и полноэкранный просмотр не открывается вовсе.
void _stubHandouts(WidgetTester tester, Uint8List bytes) {
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key.startsWith(kHandoutDir)) return bytes.buffer.asByteData();
      // Пустой, но валидный манифест: в тестах собранного бандла нет, а
      // `Image.asset` читает манифест прежде самой картинки.
      if (key == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(<String, Object>{});
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', null));
}

Future<void> _pump(WidgetTester tester, Question q) async {
  _stubHandouts(tester, _png);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: QuestionCycle(
        question: q,
        config: const CycleConfig(mode: GameMode.bingo),
        onFinished: (_) {},
      ),
    ),
  ));
  // Без settle картинка ещё не декодирована, виджет нулевой высоты и тап по
  // нему промахивается мимо собственной цели.
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('раздатка видна на чтении, минуте, записи и раскрытии',
      (tester) async {
    // Раздатку выдают до отсчёта и не отбирают: на живой игре она лежит перед
    // командой всю минуту и остаётся на столе при разборе.
    await _pump(tester, _withHandout);
    expect(find.byType(HandoutImage), findsOneWidget);

    await _tap(tester, 'cycle-start');
    expect(find.byType(HandoutImage), findsOneWidget);

    await _tap(tester, 'cycle-ready');
    expect(find.byType(HandoutImage), findsOneWidget);

    await _tap(tester, 'cycle-answer-done');
    expect(find.text('комментарий'), findsOneWidget);
    expect(find.byType(HandoutImage), findsOneWidget);
  });

  testWidgets('у вопроса без раздатки картинки нет ни на одной фазе',
      (tester) async {
    await _pump(tester, _plain);
    expect(find.byType(HandoutImage), findsNothing);
    await _tap(tester, 'cycle-start');
    await _tap(tester, 'cycle-ready');
    await _tap(tester, 'cycle-answer-done');
    expect(find.byType(HandoutImage), findsNothing);
  });

  testWidgets('тап открывает раздатку на весь экран и закрывает', (tester) async {
    // Схема 1080×946 и полоса 600×59 в ширину телефона не читаются, а
    // неразличимая раздатка делает вопрос невзятым не по вине игрока.
    await _pump(tester, _withHandout);
    await _tap(tester, 'handout-open');
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await _tap(tester, 'handout-close');
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(HandoutImage), findsOneWidget);
  });

  testWidgets('пропавший файл — сообщение, а не пустое место', (tester) async {
    // В норме сюда не попасть: сборщик ассета не собирается без файла. Но если
    // попали — игрок должен понимать, что вопрос не берётся не из-за него.
    _stubHandouts(tester, Uint8List.fromList(const [1, 2, 3]));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HandoutImage(file: 'нет-такого.jpg')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('handout-missing')), findsOneWidget);
  });
}
