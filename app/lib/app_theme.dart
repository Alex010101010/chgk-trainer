import 'package:flutter/material.dart';

/// Тон приложения (T8).
///
/// Три цвета и не больше: чёрно-белая база панды, тёплое золото как
/// единственный акцент (отсылка к совам-трофеям) и тёмно-зелёное сукно
/// игрового стола как поддерживающий. Золото означает действие и удачу,
/// сукно — подложку; если акцентов станет два, «взял вопрос» перестанет
/// читаться с одного взгляда.
abstract final class PandaPalette {
  /// Золото — акцент. Кнопка действия, «взял», прогресс.
  static const gold = Color(0xFFE3B457);

  /// Текст и иконки поверх золота. Не чёрный: на тёплом фоне чёрный звенит.
  static const goldInk = Color(0xFF23190A);

  /// Золото, приглушённое до читаемого контраста на белой бумаге.
  static const goldOnPaper = Color(0xFF8A6A22);

  /// Сукно — поддерживающий цвет, не акцент.
  static const cloth = Color(0xFF23503F);
  static const clothLight = Color(0xFF7FBFA3);
  static const clothDeep = Color(0xFF12281F);

  /// База панды: чёрное и белое, оба тёплые — холодный серый рядом с
  /// золотом выглядит грязным.
  static const ink = Color(0xFF1A1815);
  static const paper = Color(0xFFF6F3EC);

  /// Текст на тёмном фоне: не белый. Чистый белый на почти чёрном
  /// «раздувается» по краям букв — от этого и режет глаз.
  static const paperDim = Color(0xFFE2DED4);

  /// Металлический блеск: тёмное золото → узкий светлый блик в верхней
  /// трети → спад к тёмному низу. Плоская заливка выглядит жёлтым
  /// пластиком; блик делает её металлом.
  ///
  /// Градиент вертикальный, а не диагональный, по двум причинам: так свет
  /// падает сверху, как в жизни, и вид не зависит от ширины — на широкой
  /// кнопке диагональ растягивала блик в засвет левой половины.
  static const goldSheenDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFCE9C36),
      Color(0xFFF8E3AC),
      Color(0xFFDBAA4A),
      Color(0xFF9C6E1C),
    ],
    stops: [0.0, 0.16, 0.52, 1.0],
  );

  /// То же на светлой теме: золото глубже, чтобы белый текст поверх читался.
  static const goldSheenLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF7C5C19),
      Color(0xFFAE8B38),
      Color(0xFF8A6A22),
      Color(0xFF57400F),
    ],
    stops: [0.0, 0.16, 0.52, 1.0],
  );
}

/// Единственный шрифт приложения: округлый гуманистический sans.
///
/// Серифа для текста вопроса нет намеренно. Первая версия темы его ставила —
/// на живом экране засечки резали глаз, и от них отказались: одно скруглённое
/// семейство на всё спокойнее и даёт тот же тон, что у тренажёров вроде
/// Duolingo. Вопрос отличается от интерфейса кеглем и воздухом, а не
/// рисунком букв.
const _uiFont = 'Nunito';

/// Шкала кеглей: 13 · 15 · 17 · 20 · 24 · 30.
///
/// Шесть ступеней на всё приложение, шаг примерно в четверть. До этого часть
/// текста брала размеры из темы, а часть — зашитые числа (18, 20, 22), и
/// соседние строки прыгали без причины. Правило простое: **в экранах нет
/// `fontSize`**, есть слот шкалы.
///
/// | слот | кегль | чем набрано |
/// |---|---|---|
/// | `displaySmall` | 30 | название приложения |
/// | `headlineSmall` | 24 | заголовок экрана, название приёма |
/// | `titleLarge` | 20 | заголовок карточки режима, «Скоро» |
/// | `titleMedium` | 17 | шапка цикла, выделенная строка ответа |
/// | `bodyLarge` | 17 | основной читаемый текст |
/// | `bodyMedium` | 15 | второстепенный текст, комментарий |
/// | `labelLarge` | 13 | метки над значениями: «Ответ», «Источник» |
const _scale = TextTheme(
  displaySmall:
      TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.2),
  headlineSmall:
      TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25),
  titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
  titleMedium:
      TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35),
  bodyLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, height: 1.5),
  bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45),
  bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.4),
  labelLarge:
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.6),
  labelMedium:
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
);

/// Текст вопроса — на ступень выше основного текста и просторнее его: от
/// того, насколько легко он читается, зависит, сколько минуты уйдёт на
/// чтение вместо думанья.
TextStyle questionTextStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontSize: 20,
          height: 1.55,
        );

/// Название приложения, набранное металлическим золотом. Единственное место,
/// где блеск лежит на самом тексте: это имя, а не интерфейс.
class PandaWordmark extends StatelessWidget {
  const PandaWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = theme.brightness == Brightness.dark
        ? PandaPalette.goldSheenDark
        : PandaPalette.goldSheenLight;
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text('Панда будет?', style: theme.textTheme.displaySmall),
    );
  }
}

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: PandaPalette.gold,
  onPrimary: PandaPalette.goldInk,
  primaryContainer: Color(0xFF4A3812),
  onPrimaryContainer: Color(0xFFF6DFAE),
  secondary: PandaPalette.clothLight,
  onSecondary: PandaPalette.clothDeep,
  secondaryContainer: PandaPalette.cloth,
  onSecondaryContainer: Color(0xFFCDE9DC),
  error: Color(0xFFE68A7E),
  onError: Color(0xFF3A0F0A),
  errorContainer: Color(0xFF5A211A),
  onErrorContainer: Color(0xFFFFD9D3),
  surface: Color(0xFF1B201E),
  onSurface: PandaPalette.paperDim,
  surfaceContainerHighest: Color(0xFF232C28),
  onSurfaceVariant: Color(0xFFAFB5B0),
  outline: Color(0xFF6B736E),
  outlineVariant: Color(0xFF39443F),
);

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: PandaPalette.goldOnPaper,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFF3E2B8),
  onPrimaryContainer: Color(0xFF2C2007),
  secondary: PandaPalette.cloth,
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFCDE9DC),
  onSecondaryContainer: PandaPalette.clothDeep,
  error: Color(0xFFA3312A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF9DEDA),
  onErrorContainer: Color(0xFF410E0A),
  surface: PandaPalette.paper,
  onSurface: PandaPalette.ink,
  surfaceContainerHighest: Color(0xFFE7E3D9),
  onSurfaceVariant: Color(0xFF4A4741),
  outline: Color(0xFF8C877D),
  outlineVariant: Color(0xFFD3CEC3),
);

ThemeData _themeFrom(ColorScheme scheme, Color scaffold) {
  final sheen = scheme.brightness == Brightness.dark
      ? PandaPalette.goldSheenDark
      : PandaPalette.goldSheenLight;

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _uiFont,
    scaffoldBackgroundColor: scaffold,
    // Цвет задаётся здесь, а не в слотах шкалы: шкала описывает размеры и
    // веса, а цвет у светлой и тёмной темы разный.
    textTheme: _scale.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    // Тени на тёмном фоне не видны, поэтому карточку от фона отделяет
    // контур: без него экран читается как одна чёрная плита.
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    // Иконка по умолчанию — золотом: на главном экране это единственное
    // цветное пятно, и без него четыре режима выглядят одинаковыми плашками.
    iconTheme: IconThemeData(color: scheme.primary),
    listTileTheme: ListTileThemeData(iconColor: scheme.primary),
    // Скругление во всём хроме — та же «мягкая форма при контрастном
    // характере», что и у самой панды.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: _uiFont,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ).copyWith(
        // Плоская заливка золотом выглядит пластиком. backgroundBuilder кладёт
        // градиент между Material кнопки и её текстом — форма, обрезка и рябь
        // остаются родные, красить вручную ничего не надо.
        backgroundBuilder: (context, states, child) {
          if (states.contains(WidgetState.disabled)) {
            return child ?? const SizedBox.shrink();
          }
          return DecoratedBox(
            decoration: BoxDecoration(gradient: sheen),
            child: child,
          );
        },
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: _uiFont,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

/// Основная тема. Живые квизы играются вечером — приложение открывают
/// в тех же условиях, и светить в лицо белым листом незачем.
ThemeData buildDarkTheme() => _themeFrom(_darkScheme, const Color(0xFF121615));

/// Светлая — альтернатива. Переключателя пока нет: он появится вместе
/// с экраном настроек, а до тех пор тема собрана, но не выбирается.
ThemeData buildLightTheme() => _themeFrom(_lightScheme, PandaPalette.paper);
