import json
import os
import re
import time
import urllib.parse

import lxml.html
import requests

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
CATEGORY_HTML = os.path.join(DATA_DIR, "bingo_wiki_category2.html")
OUT_JSON = os.path.join(DATA_DIR, "bingo_wiki_dump.json")
DELAY = 0.7
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


def best_snapshot_url(slug, retries=3):
    original = f"http://bingo.chgk.info/wiki/{slug}"
    cdx_url = "http://web.archive.org/cdx/search/cdx"
    params = {"url": original, "output": "json"}
    for attempt in range(retries):
        try:
            r = requests.get(cdx_url, params=params, headers=HEADERS, timeout=20)
            r.raise_for_status()
            data = r.json()
            break
        except Exception as e:
            if attempt == retries - 1:
                return None, str(e)
            time.sleep(2)
    else:
        return None, "no data"
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
    try:
        r = requests.get(snap_url, headers=HEADERS, timeout=30)
        r.raise_for_status()
    except Exception as e:
        return {"name": name, "slug": slug, "snapshot_url": snap_url, "error": f"fetch failed: {e}"}
    try:
        raw_text = extract_article_text(r.content)
        if raw_text is None:
            return {"name": name, "slug": slug, "snapshot_url": snap_url, "error": "no mw-content-text"}
    except Exception as e:
        return {"name": name, "slug": slug, "snapshot_url": snap_url, "error": f"parse failed: {e}"}
    return {"name": name, "slug": slug, "snapshot_url": snap_url, "raw_text": raw_text}


def main():
    topics = get_topic_slugs()
    print(f"Тем к обработке: {len(topics)}")
    results = []
    for i, (name, slug) in enumerate(topics, 1):
        entry = fetch_and_parse(name, slug)
        status = "OK" if "raw_text" in entry else f"ERR: {entry.get('error')}"
        print(f"[{i}/{len(topics)}] {name} -> {status}")
        results.append(entry)
        time.sleep(DELAY)
    save_if_not_worse(results)


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
    main()
