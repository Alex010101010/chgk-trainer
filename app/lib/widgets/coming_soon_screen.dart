import 'package:flutter/material.dart';

class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const ComingSoonScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('Скоро',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
