"""Раздаточные картинки в ассеты приложения (T20).

`data/images/` + `data/bingo_images.json` + `data/gq_images.json` (T21)
→ `app/assets/handouts/<id вопроса>.<ext>`.
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

sys.path.insert(0, os.path.dirname(__file__))

from build_app_assets import article_image_name

ROOT = os.path.join(os.path.dirname(__file__), "..")
BINGO_MANIFEST = os.path.join(ROOT, "data", "bingo_images.json")
# У gq в манифесте есть и нескачанные картинки, и чисто текстовая раздатка:
# в сборку идут только скачанные — остальные вопросы санитайзер и так бракует.
GQ_MANIFEST = os.path.join(ROOT, "data", "gq_images.json")
GQ_CLEAN = os.path.join(ROOT, "data", "gq_clean.json")
SRC = os.path.join(ROOT, "data", "images")
OUT = os.path.join(ROOT, "app", "assets", "handouts")

# Порог «мало цветов» — граница между схемой и фотографией. Схема с палитрой
# весит меньше JPEG и не обрастает артефактами вокруг букв; фотография в PNG,
# наоборот, весит вчетверо больше нужного.
PALETTE_LIMIT = 512

JPEG_QUALITY = 85

# Иллюстрации статей справочника (T14) — не раздатка: их смотрят, а не
# разглядывают, и больше экрана телефона им не нужно. Исходники в основном
# до 800 px, так что на наборе 26.09.2026 порог почти ничего не срезал
# (666 картинок, 54 МБ) — это страховка от единичных огромных.
ARTICLE_MAX_SIDE = 1200


def encode(path, out_dir, name):
    """Возвращает имя записанного файла."""
    im = Image.open(path)
    colors = im.convert("RGB").getcolors(maxcolors=PALETTE_LIMIT)
    is_flat = path.lower().endswith(".png") and colors is not None

    if is_flat:
        out_name = f"{name}.png"
        # Через RGB: палитра строится только из 8-битных режимов, а среди
        # раздаток gq попадаются 16-битные и с альфой (T30).
        im.convert("RGB").convert("P", palette=Image.ADAPTIVE, colors=min(256, len(colors))).save(
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
                f"Скачай картинки: python3 scripts/fetch_bingo_images.py "
                f"(gq — python3 scripts/fetch_gq_handouts.py)"
            )
        mapping[item["attachedTo"]] = encode(path, out_dir, item["attachedTo"])
    return mapping


def build_article_images(manifest, src_dir, out_dir):
    """Иллюстрации статей (T14) → `art-<исходник>.jpg`. Возвращает число файлов."""
    os.makedirs(out_dir, exist_ok=True)
    done = set()
    for item in manifest:
        if item.get("isHandout") or not item.get("file") or not item.get("articleName"):
            continue
        path = os.path.join(src_dir, item["file"])
        name = article_image_name(item["file"])
        # Нескачанную картинку статья и не объявит (`article_images`), так что
        # здесь пропуск не молчаливая дыра, а тот же фильтр с другой стороны.
        if name in done or not os.path.exists(path):
            continue
        im = Image.open(path).convert("RGB")
        im.thumbnail((ARTICLE_MAX_SIDE, ARTICLE_MAX_SIDE))
        im.save(os.path.join(out_dir, name), "JPEG", quality=JPEG_QUALITY, optimize=True)
        done.add(name)
    return len(done)


def main():
    with open(BINGO_MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    # Раздатка gq — только у вопросов, которые идут в поток: у устаревших
    # (T30) картинки лежат в data/, но в приложение не едут.
    with open(GQ_CLEAN, encoding="utf-8") as f:
        playable = {r["id"] for r in json.load(f) if r.get("excluded") is None}
    with open(GQ_MANIFEST, encoding="utf-8") as f:
        manifest += [i for i in json.load(f)
                     if i.get("status") == "ok" and i["attachedTo"] in playable]
    mapping = build(manifest, SRC, OUT)
    with open(BINGO_MANIFEST, encoding="utf-8") as f:
        arts = build_article_images(json.load(f), SRC, OUT)
    art_mb = sum(
        os.path.getsize(os.path.join(OUT, n)) for n in os.listdir(OUT) if n.startswith("art-")
    ) / 1024 / 1024
    print(f"{arts} иллюстраций статей -> {OUT} ({art_mb:.2f} МБ)")
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
