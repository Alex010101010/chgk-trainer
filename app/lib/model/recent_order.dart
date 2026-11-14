import 'dart:math';

bool withinTenYears(String? date, DateTime now) {
  // Совместимость со старыми записями/фикстурами. Новая сборка всегда
  // проверяет дату gq-пакета до включения вопроса в ассет.
  if (date == null) return true;
  final played = DateTime.tryParse(date);
  if (played == null) return false;
  final day = DateTime(now.year, now.month, now.day);
  final lower = DateTime(now.year - 10, now.month,
      min(now.day, DateTime(now.year - 10, now.month + 1, 0).day));
  return !played.isBefore(lower) && !played.isAfter(day);
}

/// Новый пакет получает больший вес, но старые внутри десяти лет тоже играются.
double freshnessWeight(String? date, DateTime now) {
  final played = DateTime.tryParse(date ?? '');
  if (played == null) return 1;
  final age = max(0, now.difference(played).inDays) / 365.25;
  return 1 / (1 + age);
}

List<T> preferRecent<T>(
    Iterable<T> items, String? Function(T) date, DateTime now, Random random) {
  final ranked = [
    for (final item in items)
      (
        item: item,
        score: -log(1 - random.nextDouble()) / freshnessWeight(date(item), now)
      ),
  ]..sort((a, b) => a.score.compareTo(b.score));
  return [for (final r in ranked) r.item];
}
