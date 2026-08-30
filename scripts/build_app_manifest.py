#!/usr/bin/env python3
"""Манифест самообновления APK.

Кладётся ассетом в GitHub Release рядом с app-release.apk. Приложение тянет его
со стабильного адреса releases/latest/download/app_manifest.json (всегда самый
свежий релиз, без токенов) и сравнивает app_build со своим build-номером. Если в
манифесте больше — предлагает скачать и установить APK по apk_url с проверкой
sha256.

Использование:
  build_app_manifest.py <apk> <build:int> <version> <apk_url> <out.json>
"""
import hashlib
import json
import sys


def main() -> None:
    if len(sys.argv) != 6:
        sys.exit("использование: build_app_manifest.py <apk> <build> <version> <apk_url> <out>")
    apk, build, version, apk_url, out = sys.argv[1:6]
    with open(apk, "rb") as f:
        data = f.read()
    manifest = {
        "schema": 1,
        "app_build": int(build),
        "app_version": version,
        "apk_url": apk_url,
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    main()
