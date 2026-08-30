import 'package:flutter/material.dart';

import '../panda/panda_poses.dart';
import '../panda/panda_voice.dart';
import 'panda_bubble.dart';

/// Панда и её реплика: поза внизу слева, пузырь над ней.
///
/// Порядок именно такой, потому что хвостик пузыря смотрит вниз-влево — он
/// должен указывать на того, кто говорит.
///
/// **Поза показывается и в молчании.** Голос молчит примерно в половине
/// моментов, и если бы вместе с репликой исчезала картинка, экран бы прыгал,
/// а молчание читалось как «панды тут нет». Она есть — просто ничего не
/// сказала, и это самостоятельная реакция.
class PandaSays extends StatefulWidget {
  final String moment;
  final Map<String, String> vars;

  /// Высота позы. На глаз: панда должна быть заметна, но не спорить с
  /// текстом вопроса за внимание.
  final double size;

  const PandaSays({
    super.key,
    required this.moment,
    this.vars = const {},
    this.size = 116,
  });

  @override
  State<PandaSays> createState() => _PandaSaysState();
}

class _PandaSaysState extends State<PandaSays> {
  PandaSpeech? _speech;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Голос спрашиваем ровно один раз и здесь, а не в пузыре: поза должна
    // соответствовать той же самой реплике, что показана.
    if (_asked) return;
    _asked = true;
    _speech =
        PandaScope.maybeOf(context)?.speakFor(widget.moment, vars: widget.vars);
  }

  @override
  Widget build(BuildContext context) {
    final speech = _speech;
    // Искренняя реплика идёт со своим лицом. Без этого единственная поза
    // набора с настоящей улыбкой не показалась бы никогда.
    final pose = speech != null && speech.rare
        ? PandaPoses.sincere
        : PandaPoses.forMoment(widget.moment);
    if (pose == null && speech == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (speech != null)
          PandaBubble(
            moment: widget.moment,
            vars: widget.vars,
            speech: speech,
          ),
        if (pose != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Image.asset(
              pose,
              key: const Key('panda-pose'),
              height: widget.size,
              filterQuality: FilterQuality.medium,
              // Ассет не доехал — показываем пустоту, а не красный экран:
              // отсутствие панды игрока не останавливает.
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}
