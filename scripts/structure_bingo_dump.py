import json
import os
import re

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
IN_JSON = os.path.join(DATA_DIR, "bingo_wiki_dump.json")
OUT_JSON = os.path.join(DATA_DIR, "bingo_questions.json")

CITATION_MARKER = re.compile(r"Вопрос\s*\d+\.")
FIELD_LABELS = ["Ответ", "Зачет", "Зачёт", "Комментарий", "Источник(и)", "Источники", "Источник",
                "Автор(ы)", "Авторы", "Автор"]
LABEL_PATTERN = "|".join(re.escape(l) for l in FIELD_LABELS)
NEXT_LABEL = re.compile(rf"(?:{LABEL_PATTERN})\s*:", re.IGNORECASE)
CITATION_LOOKBACK = 300


def slugify(name):
    translit = {
        'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'zh',
        'з': 'z', 'и': 'i', 'й': 'i', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o',
        'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'h', 'ц': 'ts',
        'ч': 'ch', 'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
    }
    out = []
    for ch in name.lower():
        if ch in translit:
            out.append(translit[ch])
        elif ch.isalnum():
            out.append(ch)
        else:
            out.append("-")
    slug = re.sub(r"-+", "-", "".join(out)).strip("-")
    return slug or "topic"


def clean(text):
    return re.sub(r"\s*\n\s*", " ", text).strip(" \n\t") if text else text


def cut_at_paragraph_break(raw_value):
    """A blank line inside a field's raw span means we've run past the record into
    trailing subsection prose (general commentary before the next citation) — stop there."""
    m = re.search(r"\n\s*\n", raw_value)
    return raw_value[:m.start()] if m else raw_value


def split_sources(raw_value):
    # Numbered items are one per line in the source wiki markup; split on a numeral
    # at the start of a line so we don't also break on stray "1999. — С. 42." dates
    # inside a single bibliographic citation.
    parts = re.split(r"\n\s*\d+\.\s+", "\n" + raw_value)
    parts = [clean(p) for p in parts if p.strip()]
    return parts


def find_citation_starts(text):
    """For each 'Вопрос N.' marker, find where its citation text actually begins:
    the nearest preceding blank line / paragraph break, within a bounded lookback."""
    starts = []
    for m in CITATION_MARKER.finditer(text):
        window_start = max(0, m.start() - CITATION_LOOKBACK)
        window = text[window_start:m.start()]
        break_pos = None
        for bm in re.finditer(r"\n\s*\n", window):
            break_pos = bm.end()
        citation_start = window_start + break_pos if break_pos is not None else window_start
        starts.append((citation_start, m.end()))
    return starts


def parse_record(text, citation_start, citation_end, record_end):
    tournament = clean(text[citation_start:citation_end])
    body = text[citation_end:record_end]

    answer_m = re.search(r"(?:Ответ)\s*:", body, re.IGNORECASE)
    if not answer_m:
        return None
    question = clean(body[:answer_m.start()])
    if not question:
        return None

    cursor = answer_m.end()
    next_m = NEXT_LABEL.search(body, cursor)
    answer_end = next_m.start() if next_m else len(body)
    answer = clean(cut_at_paragraph_break(body[cursor:answer_end]))
    if not answer:
        return None

    fields = {"acceptance": None, "comment": None, "sources": [], "author": None}
    cursor = answer_end
    while True:
        m2 = NEXT_LABEL.search(body, cursor)
        if not m2:
            break
        label = m2.group(0).rstrip(":").strip().lower()
        m3 = NEXT_LABEL.search(body, m2.end())
        value_end = m3.start() if m3 else len(body)
        raw_value = cut_at_paragraph_break(body[m2.end():value_end])
        if label.startswith("зачет") or label.startswith("зачёт"):
            fields["acceptance"] = clean(raw_value) or None
        elif label.startswith("коммент"):
            fields["comment"] = clean(raw_value) or None
        elif label.startswith("источник"):
            fields["sources"] = split_sources(raw_value)
        elif label.startswith("автор"):
            fields["author"] = clean(raw_value) or None
        cursor = value_end

    return {
        "tournament": tournament,
        "question": question,
        "answer": answer,
        **fields,
    }


def structure_topic(topic_name, raw_text):
    slug = slugify(topic_name)
    citations = find_citation_starts(raw_text)
    out = []
    n = 0
    for i, (c_start, c_end) in enumerate(citations):
        record_end = citations[i + 1][0] if i + 1 < len(citations) else len(raw_text)
        parsed = parse_record(raw_text, c_start, c_end, record_end)
        if not parsed:
            continue
        n += 1
        out.append({
            "id": f"{slug}-{n}",
            "theme": topic_name,
            **parsed,
        })
    return out


def main():
    with open(IN_JSON, encoding="utf-8") as f:
        data = json.load(f)
    all_questions = []
    per_topic_counts = []
    for d in data:
        if "raw_text" not in d:
            continue
        qs = structure_topic(d["name"], d["raw_text"])
        per_topic_counts.append((d["name"], len(qs)))
        all_questions.extend(qs)

    zero = [name for name, c in per_topic_counts if c == 0]
    print(f"Тем обработано: {len(per_topic_counts)}")
    print(f"Тем с 0 извлечённых вопросов: {len(zero)} -> {zero}")
    print(f"Всего вопросов извлечено: {len(all_questions)}")

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(all_questions, f, ensure_ascii=False, indent=2)
    print(f"Сохранено в {OUT_JSON}")


if __name__ == "__main__":
    main()
