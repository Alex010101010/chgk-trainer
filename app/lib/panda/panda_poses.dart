import 'panda_voice.dart';

/// Позы панды: какой файл показывать в каком моменте.
///
/// Отдельно от [PandaMoments], потому что связь не один-к-одному: у
/// искренней реплики своя поза независимо от момента, а часть поз лежит в
/// ассетах без момента — их экраны ещё не написаны.
abstract final class PandaPoses {
  static const _dir = 'assets/panda';

  /// Лицо для редкой искренней реплики. Единственная поза набора без
  /// брови-приговора и с настоящей улыбкой; показывается несколько раз за
  /// всё время, и продаёт её только редкость.
  static const sincere = '$_dir/panda_sincere.png';

  /// Поза для момента или `null`, если под момент арта нет.
  static String? forMoment(String momentId) => switch (momentId) {
        PandaMoments.took => '$_dir/panda_took.png',
        PandaMoments.almost => '$_dir/panda_almost.png',
        // Единственная поза, где панда не язвит: на промахе бровь-приговор
        // снята. Насмешка ровно в секунду неудачи — то, чего T8 запрещает.
        PandaMoments.missed => '$_dir/panda_missed.png',
        PandaMoments.roundEnd => '$_dir/panda_clap.png',
        _ => null,
      };

  // В ассетах лежат ещё neutral, facepalm, stop, notes, waiting и thumbs —
  // под моменты, для которых экранов пока нет (T9, T4b). Заводить им строки
  // здесь значит писать мёртвый маппинг: он приедет вместе с экранами.
}
