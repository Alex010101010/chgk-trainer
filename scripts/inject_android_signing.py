#!/usr/bin/env python3
"""Впрыск release-подписи в сгенерённый `flutter create` android-проект.

Платформенная папка android/ не хранится в git — CI генерит её на лету, поэтому
build.gradle(.kts) каждый раз создаётся заново с debug-ключом. Этот скрипт после
`flutter create` правит build.gradle модуля app, чтобы release-сборка подписывалась
нашим keystore (параметры читаются из android/key.properties, который CI пишет из
секретов).

Поддержаны оба DSL: Kotlin (build.gradle.kts, текущий дефолт Flutter) и Groovy.
Идемпотентен: повторный запуск ничего не дублирует. Падает с ошибкой, если не нашёл
ссылку на debug-подпись (значит шаблон Flutter изменился — лучше сломать сборку явно,
чем молча отгрузить debug-подписанный APK).

Использование: python3 scripts/inject_android_signing.py app/android
"""
import sys
import pathlib


def inject_kts(f: pathlib.Path) -> None:
    text = f.read_text()
    if 'signingConfigs.getByName("release")' in text:
        print("kts: подпись уже впрыснута, пропуск")
        return

    imports = "import java.util.Properties\nimport java.io.FileInputStream\n\n"
    if "import java.util.Properties" not in text:
        text = imports + text

    # Блок загрузки key.properties — перед `android {` (после обязательного plugins{}).
    load_block = (
        'val keystoreProperties = Properties()\n'
        'val keystorePropertiesFile = rootProject.file("key.properties")\n'
        'if (keystorePropertiesFile.exists()) {\n'
        '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
        '}\n\n'
    )
    idx = text.index("android {")
    text = text[:idx] + load_block + text[idx:]

    # signingConfigs — сразу внутри `android {`.
    signing = (
        '    signingConfigs {\n'
        '        create("release") {\n'
        '            keyAlias = keystoreProperties["keyAlias"] as String\n'
        '            keyPassword = keystoreProperties["keyPassword"] as String\n'
        '            storeFile = file(keystoreProperties["storeFile"] as String)\n'
        '            storePassword = keystoreProperties["storePassword"] as String\n'
        '        }\n'
        '    }\n'
    )
    marker = "android {"
    pos = text.index(marker) + len(marker)
    nl = text.index("\n", pos) + 1
    text = text[:nl] + signing + text[nl:]

    new_text = text.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
    )
    if new_text == text:
        sys.exit("kts: не найдена строка debug-подписи — шаблон Flutter изменился")
    f.write_text(new_text)
    print("kts: release-подпись впрыснута")


def inject_groovy(f: pathlib.Path) -> None:
    text = f.read_text()
    if "signingConfigs.release" in text or "signingConfig signingConfigs.release" in text:
        print("groovy: подпись уже впрыснута, пропуск")
        return

    # Groovy авто-импортирует java.util.* и java.io.*, импорты не нужны.
    load_block = (
        "def keystoreProperties = new Properties()\n"
        "def keystorePropertiesFile = rootProject.file('key.properties')\n"
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
        "}\n\n"
    )
    idx = text.index("android {")
    text = text[:idx] + load_block + text[idx:]

    signing = (
        "    signingConfigs {\n"
        "        release {\n"
        "            keyAlias keystoreProperties['keyAlias']\n"
        "            keyPassword keystoreProperties['keyPassword']\n"
        "            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null\n"
        "            storePassword keystoreProperties['storePassword']\n"
        "        }\n"
        "    }\n"
    )
    marker = "android {"
    pos = text.index(marker) + len(marker)
    nl = text.index("\n", pos) + 1
    text = text[:nl] + signing + text[nl:]

    new_text = text.replace(
        "signingConfig signingConfigs.debug",
        "signingConfig signingConfigs.release",
    )
    if new_text == text:
        sys.exit("groovy: не найдена строка debug-подписи — шаблон Flutter изменился")
    f.write_text(new_text)
    print("groovy: release-подпись впрыснута")


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("использование: inject_android_signing.py <app/android>")
    android = pathlib.Path(sys.argv[1])
    kts = android / "app" / "build.gradle.kts"
    groovy = android / "app" / "build.gradle"
    if kts.exists():
        inject_kts(kts)
    elif groovy.exists():
        inject_groovy(groovy)
    else:
        sys.exit(f"не найден build.gradle(.kts) в {android / 'app'}")


if __name__ == "__main__":
    main()
