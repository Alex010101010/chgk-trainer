import json
import os
import sys
import re
import time
import urllib.parse

import lxml.html
import requests

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
CATEGORY_HTML = os.path.join(DATA_DIR, "bingo_wiki_category2.html")
OUT_JSON = os.path.join(DATA_DIR, "bingo_wiki_dump.json")
DELAY = 2.0
# Версия декодера. Тема, взятая старым кодом, несёт мойибейк, который сам по
# себе не чинится, — поэтому «уже скачано» и «скачано правильно» это разные
# вещи, и провенанс пишется прямо в дамп.
DECODER_VERSION = 2
# archive.org под нагрузкой отдаёт 503 и рвёт соединения пачками: первый
# полный прогон взял 53 темы из 139 и упёрся. Отступ с ростом — единственное,
# что отличает «сервер занят» от «темы нет».
RETRY_SLEEPS = (5, 15, 45)
HEADERS = {"User-Agent": "chgk-trainer-content-research/0.1 (non-commercial personal project)"}


def parse_html(raw_bytes):
    """Разобрать страницу с ЯВНО определённой кодировкой.

    lxml, получив байты, угадывает кодировку сам и на архивных страницах
    bingo.chgk.info промахивается в latin-1: кириллица превращается в
    `Ð‘Ð»Ð°Ð³Ð¾Ð´Ð°Ñ€Ñ`. Прежняя версия компенсировала это функцией
    `fix_mojibake`, которая перекодировала раны [\x80-\xff] обратно — и
    попутно уничтожала корректные «ёлочки» и неразрывные пробелы: одиночный
    «` (U+00AB) — это ран из одного байта, `b'\xab'` как UTF-8 не
    декодируется, и errors="replace" оставлял на его месте U+FFFD.
    """
    try:
        raw_bytes.decode("utf-8")
        encoding = "utf-8"
    except UnicodeDecodeError:
        encoding = "cp1251"
    return lxml.html.fromstring(raw_bytes, parser=lxml.html.HTMLParser(encoding=encoding))


def extract_article_text(raw_bytes):
    """Текст статьи или None, если на странице нет содержимого вики."""
    content = parse_html(raw_bytes).xpath('//div[@id="mw-content-text"]')
    if not content:
        return None
    return re.sub(r"\n{3,}", "\n\n", content[0].text_content()).strip()


def get_topic_slugs():
    tree = lxml.html.parse(CATEGORY_HTML).getroot()
    links = tree.xpath('//div[@id="mw-pages"]//a')
    slugs = []
    for a in links:
        href = a.get("href")
        slug = href.split("/wiki/")[-1]
        name = urllib.parse.unquote(slug).replace("_", " ")
        slugs.append((name, slug))
    return slugs


def polite_get(url, params=None, timeout=30):
    """Запрос с растущим отступом. Возвращает (response, None) либо (None, текст ошибки)."""
    last_error = "не пробовали"
    for pause in (0,) + RETRY_SLEEPS:
        if pause:
            time.sleep(pause)
        try:
            r = requests.get(url, params=params, headers=HEADERS, timeout=timeout)
            r.raise_for_status()
            return r, None
        except Exception as e:
            last_error = str(e)
    return None, last_error


def best_snapshot_url(slug):
    original = f"http://bingo.chgk.info/wiki/{slug}"
    cdx_url = "http://web.archive.org/cdx/search/cdx"
    r, err = polite_get(cdx_url, params={"url": original, "output": "json"}, timeout=20)
    if r is None:
        return None, err
    try:
        data = r.json()
    except Exception as e:
        return None, f"bad cdx json: {e}"
    rows = data[1:]
    ok_rows = [row for row in rows if row[4] == "200"]
    if not ok_rows:
        return None, "no 200 snapshot"
    ok_rows.sort(key=lambda r: int(r[6]), reverse=True)
    best = ok_rows[0]
    timestamp = best[1]
    return f"http://web.archive.org/web/{timestamp}/{original}", None


def fetch_and_parse(name, slug):
    snap_url, err = best_snapshot_url(slug)
    if not snap_url:
        return {"name": name, "slug": slug, "error": f"no snapshot: {err}"}
    r, err = polite_get(snap_url, timeout=30)
    if r is None:
        return {"name": name, "slug": slug, "snapshot_url": snap_url, "error": f"fetch failed: {err}"}
    try:
        raw_text = extract_article_text(r.content)
        if raw_text is None:
            return {"name": name, "slug": slug, "snapshot_url": snap_url, "error": "no mw-content-text"}
    except Exception as e:
        return {"name": name, "slug": slug, "snapshot_url": snap_url, "error": f"parse failed: {e}"}
    return {
        "name": name,
        "slug": slug,
        "snapshot_url": snap_url,
        "raw_text": raw_text,
        "decoder": DECODER_VERSION,
    }


def load_existing():
    if not os.path.exists(OUT_JSON):
        return {}
    with open(OUT_JSON, encoding="utf-8") as f:
        return {t["name"]: t for t in json.load(f)}


def is_fresh(entry):
    """Тема считается готовой, только если текст есть И взят текущим декодером."""
    return bool(entry.get("raw_text")) and entry.get("decoder") == DECODER_VERSION


def main(force_all=False):
    topics = get_topic_slugs()
    existing = load_existing()
    todo = [(n, s) for n, s in topics if force_all or not is_fresh(existing.get(n, {}))]
    print(f"Тем всего {len(topics)}, уже свежих {len(topics) - len(todo)}, идём за {len(todo)}")

    for i, (name, slug) in enumerate(todo, 1):
        entry = fetch_and_parse(name, slug)
        status = "OK" if "raw_text" in entry else f"ERR: {entry.get('error')}"
        print(f"[{i}/{len(todo)}] {name} -> {status}", flush=True)
        # Неудача не имеет права затереть уже имеющийся текст: прогон по
        # архиву флакует, и «сегодня не ответили» — это не «темы больше нет».
        previous = existing.get(name)
        if entry.get("raw_text") or not (previous and previous.get("raw_text")):
            existing[name] = entry
        time.sleep(DELAY)

    results = [
        existing.get(name, {"name": name, "slug": slug, "error": "не краулилось"})
        for name, slug in topics
    ]
    save_if_not_worse(results)
    stale = [r["name"] for r in results if not is_fresh(r)]
    print(f"Ещё не свежих тем: {len(stale)}")
    if stale:
        print("Повторный запуск заберёт только их — уже свежие не перекраиваются.")


def quality(entries):
    """Три числа, по которым сравниваются прогоны: удачных тем, объём прозы,
    остаточный мойибейк."""
    ok = sum(1 for e in entries if e.get("raw_text"))
    prose = sum(len(e.get("raw_text") or "") for e in entries)
    broken = sum((e.get("raw_text") or "").count("\ufffd") for e in entries)
    return ok, prose, broken


def save_if_not_worse(results):
    """Крауль по web.archive флакует — два прогона подряд дают разный набор
    удачных тем. Молча затереть хороший дамп неудачным прогоном обошлось бы
    дороже всего, поэтому замена только при не-ухудшении; иначе результат
    ложится рядом и решение принимает человек."""
    new_q = quality(results)
    old_q = None
    if os.path.exists(OUT_JSON):
        with open(OUT_JSON, encoding="utf-8") as f:
            old_q = quality(json.load(f))

    print(f"Прогон: тем с текстом {new_q[0]}/{len(results)}, прозы {new_q[1]} симв., U+FFFD {new_q[2]}")
    if old_q:
        print(f"Было:   тем с текстом {old_q[0]}, прозы {old_q[1]} симв., U+FFFD {old_q[2]}")

    worse = old_q and (new_q[0] < old_q[0] or new_q[1] < old_q[1])
    target = OUT_JSON if not worse else OUT_JSON.replace(".json", ".new.json")
    with open(target, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    if worse:
        print(f"ХУЖЕ ПРЕЖНЕГО — прежний дамп не тронут, новый лежит в {target}")
    else:
        print(f"Сохранено в {target}")


if __name__ == "__main__":
    # --all — принудительно перекраулить всё, а не только несвежее.
    main(force_all="--all" in sys.argv)
