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
}

/// Единственный шрифт приложения: округлый гуманистический sans.
///
/// Серифа для текста вопроса нет намеренно. Первая версия темы его ставила —
/// на живом экране засечки резали глаз, и от них отказались: одно скруглённое
/// семейство на всё спокойнее и даёт тот же тон, что у тренажёров вроде
/// Duolingo. Вопрос отличается от интерфейса кеглем и воздухом, а не
/// рисунком букв.
const _uiFont = 'Nunito';

/// Текст вопроса — крупнее и просторнее интерфейса: от того, насколько легко
/// он читается, зависит, сколько минуты уйдёт на чтение вместо думанья.
TextStyle questionTextStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontSize: 19,
          height: 1.55,
        );

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
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _uiFont,
    scaffoldBackgroundColor: scaffold,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
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
    // Скругление во всём хроме — то же «мягкая форма при контрастном
    // характере», что и у самой панды.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: _uiFont,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: _uiFont,
          fontSize: 16,
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
