import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

/// Только метаданные установленного приложения, без манифеста обновления и сети.
class InstalledVersion extends StatefulWidget {
  const InstalledVersion({super.key});
  @override
  State<InstalledVersion> createState() => _InstalledVersionState();
}

class _InstalledVersionState extends State<InstalledVersion> {
  Future<PackageInfo>? _info;
  @override
  void initState() {
    super.initState();
    if (!kIsWeb)
      _info = PackageInfo.fromPlatform().timeout(const Duration(seconds: 3));
  }

  @override
  Widget build(BuildContext context) => kIsWeb
      ? const Text('Веб-превью', key: Key('installed-version'))
      : FutureBuilder<PackageInfo>(
          future: _info,
          builder: (context, snapshot) {
            final info = snapshot.data;
            return Text(
              info == null
                  ? snapshot.hasError
                      ? 'Версия недоступна'
                      : 'Читаю версию…'
                  : 'Версия ${info.version} · сборка ${info.buildNumber}',
              key: const Key('installed-version'),
              style: Theme.of(context).textTheme.bodySmall,
            );
          },
        );
}
