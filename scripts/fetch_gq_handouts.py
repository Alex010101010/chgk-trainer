"""Докачка раздатки gotquestions (T21).

Первый краул (`crawl_gotquestions.py`) полей раздатки не читал, и 450 вопросов
санитайзер бракует как «раздатка без картинки». Здесь добираются только эти
поля — **дамп не перезаписывается**: за месяц тексты на сайте могли поправить,
и пересборка молча поменяла бы уже сыгранный корпус.

Пакеты — те же, что у краула: тот же сид, тот же порядок. Из пакета берутся
вопросы, которые есть в дампе, поэтому раздатка известна у всех 9280, а не
только у забракованных, — иначе сверку «правило ↔ сайт» в обе стороны не
провести.

Картинка кладётся локально в `data/images/` и коммитится: хотлинки на медиа
умирают. `razdatkaPicGeneric` — старая ссылка на `db.chgk.info`, который мёртв
с 2024, поэтому берётся только `razdatkaPic` с самого gotquestions.

Выход — `data/gq_images.json`, в том же виде, что `bingo_images.json`: его
читают санитайзер и `build_handout_assets.py`.
"""
import hashlib
import json
import os
import random
import sys
import time

import requests

from crawl_gotquestions import DELAY, HEADERS, MAX_PACK_ID, TARGET_PACKS
from fetch_bingo_images import EXTENSIONS, IMAGES_DIR, image_key, is_done, measure
from gq_extract import extract_questions

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
DUMP_JSON = os.path.join(DATA_DIR, "gotquestions_dump.json")
# Свежие пакеты (T30): поля раздатки уже лежат в самом дампе, пакеты заново
# не открываются.
FRESH_DUMP = os.path.join(DATA_DIR, "gq_fresh_dump.json")
MANIFEST = os.path.join(DATA_DIR, "gq_images.json")
SITE = "https://gotquestions.online"
TIMEOUT = 40


def scan_packs(wanted):
    """{id вопроса: (razdatkaPic, razdatkaText)} по всем вопросам дампа."""
    random.seed(42)
    pack_ids = random.sample(range(1, MAX_PACK_ID + 1), TARGET_PACKS * 2)
    found = {}
    for i, pack_id in enumerate(pack_ids, 1):
        if len(found) == len(wanted):
            break
        try:
            r = requests.get(f"{SITE}/pack/{pack_id}", headers=HEADERS, timeout=TIMEOUT)
        except Exception as e:
            print(f"[{i}] pack {pack_id} -> ERR: {e}")
            continue
        hits = 0
        if r.status_code == 200:
            for q in extract_questions(r.text):
                qid = f"gq-{q.get('id')}"
                if qid in wanted:
                    found[qid] = ((q.get("razdatkaPic") or "").strip(),
                                  (q.get("razdatkaText") or "").strip())
                    hits += 1
        if hits:
            print(f"[{i}] pack {pack_id} -> {hits} вопросов (всего {len(found)}/{len(wanted)})")
        time.sleep(DELAY)
    return found


def fetch_image(url):
    try:
        r = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
        r.raise_for_status()
    except Exception as e:
        return {"status": "error", "error": str(e)}
    ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip()
    ext = EXTENSIONS.get(ctype)
    if not ext:
        return {"status": "error", "error": f"не картинка: {ctype}"}
    name = image_key(url) + ext
    with open(os.path.join(IMAGES_DIR, name), "wb") as f:
        f.write(r.content)
    width, height = measure(r.content)
    return {
        "status": "ok",
        "file": name,
        "sha256": hashlib.sha256(r.content).hexdigest(),
        "bytes": len(r.content),
        "width": width,
        "height": height,
    }


def main():
    with open(DUMP_JSON, encoding="utf-8") as f:
        wanted = {row["id"] for row in json.load(f)}
    old = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            old = {row["attachedTo"]: row for row in json.load(f)}

    # Старый дамп сканируется заново, только если манифеста ещё нет: поля
    # раздатки его 150 пакетов уже в нём, и перекачивать их незачем.
    if old:
        found = {qid: (row.get("url") or "", row.get("text") or "") for qid, row in old.items()}
    else:
        found = scan_packs(wanted)
        missing = wanted - found.keys()
        if missing:
            print(f"Не нашлись на сайте: {len(missing)} вопросов, например {sorted(missing)[:5]}")
    if os.path.exists(FRESH_DUMP):
        with open(FRESH_DUMP, encoding="utf-8") as f:
            for row in json.load(f):
                found.setdefault(row["id"], (row.get("razdatkaPic") or "", row.get("razdatkaText") or ""))

    os.makedirs(IMAGES_DIR, exist_ok=True)
    manifest = []
    for qid in sorted(found):
        pic, text = found[qid]
        if not pic and not text:
            continue
        row = {"attachedTo": qid, "isHandout": True, "url": None, "text": text or None}
        if pic:
            url = pic if pic.startswith("http") else SITE + pic
            row["url"] = url
            prev = old.get(qid)
            if prev and prev.get("url") == url and is_done(prev):
                row.update({k: prev[k] for k in ("status", "file", "sha256", "bytes", "width", "height")})
            else:
                row.update(fetch_image(url))
                time.sleep(DELAY)
                print(f"{qid}: {row['status']} {row.get('file') or row.get('error')}")
        manifest.append(row)

    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    pics = sum(1 for r in manifest if r.get("status") == "ok")
    errors = sum(1 for r in manifest if r.get("status") == "error")
    texts = sum(1 for r in manifest if r["text"])
    only_text = sum(1 for r in manifest if r["text"] and not r["url"])
    print(f"Раздатка у {len(manifest)} вопросов: картинок скачано {pics}, ошибок {errors}, "
          f"с текстом {texts} (только текст — {only_text}) -> {MANIFEST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
