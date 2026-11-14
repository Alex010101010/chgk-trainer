import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Матовое оформление игрового содержимого; меню и профиль не меняет.
class PlaySurface extends StatelessWidget {
  final Widget child;
  const PlaySurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: base.filledButtonTheme.style?.copyWith(
            backgroundColor: const WidgetStatePropertyAll(PandaPalette.gold),
            foregroundColor: const WidgetStatePropertyAll(PandaPalette.goldInk),
            backgroundBuilder: (context, states, child) =>
                child ?? const SizedBox.shrink(),
          ),
        ),
      ),
      child: ColoredBox(
        color: base.brightness == Brightness.dark
            ? const Color(0xFF121B17)
            : base.colorScheme.surface,
        child: child,
      ),
    );
  }
}
