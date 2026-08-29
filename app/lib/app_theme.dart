import 'package:flutter/material.dart';

ThemeData buildTheme() {
  const seed = Color(0xFF6A1B9A);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: seed),
    scaffoldBackgroundColor: const Color(0xFFF7F7F5),
  );
}
