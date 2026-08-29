/// Подсказка самооценке. Матчер только предзаполняет кнопку, решает игрок:
/// `acceptance` заполнен у 28% вопросов, поэтому промах здесь — норма.
enum MatchHint { taken, almost, none }

final RegExp _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Нижний регистр, `ё → е`, вся пунктуация (включая внешние кавычки) в пробел,
/// пробелы схлопнуты. Без этого «Уорхол.» не совпадёт с вариантом «уорхол».
String normalizeAnswer(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(_notLetterOrDigit, ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  final cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    prev = List<int>.from(cur);
  }
  return prev[b.length];
}

/// Минимальная длина ответа, при которой вхождение подстроки что-то значит.
/// Без порога «а» — подстрока почти любого варианта, и каждый пустяковый
/// ответ молча становился бы «почти».
const int _kMinSubstringLen = 4;

MatchHint matchAnswer(String userAnswer, List<String> acceptVariants) {
  final user = normalizeAnswer(userAnswer);
  // Пустая версия не матчится ни с чем и никогда: `''.contains` иначе даёт
  // «почти» на каждом вопросе.
  if (user.isEmpty) return MatchHint.none;

  final variants = acceptVariants
      .map(normalizeAnswer)
      .where((v) => v.isNotEmpty)
      .toList();

  // Точный матч и опечатка ищутся по всем вариантам до того, как хоть один
  // вариант успеет дать «почти» вхождением.
  for (final v in variants) {
    if (v == user) return MatchHint.taken;
    if (levenshtein(user, v) <= (v.length ~/ 6).clamp(1, v.length)) {
      return MatchHint.taken;
    }
  }

  if (user.length >= _kMinSubstringLen) {
    for (final v in variants) {
      if (user.contains(v) || v.contains(user)) return MatchHint.almost;
    }
  }

  return MatchHint.none;
}
