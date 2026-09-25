"""Проход по всем пакетам gotquestions (T30): дата отыгрыша каждого пакета.

Номера пакетов выдаются по порядку загрузки на сайт, а не по дате игры:
самый свежезалитый пакет 25.09.2026 оказался отыгран в 2002-м. Списка
пакетов с датами и фильтра по дате на сайте нет, поэтому пакеты открываются
по одному — до тех пор, пока свежих не наберётся на отбор.

Выход — `data/gq_packs_scan.jsonl`, строка на пакет:
`{id, status, title, startDate, questionIds, questions?}`. Вопросы целиком
(с полями раздатки) сохраняются только у пакетов не старше [CUTOFF] — у
остальных достаточно id, чтобы датировать вопросы старого дампа.

Запуск повторяемый: уже просканированные пакеты пропускаются, строки
дописываются по одной — обрыв сети не стоит часа работы.
"""
import json
import os
import re
import sys
import time

import random
import threading
from concurrent.futures import ThreadPoolExecutor

import requests

from crawl_gotquestions import HEADERS, MAX_PACK_ID, TARGET_PACKS
from gq_extract import extract_authors_map, extract_questions, extract_title

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
OUT = os.path.join(DATA_DIR, "gq_packs_scan.jsonl")
SITE = "https://gotquestions.online"
DELAY = 0.5
TIMEOUT = 40
# Пять лет от дня прохода — просьба игрока: «вопросы за последние 5 лет».
CUTOFF = "2020-09-25"
# Страница пакета отдаётся ~4 секунды: весь сайт последовательно — девять
# часов. Три запроса параллельно и остановка, как только свежих набралось с
# запасом на отбор (`build_gq_fresh.py` берёт 300).
WORKERS = 3
TARGET_FRESH = 360
SEED = 20260925


def max_pack_id():
    """Самый большой номер из «последних загруженных» на главной."""
    html = requests.get(SITE + "/", headers=HEADERS, timeout=TIMEOUT).text
    return max(int(x) for x in re.findall(r"/pack/(\d+)", html))


def pack_date(html, pack_id):
    """`startDate` самого пакета, а не соседних блоков страницы."""
    m = re.search(r'\\"pack\\":\{\\"id\\":%d,' % pack_id, html)
    if not m:
        return None
    d = re.search(r'\\"startDate\\":\\"(?:\$D)?(\d{4}-\d\d-\d\d)', html[m.end():m.end() + 3000])
    return d.group(1) if d else None


def scan_one(pack_id):
    try:
        r = requests.get(f"{SITE}/pack/{pack_id}", headers=HEADERS, timeout=TIMEOUT)
    except Exception as e:
        return {"id": pack_id, "status": "error", "error": str(e)}
    if r.status_code != 200:
        return {"id": pack_id, "status": f"http {r.status_code}"}
    questions = extract_questions(r.text)
    if not questions:
        return {"id": pack_id, "status": "empty"}
    title = re.sub(r"\s*\|\s*Есть вопросы\?\s*$", "", extract_title(r.text) or "").strip()
    date = pack_date(r.text, pack_id)
    row = {
        "id": pack_id,
        "status": "ok",
        "title": title,
        "startDate": date,
        "questionIds": [q.get("id") for q in questions],
    }
    if date and date >= CUTOFF:
        authors = extract_authors_map(r.text)
        row["questions"] = [
            {**q, "authorNames": authors.get(q.get("id"), [])} for q in questions
        ]
    return row


def scan_order(top):
    """Сперва пакеты первой закачки — без их дат вопросы нынешнего корпуса не
    датировать; потом все остальные в случайном порядке, чтобы ранняя
    остановка давала честную выборку свежих, а не «первые по номеру»."""
    rnd = random.Random(42)
    first = [i for i in rnd.sample(range(1, MAX_PACK_ID + 1), TARGET_PACKS * 2)]
    rest = [i for i in range(1, top + 1) if i not in set(first)]
    random.Random(SEED).shuffle(rest)
    return first, rest


def load_done():
    done = {}
    if os.path.exists(OUT):
        with open(OUT, encoding="utf-8") as f:
            for line in f:
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue  # строка, оборванная остановкой процесса
                # Сетевую ошибку стоит повторить, 404 — нет.
                if row["status"] != "error":
                    done[row["id"]] = row
    return done


def main():
    done = load_done()
    top = max_pack_id()
    first, rest = scan_order(top)
    first_set = set(first)
    fresh = sum(1 for i, r in done.items() if "questions" in r and i not in first_set)
    todo = [i for i in first + rest if i not in done]
    print(f"пакетов до {top}, просканировано {len(done)}, свежих вне первой "
          f"закачки {fresh}, цель {TARGET_FRESH}", flush=True)
    lock = threading.Lock()
    with open(OUT, "a", encoding="utf-8") as out, ThreadPoolExecutor(WORKERS) as pool:
        # Партиями по WORKERS: остановка по цели проверяется между партиями,
        # и после неё не висят сотни уже поставленных запросов.
        for start in range(0, len(todo), WORKERS):
            batch = todo[start:start + WORKERS]
            if fresh >= TARGET_FRESH and not first_set.intersection(batch):
                break
            for row in pool.map(scan_one, batch):
                with lock:
                    out.write(json.dumps(row, ensure_ascii=False) + "\n")
                    out.flush()
                if "questions" in row and row["id"] not in first_set:
                    fresh += 1
            n = start + len(batch)
            if n % 99 < WORKERS:
                print(f"[{n}/{len(todo)}] свежих вне первой закачки: {fresh}", flush=True)
            time.sleep(DELAY)
    print(f"Готово: свежих вне первой закачки {fresh} -> {OUT}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
