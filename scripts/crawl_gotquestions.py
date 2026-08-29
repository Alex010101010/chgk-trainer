import json
import os
import random
import re
import time

import requests

from gq_extract import extract_authors_map, extract_questions, extract_title

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
OUT_JSON = os.path.join(DATA_DIR, "gotquestions_dump.json")
HEADERS = {"User-Agent": "chgk-trainer-content-research/0.1 (non-commercial personal project)"}
DELAY = 0.5
TARGET_PACKS = 150
MAX_PACK_ID = 7030


def fetch_pack(pack_id):
    url = f"https://gotquestions.online/pack/{pack_id}"
    try:
        r = requests.get(url, headers=HEADERS, timeout=20)
    except Exception as e:
        return None, f"request failed: {e}"
    if r.status_code != 200:
        return None, f"http {r.status_code}"
    html = r.text
    title = extract_title(html)
    if title and title.strip().lower().startswith(("404", "не найд")):
        return None, "not found"
    questions = extract_questions(html)
    if not questions:
        return None, "no questions parsed"
    authors_map = extract_authors_map(html)
    pack_title = re.sub(r"\s*\|\s*Есть вопросы\?\s*$", "", title or "").strip()

    out = []
    for q in questions:
        qid = q.get("id")
        sources_raw = q.get("source") or ""
        sources = [s.strip() for s in re.split(r"\n|(?:\d+\.\s)", sources_raw) if s.strip()]
        out.append({
            "id": f"gq-{qid}",
            "theme": None,
            "tournament": pack_title,
            "question": q.get("text"),
            "answer": q.get("answer"),
            "acceptance": q.get("zachet") or None,
            "comment": q.get("comment") or None,
            "sources": sources,
            "author": ", ".join(authors_map.get(qid, [])) or None,
            "complexity": q.get("complexity") or None,
        })
    return out, None


def main():
    random.seed(42)
    pack_ids = random.sample(range(1, MAX_PACK_ID + 1), TARGET_PACKS * 2)
    results = []
    ok_packs = 0
    for i, pack_id in enumerate(pack_ids, 1):
        if ok_packs >= TARGET_PACKS:
            break
        qs, err = fetch_pack(pack_id)
        if qs:
            ok_packs += 1
            results.extend(qs)
            print(f"[{i}] pack {pack_id} -> OK, {len(qs)} вопросов (пакетов собрано: {ok_packs}, вопросов всего: {len(results)})")
        else:
            print(f"[{i}] pack {pack_id} -> ERR: {err}")
        time.sleep(DELAY)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f"Готово: {ok_packs} пакетов, {len(results)} вопросов, сохранено в {OUT_JSON}")


if __name__ == "__main__":
    main()
