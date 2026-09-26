/// Карточка факта (T15): лицо → оборот. Собирается
/// `scripts/structure_facts.py` из листов-пар таблицы фактов.
class FactCard {
  final String id;
  final String deck;

  /// Вопрос к лицу карточки — «Кто прототип?», «Где проходили?». Один на лист
  /// таблицы: в «Разном» у каждой карточки свой.
  final String ask;
  final String front;
  final String back;
  final String? note;

  /// Картинка на Pages рядом с раздатками, `fact-<исходник>.jpg`.
  final String? image;

  const FactCard({
    required this.id,
    required this.deck,
    required this.ask,
    required this.front,
    required this.back,
    this.note,
    this.image,
  });

  static FactCard? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final deck = json['deck'];
    final ask = json['ask'];
    final front = json['front'];
    final back = json['back'];
    if (id is! String || deck is! String || ask is! String) return null;
    if (front is! String || back is! String || front.isEmpty || back.isEmpty) {
      return null;
    }
    return FactCard(
      id: id,
      deck: deck,
      ask: ask,
      front: front,
      back: back,
      note: json['note'] is String ? json['note'] as String : null,
      image: json['image'] is String ? json['image'] as String : null,
    );
  }
}

class FactDeck {
  final String id;
  final String title;

  const FactDeck({required this.id, required this.title});
}

/// Всё содержимое ассета фактов: колоды в порядке показа и карточки.
class FactBook {
  final List<FactDeck> decks;
  final List<FactCard> cards;

  const FactBook({required this.decks, required this.cards});

  List<FactCard> cardsOf(String deck) =>
      cards.where((c) => c.deck == deck).toList();
}
