import 'package:flutter/widgets.dart';

import 'handout_store_io.dart'
    if (dart.library.js_interop) 'handout_store_web.dart';

/// Откуда берутся раздатки (T30). В APK их нет: 1300 картинок весят ~90 МБ,
/// и каждое обновление по кнопке тянуло бы их заново. Они лежат на GitHub
/// Pages рядом с веб-превью — CI кладёт туда `app/assets/handouts/`.
const String kHandoutBaseUrl =
    'https://alex010101010.github.io/chgk-trainer/handouts';

/// Картинка раздатки по имени файла из ассета вопросов.
abstract class HandoutStore {
  /// Картинка, готовая к показу. На телефоне — файл из кэша, при первом
  /// показе скачанный; падает, если сети нет, а в кэше пусто.
  Future<ImageProvider> resolve(String file);

  /// Подменяется в тестах: настоящий store ходит в сеть.
  static HandoutStore instance = createHandoutStore(kHandoutBaseUrl);

  /// Скачать заранее, не дожидаясь показа. Ошибку глотает: докачка —
  /// услуга, а не обязанность, показ всё равно попробует ещё раз.
  static void prefetch(Iterable<String?> files) {
    for (final f in files) {
      if (f != null) instance.resolve(f).ignore();
    }
  }
}
