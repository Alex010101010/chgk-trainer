import 'package:flutter/widgets.dart';

import 'handout_store.dart';

/// В браузере кэширует сам браузер — достаточно адреса.
HandoutStore createHandoutStore(String baseUrl) => _WebHandoutStore(baseUrl);

class _WebHandoutStore implements HandoutStore {
  final String baseUrl;
  _WebHandoutStore(this.baseUrl);

  @override
  Future<ImageProvider> resolve(String file) async =>
      NetworkImage('$baseUrl/$file');
}
