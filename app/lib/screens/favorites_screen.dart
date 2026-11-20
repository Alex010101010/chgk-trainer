import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../journal/favorites.dart';
import '../journal/journal_scope.dart';
import '../widgets/favorite_button.dart';
import '../widgets/handout_image.dart';
import '../widgets/handout_text.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<FavoriteQuestion>? _items;
  String? _error;
  String _query = '';
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final read = await JournalScope.of(context).readAll();
      if (mounted) setState(() => _items = favoriteQuestions(read.events));
    } catch (e) {
      debugPrint('[favorites] read failed: $e');
      if (mounted) setState(() => _error = 'Не удалось открыть избранное.');
    }
  }

  String _normal(String s) => s.toLowerCase().replaceAll('ё', 'е');

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final query = _normal(_query.trim());
    final found = items
        ?.where((f) => _normal([
              f.question.question,
              f.question.answer,
              f.question.comment ?? '',
              f.origin,
              f.explanation ?? '',
              f.question.author ?? '',
            ].join(' '))
                .contains(query))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Избранное')),
      body: SafeArea(
          child: _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ]))
              : items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(
                          child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'Пока нет избранных вопросов. Нажми «В избранное» в разборе вопроса.'),
                        ))
                      : Column(children: [
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: TextField(
                                key: const Key('favorites-search'),
                                decoration: const InputDecoration(
                                    labelText:
                                        'Поиск по вопросу, ответу и разбору',
                                    prefixIcon: Icon(Icons.search)),
                                onChanged: (value) =>
                                    setState(() => _query = value),
                              )),
                          Expanded(
                              child: found!.isEmpty
                                  ? const Center(
                                      child: Text('Ничего не найдено'))
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 16),
                                      itemCount: found.length,
                                      itemBuilder: (context, index) {
                                        final item = found[index];
                                        return Card(
                                            child: ListTile(
                                          key: Key(
                                              'favorite-open-${item.question.id}'),
                                          title: Text(item.question.question,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis),
                                          subtitle: item.origin.isEmpty
                                              ? null
                                              : Text(item.origin),
                                          trailing:
                                              const Icon(Icons.chevron_right),
                                          onTap: () async {
                                            await Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                    builder: (_) =>
                                                        FavoriteQuestionScreen(
                                                            item: item)));
                                            if (mounted) _load();
                                          },
                                        ));
                                      },
                                    )),
                        ])),
    );
  }
}

class FavoriteQuestionScreen extends StatelessWidget {
  final FavoriteQuestion item;
  const FavoriteQuestionScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final q = item.question;
    Widget section(String title, String? value) =>
        value == null || value.trim().isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    SelectableText(value)
                  ],
                ));
    return Scaffold(
      appBar: AppBar(title: const Text('Разбор')),
      body: SafeArea(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (item.origin.isNotEmpty) Text(item.origin),
          const SizedBox(height: 12),
          if (q.handout case final file?) HandoutImage(file: file),
          if (q.handoutText case final text?) HandoutText(text),
          SelectableText(q.question, style: questionTextStyle(context)),
          section('Ответ', q.answer),
          section('Зачёт', q.acceptance),
          section('Почему так', q.comment),
          section('Разбор приёма', item.explanation),
          section('Источники', q.sources.join('\n')),
          section('Автор', q.author),
          const SizedBox(height: 20),
          FavoriteButton(
              question: q, origin: item.origin, explanation: item.explanation),
        ],
      )),
    );
  }
}
