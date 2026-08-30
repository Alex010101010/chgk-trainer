/// Момент, в который панда может подать голос: набор взаимозаменяемых реплик
/// плюс отдельный редкий пул искренних.
///
/// Искренние лежат отдельно не для красоты. По T8 бюджет искренности — одна
/// реплика из ~30: если панда добра постоянно, доброта ничего не стоит и
/// персонаж превращается в мотиватора, которым он не является.
class PandaMoment {
  final String id;
  final String name;
  final List<String> lines;
  final List<String> rare;

  const PandaMoment({
    required this.id,
    required this.name,
    required this.lines,
    required this.rare,
  });

  /// Возвращает `null` на кривой записи вместо того, чтобы падать: одна
  /// испорченная строка в банке не должна лишать голоса остальные моменты.
  static PandaMoment? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final lines = _strings(json['lines']);
    final rare = _strings(json['rare']);
    if (lines.isEmpty && rare.isEmpty) return null;
    return PandaMoment(id: id, name: name, lines: lines, rare: rare);
  }

  static List<String> _strings(Object? v) => v is List
      ? v.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
      : const [];
}
