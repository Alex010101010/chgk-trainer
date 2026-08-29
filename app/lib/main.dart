import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ChgkTrainerApp());
}

class ChgkTrainerApp extends StatelessWidget {
  const ChgkTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ЧГК-тренажёр',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
