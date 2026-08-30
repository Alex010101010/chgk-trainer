import 'dart:io';
import 'dart:math';

import 'package:chgk_trainer/model/panda_line.dart';
import 'package:chgk_trainer/panda/panda_poses.dart';
import 'package:chgk_trainer/panda/panda_voice.dart';
import 'package:chgk_trainer/widgets/panda_says.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _moments = [
  PandaMoment(
    id: PandaMoments.took,
    name: 'Взял',
    lines: ['подколка'],
    rare: ['искренняя'],
  ),
];

Widget _wrap(Widget w, {PandaVoice? voice}) {
  final app = MaterialApp(home: Scaffold(body: w));
  return voice == null ? app : PandaScope(voice: voice, child: app);
}

String? _poseAsset(WidgetTester tester) {
  final found = find.byKey(const Key('panda-pose'));
  if (found.evaluate().isEmpty) return null;
  final image = tester.widget<Image>(found).image;
  return (image as AssetImage).assetName;
}

void main() {
  testWidgets('панда видна и когда молчит', (tester) async {
    await tester.pumpWidget(_wrap(
      const PandaSays(moment: PandaMoments.took),
      voice: PandaVoice.silent(),
    ));
    await tester.pump();

    // Молчание — самостоятельная реакция, а не отсутствие панды: если бы
    // вместе с репликой пропадала поза, экран прыгал бы на каждом вердикте.
    expect(_poseAsset(tester), contains('panda_took'));
    expect(find.byKey(const Key('panda-line')), findsNothing);
  });

  testWidgets('редкая реплика идёт с искренним лицом', (tester) async {
    final voice = PandaVoice(
      _moments,
      random: Random(1),
      speakPercent: 100,
      rareOneIn: 1, // редкая выпадает всегда
    );
    await tester.pumpWidget(
        _wrap(const PandaSays(moment: PandaMoments.took), voice: voice));
    await tester.pump();

    expect(_poseAsset(tester), PandaPoses.sincere);
  });

  testWidgets('обычная реплика идёт с позой момента', (tester) async {
    final voice = PandaVoice(
      _moments,
      random: Random(1),
      speakPercent: 100,
      rareOneIn: 1000000, // редкая не выпадет
    );
    await tester.pumpWidget(
        _wrap(const PandaSays(moment: PandaMoments.took), voice: voice));
    await tester.pump();

    expect(_poseAsset(tester), contains('panda_took'));
  });

  testWidgets('момента без арта хватает, чтобы не упасть', (tester) async {
    await tester.pumpWidget(_wrap(
      const PandaSays(moment: 'weakmap.show'),
      voice: PandaVoice.silent(),
    ));
    await tester.pump();

    expect(_poseAsset(tester), isNull);
    expect(tester.takeException(), isNull);
  });

  test('у каждого подключённого момента файл позы лежит на диске', () {
    final poses = {
      for (final m in const [
        PandaMoments.took,
        PandaMoments.almost,
        PandaMoments.missed,
        PandaMoments.roundEnd,
      ])
        m: PandaPoses.forMoment(m),
      'rare': PandaPoses.sincere,
    };
    // Опечатка в имени файла даёт пустое место на экране и никакой ошибки —
    // errorBuilder её проглотит. Ловим здесь, а не глазами на телефоне.
    poses.forEach((moment, asset) {
      expect(asset, isNotNull, reason: 'у момента $moment нет позы');
      expect(File(asset!).existsSync(), isTrue, reason: 'нет файла $asset');
    });
  });
}
