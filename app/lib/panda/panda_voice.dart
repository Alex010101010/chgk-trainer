import 'dart:math';

import 'package:flutter/widgets.dart';

import '../model/panda_line.dart';

/// Идентификаторы моментов. Строками их не разбрасываем: опечатка в строке
/// даёт молчание, которое выглядит как «панда просто промолчала» и не
/// находится ни тестом, ни глазами.
abstract final class PandaMoments {
  static const took = 'verdict.took';
  static const almost = 'verdict.almost';
  static const missed = 'verdict.missed';
  static const roundEnd = 'round.end';
  // Ниже — моменты, для которых банк написан, а экранов ещё нет:
  // weakmap.show (T4b), streak.alive / streak.broken (T9), loading, empty.
}

/// Голос панды: выбирает реплику на момент или молчит.
///
/// Три правила из T8, все три здесь:
/// - **молчание** — реплика показывается примерно в половине моментов.
///   Восемьдесят строк, произносимых каждый раз, выговариваются за неделю;
/// - **бюджет искренности** — редкая строка выпадает примерно раз из
///   тридцати;
/// - **без повтора подряд** — та же строка не идёт вторым разом в том же
///   моменте.
class PandaVoice {
  final Map<String, PandaMoment> _moments;
  final Random _random;

  /// Вероятность подать голос, в процентах.
  final int speakPercent;

  /// Знаменатель бюджета искренности: одна редкая реплика из N показов.
  final int rareOneIn;

  final Map<String, String> _lastByMoment = {};

  PandaVoice(
    List<PandaMoment> moments, {
    Random? random,
    this.speakPercent = 50,
    this.rareOneIn = 30,
  })  : _moments = {for (final m in moments) m.id: m},
        _random = random ?? Random();

  /// Молчащий голос: банк не загрузился. Панда просто не подаёт реплик —
  /// это не ошибка приложения и показывать её игроку незачем.
  PandaVoice.silent()
      : _moments = const {},
        _random = Random(),
        speakPercent = 0,
        rareOneIn = 30;

  /// Реплика на момент или `null` — молчание.
  ///
  /// `vars` подставляется в фигурные скобки: `{n}` — число, `{приём}` —
  /// название приёма. Строка с неподставленной переменной не показывается:
  /// «{n} дней подряд» на экране хуже, чем молчание.
  String? lineFor(String momentId, {Map<String, String> vars = const {}}) {
    final moment = _moments[momentId];
    if (moment == null) return null;
    if (_random.nextInt(100) >= speakPercent) return null;

    final useRare = moment.rare.isNotEmpty && _random.nextInt(rareOneIn) == 0;
    final pool = useRare ? moment.rare : moment.lines;
    if (pool.isEmpty) return null;

    final last = _lastByMoment[momentId];
    final fresh = pool.length > 1
        ? (pool.where((l) => l != last).toList()..shuffle(_random))
        : pool;
    final chosen = fresh[_random.nextInt(fresh.length)];
    _lastByMoment[momentId] = chosen;

    final filled = _fill(chosen, vars);
    return filled != null && filled.contains('{') ? null : filled;
  }

  String? _fill(String line, Map<String, String> vars) {
    var out = line;
    vars.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }
}

/// Голос на всё приложение. Через скоуп, а не через конструкторы: реплика
/// нужна в глубине цикла вопроса, и протаскивать её пятью параметрами
/// значит менять пять сигнатур ради одной строки текста.
class PandaScope extends InheritedWidget {
  final PandaVoice voice;

  const PandaScope({super.key, required this.voice, required super.child});

  /// Возвращает `null`, если скоупа нет. Так экран без голоса (и любой
  /// существующий тест) продолжает работать — панда просто молчит.
  static PandaVoice? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PandaScope>()
      ?.voice;

  @override
  bool updateShouldNotify(PandaScope oldWidget) => oldWidget.voice != voice;
}
