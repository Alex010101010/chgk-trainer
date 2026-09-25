"""Свежие пакеты gotquestions в корпус (T30).

`data/gq_packs_scan.jsonl` (выход `scan_gq_packs.py`, в git не лежит — там
целиком все свежие пакеты) → два файла, которые коммитятся:

- `data/gq_packs_index.json` — дата отыгрыша каждого пакета и его вопросы.
  По нему санитайзер датирует **любой** gq-вопрос, в том числе старого дампа:
  у первой закачки дат не было вовсе.
- `data/gq_fresh_dump.json` — [TARGET_PACKS] случайных пакетов не старше
  `CUTOFF`, в формате `gotquestions_dump.json` плюс поля раздатки и дата.

300 пакетов — примерно столько же вопросов, сколько в корпусе было: старые
уходят из потока, и приложение не распухает (развилка T30, вариант 1).
"""
import json
import os
import random
import re
import sys

from scan_gq_packs import CUTOFF, OUT as SCAN

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
INDEX = os.path.join(DATA_DIR, "gq_packs_index.json")
OLD_DUMP = os.path.join(DATA_DIR, "gotquestions_dump.json")
FRESH_DUMP = os.path.join(DATA_DIR, "gq_fresh_dump.json")
TARGET_PACKS = 300
SEED = 20260925


def load_scan():
    packs = {}
    with open(SCAN, encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            # Повторный прогон дописывает строку заново — последняя верна.
            packs[row["id"]] = row
    return packs


def as_dump_row(q, pack):
    """Та же форма, что у `crawl_gotquestions.py`, — санитайзер её уже знает."""
    sources_raw = q.get("source") or ""
    sources = [s.strip() for s in re.split(r"\n|(?:\d+\.\s)", sources_raw) if s.strip()]
    return {
        "id": f"gq-{q.get('id')}",
        "theme": None,
        "tournament": pack["title"],
        "question": q.get("text"),
        "answer": q.get("answer"),
        "acceptance": q.get("zachet") or None,
        "comment": q.get("comment") or None,
        "sources": sources,
        "author": ", ".join(q.get("authorNames") or []) or None,
        "complexity": q.get("complexity") or None,
        "packId": pack["id"],
        "packDate": pack["startDate"],
        "razdatkaPic": (q.get("razdatkaPic") or "").strip() or None,
        "razdatkaText": (q.get("razdatkaText") or "").strip() or None,
    }


def main():
    packs = load_scan()
    ok = [p for p in packs.values() if p["status"] == "ok"]
    index = [
        {"id": p["id"], "title": p["title"], "startDate": p["startDate"],
         "questionIds": p["questionIds"]}
        for p in sorted(ok, key=lambda p: p["id"])
    ]
    with open(INDEX, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False)

    with open(OLD_DUMP, encoding="utf-8") as f:
        old_ids = {row["id"] for row in json.load(f)}
    fresh = [p for p in ok if p.get("questions")]
    # Пакет, чьи вопросы уже есть в старом дампе, второй раз не берётся:
    # его свежие вопросы и так останутся в потоке.
    candidates = [
        p for p in fresh
        if not any(f"gq-{qid}" in old_ids for qid in p["questionIds"])
    ]
    rnd = random.Random(SEED)
    picked = rnd.sample(sorted(candidates, key=lambda p: p["id"]),
                        min(TARGET_PACKS, len(candidates)))
    rows = [as_dump_row(q, p) for p in sorted(picked, key=lambda p: p["id"])
            for q in p["questions"]]
    with open(FRESH_DUMP, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)

    dated = sum(1 for p in ok if p["startDate"])
    print(f"Пакетов просканировано: {len(packs)}, с вопросами {len(ok)}, с датой {dated}")
    print(f"Не старше {CUTOFF}: {len(fresh)} пакетов, "
          f"{sum(len(p['questionIds']) for p in fresh)} вопросов")
    print(f"Взято {len(picked)} пакетов, {len(rows)} вопросов -> {FRESH_DUMP}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
