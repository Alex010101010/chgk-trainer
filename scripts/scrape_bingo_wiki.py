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


def fix_mojibake(text):
    try:
        return text.encode("latin-1", errors="strict").decode("utf-8", errors="strict")
    except (UnicodeDecodeError, UnicodeEncodeError):
        return text


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
        tree = lxml.html.fromstring(r.content)
        content = tree.xpath('//div[@id="mw-content-text"]')
        if not content:
            return {"name": name, "slug": slug, "snapshot_url": snap_url, "error": "no mw-content-text"}
        raw_text = fix_mojibake(content[0].text_content())
        raw_text = re.sub(r'\n{3,}', '\n\n', raw_text).strip()
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
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    ok = sum(1 for r in results if "raw_text" in r)
    print(f"Готово: {ok}/{len(results)} тем успешно, сохранено в {OUT_JSON}")


if __name__ == "__main__":
    main()
