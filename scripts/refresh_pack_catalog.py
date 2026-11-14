"""Перепроверить свежие скачанные пакеты и подготовить отдельные наборы.

Не использует дату публикации для отбора. Повторный запуск читает кеш;
неудачные запросы не заменяют уже полученные данные.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import date
import json
import os
from pathlib import Path
import threading
import time

import requests
from crawl_gotquestions import HEADERS
from gq_extract import extract_pack
from pack_policy import audience, in_horizon, play_date, today
from build_gq_fresh import as_dump_row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--limit', type=int, default=360)
    parser.add_argument('--as-of', type=date.fromisoformat, default=today())
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    cache = args.out/'pack_cache'
    cache.mkdir(exist_ok=True)
    index = json.loads((args.source/'gq_packs_index.json').read_text())
    candidates = sorted((p for p in index if in_horizon(p.get('startDate'),args.as_of)),
                        key=lambda p:(p['startDate'],p['id']),reverse=True)[:args.limit]
    ids = [p['id'] for p in candidates]
    adult_sources = args.source/'adult_pack_sources.json'
    if adult_sources.exists():
        ids += [p['packId'] for p in json.loads(adult_sources.read_text())]
    ids += [p['id'] for p in index if audience({**p,'metadataChecked':True})[0]=='adult']
    ids = list(dict.fromkeys(ids))
    # Соблюдаем общую паузу между запросами и Crawl-delay источника.
    import urllib.robotparser
    robot = requests.get('https://gotquestions.online/robots.txt',headers=HEADERS,timeout=30)
    robot.raise_for_status()
    rp = urllib.robotparser.RobotFileParser()
    rp.parse(robot.text.splitlines())
    delay = max(.5,rp.crawl_delay(HEADERS['User-Agent']) or rp.crawl_delay('*') or 0)
    lock = threading.Lock()
    last = [0.0]

    def fetch(pid):
        path = cache/f'{pid}.json'
        if path.exists():
            cached = json.loads(path.read_text())
            if cached.get('checkedAt') == args.as_of.isoformat():
                return cached
        url = f'https://gotquestions.online/pack/{pid}'
        if not rp.can_fetch(HEADERS['User-Agent'],url):
            raise ValueError(f'robots.txt запрещает {url}')
        with lock:
            time.sleep(max(0,delay-(time.monotonic()-last[0])))
            last[0] = time.monotonic()
        r = requests.get(url,headers=HEADERS,timeout=40)
        r.raise_for_status()
        p = extract_pack(r.text,pid)
        p['metadataChecked'] = True
        p['checkedAt'] = args.as_of.isoformat()
        path.write_text(json.dumps(p,ensure_ascii=False))
        return p

    packs = []
    with ThreadPoolExecutor(max_workers=3) as executor:
        for n,p in enumerate(executor.map(fetch,ids),1):
            packs.append(p)
            if n % 20 == 0 or n == len(ids):
                print(f'Проверено {n}/{len(ids)}',flush=True)
    catalog = []
    for p in packs:
        category,reason = audience(p)
        catalog.append(dict(id=p['id'],title=p['title'],type=p['type'],
                            startDate=play_date(p.get('startDate')),pubDate=play_date(p.get('pubDate')),
                            adultOnly=p.get('adultOnly'),audience=category,audienceReason=reason,
                            info=p.get('info'),sourceUrl=f"https://gotquestions.online/pack/{p['id']}",
                            metadataChecked=True,checkedAt=args.as_of.isoformat()))
    by_id = {p['id']:p for p in packs}
    eligible = [p for p in catalog if in_horizon(p['startDate'],args.as_of)]
    standard = sorted((p for p in eligible if p['type']=='kvrm' and p['audience']=='standard'),
                      key=lambda p:(p['startDate'],p['id']),reverse=True)[:300]
    selected = {p['id'] for p in standard}
    for p in catalog:
        p['selected'] = p['id'] in selected

    def questions(meta):
        p = by_id[meta['id']]
        for t in p.get('tours',[]):
            for q in t.get('questions',[]):
                names = [a['person']['name'] for a in q.get('authors',[]) if a.get('person',{}).get('name')]
                yield as_dump_row({**q,'authorNames':names},meta)

    rows = [q for p in standard for q in questions(p)]
    # Взрослые пакеты по решению игрока 14.11.2026 не ограничены возрастом.
    adults = [dict(pack=p,questions=list(questions(p))) for p in catalog if p['type']=='kvrm' and p['audience']=='adult']
    if len(standard)<300:
        raise SystemExit('Не хватает 300 обычных пакетов: увеличьте --limit, кеш сохранён, наборы не заменены')
    for name,data in [('pack_catalog.json',catalog),('gq_recent_dump.json',rows),('gq_adult_dump.json',adults)]:
        tmp = args.out/(name+'.tmp')
        tmp.write_text(json.dumps(data,ensure_ascii=False,indent=1))
        os.replace(tmp,args.out/name)
    print(json.dumps(dict(checked=len(catalog),selectedPacks=len(standard),questions=len(rows),adultPacks=len(adults),reviewPacks=sum(p['audience']=='review' for p in eligible)),ensure_ascii=False),flush=True)


if __name__=='__main__':
    main()
