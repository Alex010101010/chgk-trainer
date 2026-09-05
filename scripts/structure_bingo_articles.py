"""Проза статей бинго → `data/bingo_articles.json` (T14, срез «справка по клетке»).

Вопросы из статей уже вынуты (`structure_bingo_dump.py`, `structure_bingo_index.py`);
здесь берётся ровно то, что те скрипты выбросили, — объяснение клише до первого
вопроса: что это за факт и как его обыгрывают.

Источников два, как и у корпуса. Вики предпочтительнее индекса: её проза
написана про вопросы («чаще всего в вопросах встречается…»), а не про предмет.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))

from structure_bingo_dump import find_citation_starts

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
WIKI_IN = os.path.join(DATA_DIR, "bingo_wiki_dump.json")
INDEX_IN = os.path.join(DATA_DIR, "bingo_index_dump.json")
CORPUS_IN = os.path.join(DATA_DIR, "bingo_clean.json")
OUT_JSON = os.path.join(DATA_DIR, "bingo_articles.json")

# Строка оглавления вики: «1 События 1984 года».
TOC_ITEM = re.compile(r"^\d+(\.\d+)*\s+\S")


def _blocks(text):
    return re.split(r"\n\s*\n", text)


def _is_toc(lines):
    # Оглавление выбрасывается: в справке это список ссылок без ссылок.
    # Одной строки мало — ею может начинаться и обычный абзац.
    return len(lines) >= 2 and all(TOC_ITEM.match(l) for l in lines)


def wiki_prose(raw_text):
    """Проза вики-статьи до первого вопроса.

    Заголовок раздела в дампе отбит ведущими пробелами и склеен с первым
    абзацем раздела — расклеиваем, иначе справка начинается с «Ковентри
    Немецкая бомбардировка В 1940 году…». Заголовок помечается `## `: без
    пометки он читается как оборванное предложение посреди справки.
    """
    starts = find_citation_starts(raw_text)
    head = raw_text[: starts[0][0]] if starts else raw_text

    out = []
    for block in _blocks(head):
        if not block.strip():
            continue
        heading = block.startswith((" ", "\t"))
        lines = [l.strip() for l in block.split("\n") if l.strip()]
        if not lines or lines[0] == "Содержание" or _is_toc(lines):
            continue
        if heading:
            out.append(f"## {lines[0]}")
            lines = lines[1:]
        if lines:
            out.append(" ".join(lines))
    return "\n\n".join(out).strip()


def index_prose(blocks):
    """Проза статьи индекса — абзацы до первой цитаты (первого вопроса)."""
    out = []
    for b in blocks:
        if b.get("type") == "quote":
            break
        if b.get("type") == "p" and b.get("text", "").strip():
            out.append(" ".join(b["text"].split()))
    return "\n\n".join(out).strip()


def build(wiki, index, themes):
    """По статье на тему. Тема без прозы в файл не едет: пустая справка —
    это «нажал и ничего», и лучше сказать об этом в приложении явно."""
    articles = {}
    for a in index:
        text = index_prose(a.get("blocks", []))
        if a["name"] in themes and text:
            articles[a["name"]] = {
                "theme": a["name"],
                "text": text,
                "source": "index",
                "url": a.get("url"),
            }
    # Вики поверх индекса — пишет про вопросы, а не про предмет.
    for w in wiki:
        if w["name"] not in themes or "raw_text" not in w:
            continue
        text = wiki_prose(w["raw_text"])
        if text:
            articles[w["name"]] = {
                "theme": w["name"],
                "text": text,
                "source": "wiki",
                "url": w.get("snapshot_url"),
            }
    return [articles[k] for k in sorted(articles)]


def main():
    with open(WIKI_IN, encoding="utf-8") as f:
        wiki = json.load(f)
    with open(INDEX_IN, encoding="utf-8") as f:
        index = json.load(f)
    with open(CORPUS_IN, encoding="utf-8") as f:
        themes = {q["theme"] for q in json.load(f) if q.get("theme")}

    articles = build(wiki, index, themes)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(articles, f, ensure_ascii=False, indent=2)

    lengths = sorted(len(a["text"]) for a in articles)
    by_source = {}
    for a in articles:
        by_source[a["source"]] = by_source.get(a["source"], 0) + 1
    missing = sorted(themes - {a["theme"] for a in articles})
    print(f"Тем в корпусе: {len(themes)}, статей: {len(articles)} {by_source}")
    print(f"Длина справки: медиана {lengths[len(lengths) // 2]}, макс {lengths[-1]}")
    print(f"Без справки: {len(missing)} -> {missing[:10]}")
    print(f"Сохранено в {OUT_JSON}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
