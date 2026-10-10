"""Выгрузка пакетов «Своей игры» с gotquestions (T6).

Пакеты «Своей игры» помечены на сайте `type: si`, и поиск отдаёт их списком с
датами: `search?type=packages&packType=si&page=N`. Обходить весь сайт, как
в T30, не нужно. Тема — тур пакета: название в `tours[].title`, раунд в
`round.title`, номинал вопроса — поле `number`.

Выход — `data/svoyak_dump.json`: пакеты целиком, сырыми, со всеми полями
вопросов. Отбор и чистка — `sanitize_dumps.py`.

Запуск повторяемый: уже скачанные пакеты пропускаются, дамп переписывается
после каждого пакета — обрыв сети не стоит прогона.
"""
import collections
import json
import os
import re
import sys
import time

import requests

from crawl_gotquestions import HEADERS
from gq_extract import extract_authors_map

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
OUT = os.path.join(DATA_DIR, "svoyak_dump.json")
SITE = "https://gotquestions.online"
LIST_URL = SITE + "/search?type=packages&packType=si&page={page}"
DELAY = 0.5
TIMEOUT = 40


def json_after(html, key, open_ch):
    """Разобрать JSON-значение, которое на странице идёт за `\\"key\\":`.

    Не через `extract_balanced`: тот считает скобки и внутри строк, и одна
    непарная «[» в тексте вопроса («[Ведущему: …») уводит конец массива за
    его границу. Здесь сперва раскодируется вся JS-строка, в которую завёрнут
    JSON, — до первой неэкранированной кавычки, — а значение читается
    настоящим JSON-разборщиком, который строки понимает."""
    m = re.search(r'\\"%s\\":%s' % (re.escape(key), re.escape(open_ch)), html)
    if not m:
        return None
    start = i = m.end() - 1
    while i < len(html) and html[i] != '"':
        i += 2 if html[i] == "\\" else 1
    try:
        value, _ = json.JSONDecoder().raw_decode(json.loads('"' + html[start:i] + '"'))
    except json.JSONDecodeError:
        return None
    return value


def clean_date(raw):
    """`$D2026-03-29T00:00:00.000Z` → `2026-03-29`."""
    m = re.search(r"\d{4}-\d\d-\d\d", raw or "")
    return m.group(0) if m else None


def list_packs():
    """Все пакеты «Своей игры» из поиска. Недобор против `totalResults` — падение:
    пустая страница посреди списка иначе выглядела бы как его конец."""
    packs, total, page = {}, None, 1
    while True:
        html = requests.get(LIST_URL.format(page=page), headers=HEADERS, timeout=TIMEOUT).text
        data = json_after(html, "initialData", "{")
        if data is None:
            sys.exit(f"страница списка {page}: нет initialData — разметка сайта сменилась")
        total = data["metadata"]["totalResults"]
        for item in data["items"]:
            if item.get("type") == "si":
                packs[item["id"]] = {
                    "id": item["id"],
                    "title": item.get("title", ""),
                    "startDate": clean_date(item.get("startDate")),
                }
        if page >= data["metadata"]["totalPages"]:
            break
        page += 1
        time.sleep(DELAY)
    if len(packs) != total:
        sys.exit(f"список: собрано {len(packs)} пакетов, сайт говорит {total}")
    return list(packs.values())


def fetch_pack(pack):
    """Темы пакета с вопросами и авторами. `None` — страница не разобралась."""
    r = requests.get(f"{SITE}/pack/{pack['id']}", headers=HEADERS, timeout=TIMEOUT)
    if r.status_code != 200:
        return None
    tours = json_after(r.text, "tours", "[")
    if not tours:
        return None
    authors = extract_authors_map(r.text)
    themes = []
    for t in tours:
        themes.append({
            "tourId": t["id"],
            "title": t.get("title", ""),
            "round": (t.get("round") or {}).get("title", ""),
            "questions": [
                {**q, "authorNames": authors.get(q.get("id"), [])}
                for q in t.get("questions", [])
            ],
        })
    return {**pack, "themes": themes}


def load_dump():
    if not os.path.exists(OUT):
        return []
    with open(OUT, encoding="utf-8") as f:
        return json.load(f)


def save_dump(rows):
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        # Без отступов: дамп лежит в git, а отступы — треть его веса.
        json.dump(rows, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, OUT)


def report(rows):
    by_year = collections.Counter()
    themes_by_year = collections.Counter()
    for p in rows:
        year = (p.get("startDate") or "????")[:4]
        by_year[year] += 1
        themes_by_year[year] += len(p["themes"])
    print("год   пакетов  тем")
    for y in sorted(by_year):
        print(f"{y}  {by_year[y]:7}  {themes_by_year[y]:5}")
    print(f"всего {len(rows)} пакетов, {sum(themes_by_year.values())} тем")


def main():
    packs = list_packs()
    rows = load_dump()
    done = {p["id"] for p in rows}
    todo = [p for p in packs if p["id"] not in done]
    print(f"в списке {len(packs)}, уже скачано {len(done)}, качаю {len(todo)}")
    failed = []
    for i, pack in enumerate(todo, 1):
        try:
            row = fetch_pack(pack)
        except requests.RequestException as e:
            row = None
            print(f"  {pack['id']}: {e}")
        if row is None:
            failed.append(pack["id"])
        else:
            rows.append(row)
            save_dump(rows)
        print(f"{i}/{len(todo)} {pack['id']} {pack['title'][:60]}")
        time.sleep(DELAY)
    report(rows)
    if failed:
        sys.exit(f"не скачались: {failed} — перезапусти, скачанные пропустятся")


if __name__ == "__main__":
    main()
