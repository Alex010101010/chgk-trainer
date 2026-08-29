"""Скачка картинок статей индекса (T16, шаг 5).

Картинки кладутся локально и коммитятся: хотлинк на медиа умирает — ровно этот
сценарий уже один раз убил T13, когда все ссылки ушли на мёртвые `chgk.zaba.ru`
и `db.chgk.info`.

Раздатка сохраняется как есть — исходное разрешение и формат. Ужимаются только
иллюстрации: раздатка часто скан с мелким текстом или схема, которую игрок
обязан прочитать, и ужатая до нечитаемости она выяснится только на живой игре,
когда оригинала уже не будет.
"""
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.parse
from collections import defaultdict

import requests
from PIL import Image

from bingo_index_blocks import VK_HEADERS
from scrape_bingo_wiki import HEADERS

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
DUMP_JSON = os.path.join(DATA_DIR, "bingo_index_dump.json")
QUESTIONS_JSON = os.path.join(DATA_DIR, "bingo_index_questions.json")
IMAGES_DIR = os.path.join(DATA_DIR, "images")
MANIFEST = os.path.join(DATA_DIR, "bingo_images.json")

DELAY = 0.5
TIMEOUT = 40
MAX_WIDTH = 1024
JPEG_QUALITY = 85
# После стольких подряд обрывов на одном хосте остальные его картинки
# помечаются `unreachable` без запроса. Иначе 190 недоступных картинок
# телеграфа заняли бы часы на одних таймаутах.
HOST_FAILURE_LIMIT = 5

EXTENSIONS = {"image/jpeg": ".jpg", "image/png": ".png", "image/gif": ".gif", "image/webp": ".webp"}


def image_key(url):
    return hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]


def vk_full_size(url):
    """VK кладёт в `src` превью: `cs=72x0` — это 4 КБ вместо 166.

    Полный размер берётся из списка `as=` того же URL — там перечислены все
    доступные ширины, последняя самая большая.
    """
    match = re.search(r"[?&]as=([^&]+)", url)
    if not match or "cs=" not in url:
        return url
    widths = [pair.split("x")[0] for pair in match.group(1).split(",") if "x" in pair]
    if not widths:
        return url
    return re.sub(r"cs=\d+x\d+", f"cs={widths[-1]}x0", url)


def headers_for(url):
    return VK_HEADERS if "userapi.com" in url or "vk.com" in url else {}


def download(url):
    """(байты, content-type, None) либо (None, None, текст ошибки)."""
    try:
        r = requests.get(url, headers={**HEADERS, **headers_for(url)}, timeout=TIMEOUT)
        r.raise_for_status()
    except Exception as e:
        return None, None, str(e)
    return r.content, (r.headers.get("Content-Type") or "").split(";")[0].strip(), None


def shrink(raw):
    """Ужать иллюстрацию до `MAX_WIDTH`.

    Ширина — жёсткая граница: шире `MAX_WIDTH` иллюстрация не сохраняется
    никогда, и тогда результат всегда JPEG (оригинал всё равно уже потерян
    при масштабировании).

    Картинку уже, чем `MAX_WIDTH`, пережимать смысла нет: 300-килобайтный
    PNG-скриншот в JPEG бывает и хуже, а делать файл больше ради
    «единообразия» — тем более. Такая едет как есть.
    """
    try:
        image = Image.open(io.BytesIO(raw))
        image.load()
    except Exception:
        return raw, ".bin", None, None
    width, height = image.size
    if image.mode not in ("RGB", "L"):
        image = image.convert("RGB")

    if width > MAX_WIDTH:
        height = max(1, round(height * MAX_WIDTH / width))
        image = image.resize((MAX_WIDTH, height), Image.LANCZOS)
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=JPEG_QUALITY, optimize=True)
        return buffer.getvalue(), ".jpg", MAX_WIDTH, height

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    shrunk = buffer.getvalue()
    if len(shrunk) < len(raw):
        return shrunk, ".jpg", width, height
    return raw, None, width, height


def measure(raw):
    try:
        return Image.open(io.BytesIO(raw)).size
    except Exception:
        return None, None


def collect_targets():
    """Каждая картинка каждой статьи: раздатка помечается по привязке к вопросу."""
    with open(DUMP_JSON, encoding="utf-8") as f:
        articles = json.load(f)
    with open(QUESTIONS_JSON, encoding="utf-8") as f:
        questions = json.load(f)
    handouts = {q["handoutImage"]: q["id"] for q in questions if q.get("handoutImage")}

    targets = []
    seen = set()
    for article in articles:
        for block in article.get("blocks") or []:
            for image in block["images"]:
                url = image["src"]
                if not url or url in seen:
                    continue
                seen.add(url)
                targets.append({
                    "url": url,
                    "host": urllib.parse.urlparse(url).netloc,
                    "articleName": article["name"],
                    "caption": image.get("caption"),
                    "attachedTo": handouts.get(url),
                    "isHandout": url in handouts,
                })
    return targets


def load_manifest():
    if not os.path.exists(MANIFEST):
        return {}
    with open(MANIFEST, encoding="utf-8") as f:
        return {row["url"]: row for row in json.load(f)}


def is_done(row):
    """Готово — только если файл на месте и его хеш совпал с записанным."""
    if not row or row.get("status") != "ok" or not row.get("file"):
        return False
    path = os.path.join(IMAGES_DIR, row["file"])
    if not os.path.exists(path):
        return False
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest() == row.get("sha256")


def fetch_one(target):
    url = vk_full_size(target["url"]) if "userapi.com" in target["url"] else target["url"]
    raw, content_type, error = download(url)
    if raw is None:
        return None, error

    extension = EXTENSIONS.get(content_type, os.path.splitext(urllib.parse.urlparse(url).path)[1] or ".bin")
    if target["isHandout"]:
        # Раздатка — как есть: её смысл в том, чтобы её прочитали.
        data = raw
        width, height = measure(raw)
    else:
        data, new_extension, width, height = shrink(raw)
        extension = new_extension or extension

    name = image_key(target["url"]) + extension
    os.makedirs(IMAGES_DIR, exist_ok=True)
    with open(os.path.join(IMAGES_DIR, name), "wb") as f:
        f.write(data)
    return {
        **target,
        "fetchedFrom": url if url != target["url"] else None,
        "file": name,
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
        "width": width,
        "height": height,
        "status": "ok",
    }, None


def main():
    targets = collect_targets()
    manifest = load_manifest()
    todo = [t for t in targets if not is_done(manifest.get(t["url"]))]
    print(f"Картинок всего {len(targets)}, уже скачано {len(targets) - len(todo)}, идём за {len(todo)}")

    host_failures = defaultdict(int)
    downloaded = skipped = failed = 0
    for i, target in enumerate(todo, 1):
        host = target["host"]
        if host_failures[host] >= HOST_FAILURE_LIMIT:
            manifest[target["url"]] = {**target, "status": "unreachable",
                                       "error": f"хост {host} не отвечает ({HOST_FAILURE_LIMIT} обрыва подряд)"}
            skipped += 1
            continue
        row, error = fetch_one(target)
        if row:
            host_failures[host] = 0
            manifest[target["url"]] = row
            downloaded += 1
            print(f"[{i}/{len(todo)}] {row['file']} {row['bytes'] // 1024} КБ"
                  f"{' РАЗДАТКА' if row['isHandout'] else ''}", flush=True)
        else:
            host_failures[host] += 1
            failed += 1
            manifest[target["url"]] = {**target, "status": "unreachable", "error": error}
            print(f"[{i}/{len(todo)}] ОШИБКА {target['url'][:70]} -> {error[:60]}", flush=True)
        time.sleep(DELAY)

    rows = [manifest[t["url"]] for t in targets if t["url"] in manifest]
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)

    ok = [r for r in rows if r["status"] == "ok"]
    total_bytes = sum(r["bytes"] for r in ok)
    print(f"\nСкачано {downloaded}, пропущено по недоступному хосту {skipped}, ошибок {failed}")
    print(f"В манифесте {len(rows)}: ok {len(ok)}, недоступных {len(rows) - len(ok)}")
    print(f"Раздаток: {sum(1 for r in ok if r['isHandout'])}")
    print(f"Вес: {total_bytes / 1024 / 1024:.1f} МБ")
    by_host = defaultdict(lambda: [0, 0])
    for r in rows:
        by_host[r["host"]][0 if r["status"] == "ok" else 1] += 1
    for host, (good, bad) in sorted(by_host.items(), key=lambda kv: -kv[1][0] - kv[1][1]):
        print(f"    {host:34} ok {good:4}  недоступно {bad:4}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
