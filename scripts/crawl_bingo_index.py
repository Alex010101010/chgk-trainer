"""Крауль статей индекса бинго (T16, шаг 2).

`data/bingo_index.json` (199 ссылок) → `data/bingo_index_dump.json` — по записи
на статью, с нормализованными блоками из `bingo_index_blocks`.

Инкрементальный по устройству, как крауль вики в T1: по умолчанию идёт только
за несвежими, и неудачный запрос не имеет права затереть уже взятые блоки.
Прогон по 199 статьям через четыре хоста флакует, и «всё или ничего» выбрасывал
бы взятое при каждой осечке.
"""
import json
import os
import sys
import time

from bingo_index_blocks import FETCHER_VERSION, fetch_article

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
INDEX_JSON = os.path.join(DATA_DIR, "bingo_index.json")
OUT_JSON = os.path.join(DATA_DIR, "bingo_index_dump.json")
DELAY = 0.5

FETCHER_BY_HOST = {
    "vk.com": "vk",
    "telegra.ph": "telegraph",
    "teletype.in": "teletype-wayback",
}


def fetcher_name(host):
    if host.endswith("notion.site"):
        return "notion"
    return FETCHER_BY_HOST.get(host, "нет добытчика")


def is_fresh(entry):
    """Статья готова, только если блоки есть И взяты текущей версией добытчика.

    Провенанс — это не «уже скачано»: запись, взятая прежней версией, скачана,
    но не обязательно годна, и без отдельного поля их не различить.
    """
    return bool(entry.get("blocks")) and entry.get("fetcherVersion") == FETCHER_VERSION


def load_existing():
    if not os.path.exists(OUT_JSON):
        return {}
    with open(OUT_JSON, encoding="utf-8") as f:
        return {a["name"]: a for a in json.load(f)}


def crawl_one(article):
    blocks, error = fetch_article(article["host"], article["url"])
    entry = {
        "name": article["name"],
        "emoji": article.get("emoji"),
        "url": article["url"],
        "host": article["host"],
        "fetcher": fetcher_name(article["host"]),
        "fetcherVersion": FETCHER_VERSION,
    }
    if blocks is None:
        entry["error"] = error
    else:
        entry["blocks"] = blocks
    return entry


def quality(entries):
    """Три числа, по которым сравниваются прогоны: статей взято, объём прозы,
    картинок найдено."""
    ok = sum(1 for e in entries if e.get("blocks"))
    prose = sum(len(b["text"]) for e in entries for b in e.get("blocks") or [])
    images = sum(len(b["images"]) for e in entries for b in e.get("blocks") or [])
    return ok, prose, images


def save_if_not_worse(results):
    """Прогон флакует — молча затереть хороший дамп неудачным обошлось бы дороже
    всего. Замена только при не-ухудшении; иначе результат ложится рядом."""
    new_q = quality(results)
    old_q = None
    if os.path.exists(OUT_JSON):
        with open(OUT_JSON, encoding="utf-8") as f:
            old_q = quality(json.load(f))

    print(f"Прогон: статей с блоками {new_q[0]}/{len(results)}, прозы {new_q[1]} симв., картинок {new_q[2]}")
    if old_q:
        print(f"Было:   статей с блоками {old_q[0]}, прозы {old_q[1]} симв., картинок {old_q[2]}")

    worse = old_q and (new_q[0] < old_q[0] or new_q[1] < old_q[1])
    target = OUT_JSON if not worse else OUT_JSON.replace(".json", ".new.json")
    with open(target, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    if worse:
        print(f"ХУЖЕ ПРЕЖНЕГО — прежний дамп не тронут, новый лежит в {target}")
    else:
        print(f"Сохранено в {target}")


def main(force_all=False):
    with open(INDEX_JSON, encoding="utf-8") as f:
        index = json.load(f)
    existing = load_existing()
    todo = [a for a in index if force_all or not is_fresh(existing.get(a["name"], {}))]
    print(f"Статей всего {len(index)}, уже свежих {len(index) - len(todo)}, идём за {len(todo)}")

    for i, article in enumerate(todo, 1):
        entry = crawl_one(article)
        blocks = entry.get("blocks")
        status = f"OK, блоков {len(blocks)}" if blocks else f"ERR: {entry.get('error')}"
        print(f"[{i}/{len(todo)}] {article['name']} -> {status}", flush=True)
        # «Сегодня не ответили» — это не «статьи больше нет».
        previous = existing.get(article["name"])
        if blocks or not (previous and previous.get("blocks")):
            existing[article["name"]] = entry
        time.sleep(DELAY)

    results = [
        existing.get(a["name"], {**a, "error": "не краулилось"})
        for a in index
    ]
    save_if_not_worse(results)

    stale = [r["name"] for r in results if not is_fresh(r)]
    print(f"Ещё не свежих статей: {len(stale)}")
    if stale:
        print("Повторный запуск заберёт только их — уже свежие не перекраиваются.")
        for name in stale[:20]:
            print(f"    {name}")


if __name__ == "__main__":
    # --all — принудительно перекраулить всё, а не только несвежее.
    main(force_all="--all" in sys.argv)
