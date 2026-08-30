/// Конфигурация самообновления APK (OTA).
///
/// Приложение раздаётся не через маркет, а сборкой из CI. Чтобы не копировать
/// APK на телефон руками после каждой правки, оно само проверяет последний
/// GitHub Release и предлагает установить свежую версию.

/// Манифест самой свежей сборки. Адрес стабильный: `releases/latest/download/`
/// всегда отдаёт ассет из последнего релиза, без токенов и без знания тега.
const String kAppManifestUrl =
    'https://github.com/Alex010101010/chgk-trainer/releases/latest/download/app_manifest.json';

/// Таймаут проверки манифеста. Офлайн — молча остаёмся на установленной версии.
const Duration kOtaTimeout = Duration(seconds: 12);

/// Таймаут скачивания самого APK — файл на десятки мегабайт, нужен запас.
const Duration kApkDownloadTimeout = Duration(minutes: 5);
