"""Выгрузка таблицы фактов (T15).

Гугл-таблица → `data/facts_dump.json` + картинки в `data/images/`.

Выгрузка коммитится: ссылка на таблицу однажды умрёт или таблицу перепишут,
а колоды приложения должны собираться и тогда. Листы едут все, сырыми
строками, — прозу (T32) тоже, хотя карточки из неё пока не делаются.

Картинки встроены в лист плавающими, а не в ячейку: у каждой есть только якорь
«левый верхний угол в такой-то клетке». Якорь пишется в дамп как есть; к какой
строке картинка относится — решает `structure_facts.py`, а не этот скрипт.

Запуск: python3 scripts/fetch_facts.py [путь к уже скачанному .xlsx]
"""
import hashlib
import io
import json
import os
import posixpath
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from datetime import date

import openpyxl

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "data", "facts_dump.json")
IMAGES = os.path.join(ROOT, "data", "images")

SHEET_ID = "1iyyf_cTV0aUiQLbajGS4EEp0owuRQYEbeBn2ovpdSMw"
SOURCE = f"https://docs.google.com/spreadsheets/d/{SHEET_ID}"
EXPORT = f"{SOURCE}/export?format=xlsx"

def cell_text(value):
    """Год из экселя приходит числом `1896.0` — в карточке нужен `1896`."""
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value).strip()


def read_rels(z, path):
    """`{rId: путь внутри архива}` для файла `path`."""
    rels = posixpath.join(posixpath.dirname(path), "_rels", posixpath.basename(path) + ".rels")
    if rels not in z.namelist():
        return {}
    base = posixpath.dirname(path)
    return {
        r.get("Id"): posixpath.normpath(posixpath.join(base, r.get("Target")))
        for r in ET.fromstring(z.read(rels))
        if r.get("TargetMode") != "External"
    }


def sheet_images(z):
    """`{имя листа: [(строка, колонка, путь картинки в архиве)]}`, строки и
    колонки — с единицы, как в экселе."""
    wb_xml = z.read("xl/workbook.xml").decode("utf-8")
    wb_rels = read_rels(z, "xl/workbook.xml")
    out = {}
    for m in re.finditer(r'<sheet [^>]*?name="([^"]+)"[^>]*?r:id="([^"]+)"', wb_xml):
        name, rid = m[1], m[2]
        sheet_path = wb_rels.get(rid)
        if not sheet_path:
            continue
        for target in read_rels(z, sheet_path).values():
            if "/drawings/" not in target:
                continue
            drawing = z.read(target).decode("utf-8")
            media = read_rels(z, target)
            for a in re.finditer(
                r"<xdr:from><xdr:col>(\d+)</xdr:col>.*?<xdr:row>(\d+)</xdr:row>"
                r".*?r:embed=\"([^\"]+)\"",
                drawing,
                re.S,
            ):
                if a[3] in media:
                    out.setdefault(name, []).append((int(a[2]) + 1, int(a[1]) + 1, media[a[3]]))
    return out


def save_image(data, ext):
    """Имя — хэш содержимого, как у остальных картинок в `data/images/`."""
    name = hashlib.sha1(data).hexdigest()[:16] + ext
    path = os.path.join(IMAGES, name)
    if not os.path.exists(path):
        with open(path, "wb") as f:
            f.write(data)
    return name


def dump(xlsx_bytes):
    wb = openpyxl.load_workbook(io.BytesIO(xlsx_bytes), read_only=True, data_only=True)
    z = zipfile.ZipFile(io.BytesIO(xlsx_bytes))
    images = sheet_images(z)
    sheets = []
    for ws in wb.worksheets:
        rows = []
        for r in ws.iter_rows():
            cells = [cell_text(c.value) for c in r]
            while cells and not cells[-1]:
                cells.pop()
            if cells:
                rows.append({"row": r[0].row, "cells": cells})
        pics = [
            {"row": row, "col": col, "file": save_image(z.read(p), os.path.splitext(p)[1].lower())}
            for row, col, p in sorted(images.get(ws.title, []))
        ]
        sheets.append({"name": ws.title, "rows": rows, "images": pics})
    return {"source": SOURCE, "fetched": date.today().isoformat(), "sheets": sheets}


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], "rb") as f:
            data = f.read()
    else:
        with urllib.request.urlopen(EXPORT, timeout=120) as resp:
            data = resp.read()
    os.makedirs(IMAGES, exist_ok=True)
    result = dump(data)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    for s in result["sheets"]:
        print(f"  {s['name']}: {len(s['rows'])} строк, картинок {len(s['images'])}")
    print(f"-> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
