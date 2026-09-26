"""Проза статей бинго → `data/bingo_articles.json` (T14, срез «справка по клетке»).

Вопросы из статей уже вынуты (`structure_bingo_dump.py`, `structure_bingo_index.py`);
здесь берётся ровно то, что те скрипты выбросили, — проза статьи до вопросов и
между ними (T31): что это за факт и как его обыгрывают.

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


# Поле записи вопроса. В индексе поля обычно лежат блоками `quote`, но у
# нескольких статей — абзацами `p`; узнаём их по началу текста.
# «Вопрос 26» бывает и голым абзацем, без двоеточия.
FIELD_START = re.compile(
    r"^(Вопрос\s*\d+(\s*[:.]|$)|(Ответ|Зач[её]т|Комментарий|Источник\S*|Автор\S*)\s*[:.])",
    re.IGNORECASE)
QUESTION_START = re.compile(r"^Вопрос\s*\d+", re.IGNORECASE)
# Абзац, который выдаёт кусок вопроса в справке, — страж в `leaks`.
LEAK = re.compile(
    r"(^|\n)(Ответ|Зач[её]т|Комментарий|Источник\S*|Автор\S*)\s*:|Вопрос\s*\d+\.")
# Служебные заголовки: за ними список ссылок, а не проза.
# Бывает и «ИСТОЧНИКИ ===== 1) https://…» одним абзацем.
SERVICE = re.compile(r"^(источники|ссылки|см\. также)\s*:?\s*($|[=\-]{3,})")
# Связка между альтернативными вопросами: сами вопросы выброшены.
CONNECTIVES = ("или", "и")


def _is_service(text):
    return SERVICE.match(text.strip().lower()) is not None


def _wiki_blocks(chunk):
    """Абзацы куска вики: заголовок раздела отбит ведущими пробелами и склеен
    с первым абзацем — расклеиваем и помечаем `## `."""
    out = []
    for block in _blocks(chunk):
        if not block.strip():
            continue
        raw = [l for l in block.split("\n") if l.strip()]
        lines = [l.strip() for l in raw]
        if not lines or lines[0] == "Содержание" or _is_toc(lines):
            continue
        # Все строки с отступом — это список («Иваново детство (1962);»),
        # а не заголовок, склеенный с абзацем.
        if len(raw) > 1 and all(l.startswith((" ", "\t")) for l in raw):
            out.extend(f"• {l}" for l in lines)
            continue
        if raw[0].startswith((" ", "\t")):
            out.append(f"## {lines[0]}")
            lines = lines[1:]
        if lines:
            out.append(" ".join(lines))
    return out


def _wiki_tail(body):
    """Проза после записи вопроса: от пустой строки после «Автор:». Первая
    пустая строка после «Ответ:» не годится — в источниках и комментарии
    бывают свои («3. http://… Автор: …», стихи в комментарии)."""
    m = re.search(r"Автор\S*\s*:", body) or re.search(r"Ответ\s*:", body)
    if not m:
        return ""
    br = re.search(r"\n\s*\n", body[m.end():])
    # Ведущие пробелы не срезаем: ими помечен заголовок раздела.
    return body[m.end() + br.end():] if br else ""


def _is_junk(text):
    """Не текст справки: связка между выброшенными вопросами, ссылка
    («1. https://…»), строка без букв («=====»)."""
    t = text.strip()
    return (t.lower() in CONNECTIVES or not re.search(r"\w", t)
            or re.match(r"^(•\s*)?(\d+[.)]\s*)?https?://", t) is not None)


def _join_lists(paragraphs):
    """Подряд идущие пункты списка — один абзац построчно: `ArticleBody`
    ставит отступ между абзацами, и список рассыпался бы."""
    out = []
    for p in paragraphs:
        if p.startswith("• ") and out and out[-1].startswith("• "):
            out[-1] += "\n" + p
        else:
            out.append(p)
    return out


def _drop_service_sections(paragraphs):
    """«См. также» и ему подобные — вместе с содержимым до следующего раздела."""
    out, skip = [], False
    for p in paragraphs:
        if p.startswith("## "):
            skip = _is_service(p[3:])
            if skip:
                continue
        if not skip:
            out.append(p)
    return out


def wiki_prose(raw_text):
    """Проза вики-статьи: до первого вопроса и между вопросами.

    Между вопросами стоят разделы — «Ковентри появляется по трём причинам»,
    и каждая причина — свой раздел после своих вопросов.
    """
    starts = find_citation_starts(raw_text)
    chunks = [raw_text[: starts[0][0]] if starts else raw_text]
    for i, (_, end) in enumerate(starts):
        record_end = starts[i + 1][0] if i + 1 < len(starts) else len(raw_text)
        chunks.append(_wiki_tail(raw_text[end:record_end]))
    paragraphs = [p for c in chunks for p in _wiki_blocks(c) if not _is_junk(p)]
    return "\n\n".join(_join_lists(_drop_service_sections(paragraphs))).strip()


def index_prose(blocks, name=None):
    """Проза статьи индекса: всё, что не вопрос.

    Запись вопроса — от «Вопрос N» до «Автор:». Внутри неё бывают абзацы `p` —
    раздатка между «Вопрос N:» и текстом, — они выбрасываются вместе с
    записью. Записи без автора кончаются на первом не-поле после ответа:
    раздатка стоит до ответа, проза — после.
    """
    out = []
    in_record = answered = False
    in_sources = False
    poem = []

    def flush_poem():
        if poem:
            out.append("\n".join(poem))
            poem.clear()

    for b in blocks:
        kind = b.get("type")
        text = " ".join(b.get("text", "").split())
        field = kind == "quote" or FIELD_START.match(text)
        if field:
            if QUESTION_START.match(text):
                in_record, answered = True, False
            elif text.lower().startswith("ответ"):
                answered = True
            elif text.lower().startswith("автор"):
                in_record = False
            continue
        if in_record:
            if not answered:
                continue  # раздатка внутри записи
            in_record = False
        # Картинки идут лентой отдельно.
        if kind == "figure" or _is_junk(text):
            continue
        if kind != "aside":
            flush_poem()
        if _is_service(text):
            in_sources = True
            continue
        if in_sources:
            # Список ссылок под «Источниками» — до первого настоящего абзаца.
            if kind == "list" or text.startswith("http"):
                continue
            in_sources = False
        if kind == "heading":
            if text != name:
                out.append(f"## {text}")
        elif kind == "list":
            out.append(f"• {text}")
        elif kind == "aside":
            poem.append(text)
        elif kind == "p":
            out.append(text)
    flush_poem()
    # Заголовок без текста под ним — остаток выброшенного раздела.
    out = [p for i, p in enumerate(out)
           if not (p.startswith("## ") and (i + 1 == len(out) or out[i + 1].startswith("## ")))]
    return "\n\n".join(_join_lists(out)).strip()


def leaks(text):
    """Абзацы справки, похожие на кусок вопроса."""
    return [p for p in text.split("\n\n") if LEAK.search(p)]


def build(wiki, index, themes):
    """По статье на тему. Тема без прозы в файл не едет: пустая справка —
    это «нажал и ничего», и лучше сказать об этом в приложении явно."""
    articles = {}
    for a in index:
        text = index_prose(a.get("blocks", []), a["name"])
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
    leaked = [(a["theme"], p[:120]) for a in articles for p in leaks(a["text"])]
    print(f"Тем в корпусе: {len(themes)}, статей: {len(articles)} {by_source}")
    print(f"Длина справки: медиана {lengths[len(lengths) // 2]}, макс {lengths[-1]}")
    print(f"Без справки: {len(missing)} -> {missing[:10]}")
    print(f"Похоже на кусок вопроса: {len(leaked)}")
    for theme, p in leaked:
        print(f"  {theme}: {p}")
    print(f"Сохранено в {OUT_JSON}")
    return 1 if leaked else 0


if __name__ == "__main__":
    sys.exit(main())
