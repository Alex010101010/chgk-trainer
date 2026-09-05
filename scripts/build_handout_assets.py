"""Раздаточные картинки в ассеты приложения (T20).

`data/images/` + `data/bingo_images.json` → `app/assets/handouts/<id вопроса>.<ext>`.
Имя файла — id вопроса: приложению не нужен манифест картинок, оно берёт
`handout` прямо из ассета вопросов.

**Пиксельные размеры не меняются.** Раздатку нужно разглядывать, и увеличение
по тапу разворачивает ровно то, что было скачано; схема 1080×946, ужатая до
ширины телефона, назад не разворачивается.

Сжимается только кодирование: фотографии — в JPEG, схемы и текстовые полосы —
в PNG с палитрой. Почти все раздатки оказались фотографиями, и часть из них
лежала в PNG (фотография поезда на 659 КБ) — на всём наборе это 9 МБ против 4.

Как и ассет вопросов, каталог не коммитится: он детерминированно выводится из
`data/images/`, которые в git уже лежат.
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
MANIFEST = os.path.join(ROOT, "data", "bingo_images.json")
SRC = os.path.join(ROOT, "data", "images")
OUT = os.path.join(ROOT, "app", "assets", "handouts")

# Порог «мало цветов» — граница между схемой и фотографией. Схема с палитрой
# весит меньше JPEG и не обрастает артефактами вокруг букв; фотография в PNG,
# наоборот, весит вчетверо больше нужного.
PALETTE_LIMIT = 512

JPEG_QUALITY = 85


def encode(path, out_dir, name):
    """Возвращает имя записанного файла."""
    im = Image.open(path)
    colors = im.convert("RGB").getcolors(maxcolors=PALETTE_LIMIT)
    is_flat = path.lower().endswith(".png") and colors is not None

    if is_flat:
        out_name = f"{name}.png"
        im.convert("P", palette=Image.ADAPTIVE, colors=min(256, len(colors))).save(
            os.path.join(out_dir, out_name), "PNG", optimize=True
        )
    else:
        out_name = f"{name}.jpg"
        im.convert("RGB").save(
            os.path.join(out_dir, out_name), "JPEG", quality=JPEG_QUALITY, optimize=True
        )
    return out_name


def build(manifest, src_dir, out_dir):
    """Раскладывает раздатки по ассетам. Возвращает `{id вопроса: имя файла}`."""
    os.makedirs(out_dir, exist_ok=True)
    mapping = {}
    for item in manifest:
        if not item.get("isHandout") or not item.get("attachedTo"):
            continue
        path = os.path.join(src_dir, item["file"])
        # Молча пропустить нельзя: вопрос уехал бы в корпус играбельным, а на
        # экране игрок увидел бы «Перед вами…» без картинки.
        if not os.path.exists(path):
            raise SystemExit(
                f"Нет файла раздатки {item['file']} для вопроса {item['attachedTo']}. "
                f"Скачай картинки: python3 scripts/fetch_bingo_images.py"
            )
        mapping[item["attachedTo"]] = encode(path, out_dir, item["attachedTo"])
    return mapping


def main():
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    mapping = build(manifest, SRC, OUT)
    total = sum(os.path.getsize(os.path.join(OUT, n)) for n in mapping.values())
    was = sum(
        i["bytes"] for i in manifest if i.get("isHandout") and i.get("attachedTo")
    )
    print(
        f"{len(mapping)} раздаток -> {OUT} "
        f"({was / 1024 / 1024:.2f} МБ -> {total / 1024 / 1024:.2f} МБ)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
