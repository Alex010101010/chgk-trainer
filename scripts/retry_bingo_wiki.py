import json
import time

from scrape_bingo_wiki import OUT_JSON, fetch_and_parse

DELAY = 2.5
RETRIES_PER_TOPIC = 3


def main():
    with open(OUT_JSON, encoding="utf-8") as f:
        data = json.load(f)
    failed = [(i, d) for i, d in enumerate(data) if "raw_text" not in d]
    print(f"Тем на повтор: {len(failed)}")
    for n, (i, d) in enumerate(failed, 1):
        name, slug = d["name"], d["slug"]
        entry = None
        for attempt in range(RETRIES_PER_TOPIC):
            entry = fetch_and_parse(name, slug)
            if "raw_text" in entry:
                break
            time.sleep(DELAY * (attempt + 1))
        data[i] = entry
        status = "OK" if "raw_text" in entry else f"ERR: {entry.get('error')}"
        print(f"[{n}/{len(failed)}] {name} -> {status}")
        time.sleep(DELAY)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    ok = sum(1 for d in data if "raw_text" in d)
    print(f"Итог: {ok}/{len(data)} тем успешно")


if __name__ == "__main__":
    main()
