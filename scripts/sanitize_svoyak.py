"""Отбор и чистка тем «Своей игры» (T6).

`data/svoyak_dump.json` → `data/svoyak_clean.json`. Единица отбора — тема
целиком: тема без одного вопроса — не тема, и бракованный вопрос уносит её всю.

Чистка текста — та же, что у «Классики» (`sanitize_dumps.py`): HTML и
сущности (T28), инструкции ведущему, варианты зачёта (T11).
"""
import collections
import json
import os
import re
import sys

from sanitize_dumps import (
    RE_HANDOUT,
    RE_MEDIA,
    accept_variants,
    clean_markup,
    clean_question,
    duplicate_key,
    normalize_answer,
)

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
DUMP = os.path.join(DATA_DIR, "svoyak_dump.json")
OUT = os.path.join(DATA_DIR, "svoyak_clean.json")
GQ_CLEAN = os.path.join(DATA_DIR, "gq_clean.json")

THEME_SIZE = 5

# Свежесть (T6, шаг 4): вопросы «Своей игры» фактические и стареют быстрее
# ЧГК («на сегодняшний день ОНА первая в рейтинге WTA» — пакет 2013 года).
# Берётся первый порог, на котором набирается MIN_THEMES тем.
CUTOFFS = ("2020-10-10", "2015-10-10")
MIN_THEMES = 500

# «Перестрелка» — раунд-перестрелка между игроками, а не тема.
RE_NOT_A_THEME = re.compile(r"(?i)перестрелк")

REASONS = {
    "not_a_theme": "раунд-перестрелка, а не тема",
    "size": f"в теме не {THEME_SIZE} вопросов",
    "taken_down": "вопрос снят с сайта",
    "media": "картинка, звук или раздатка",
    "empty": "пустой текст вопроса",
    "no_answer": "пустой ответ",
    "duplicate": "та же тема в другом пакете",
    "old": "пакет старше порога свежести",
}


def split_sources(raw):
    """Как `build_gq_fresh.as_dump_row`: источники идут строками или «1. …»."""
    return [s.strip() for s in re.split(r"\n|(?:\d+\.\s)", raw or "") if s.strip()]


def question_row(q, nominal):
    question = clean_question(clean_markup(q.get("text") or ""))
    answer = clean_markup(q.get("answer") or "").strip()
    acceptance = clean_markup(q.get("zachet") or "").strip() or None
    return {
        "id": f"si-{q['id']}",
        "nominal": nominal,
        "question": question,
        "answer": answer,
        "acceptance": acceptance,
        "acceptVariants": accept_variants(answer, acceptance or ""),
        "comment": clean_markup(q.get("comment") or "").strip() or None,
        "sources": [clean_markup(s) for s in split_sources(q.get("source"))],
        "author": ", ".join(q.get("authorNames") or []) or None,
    }


def theme_reason(theme):
    """Первая причина отбраковки темы или `None`."""
    if RE_NOT_A_THEME.search(theme.get("round") or "") or RE_NOT_A_THEME.search(theme.get("title") or ""):
        return "not_a_theme"
    questions = theme["questions"]
    if len(questions) != THEME_SIZE:
        return "size"
    for q in questions:
        if q.get("takenDown"):
            return "taken_down"
        raw = q.get("text") or ""
        if (q.get("razdatkaPic") or q.get("razdatkaText") or q.get("audio")
                or RE_HANDOUT.search(raw) or RE_MEDIA.search(raw)):
            return "media"
        if not clean_markup(raw).strip():
            return "empty"
        if not normalize_answer(clean_markup(q.get("answer") or "")):
            return "no_answer"
    return None


def nominal_shape(theme):
    return tuple(sorted(int(q.get("number") or 0) for q in theme["questions"]))


def clean_theme(theme, pack):
    # Номинал — по порядку в теме, а не из пакета: встречаются и 100–500,
    # и 1–5, а шкала в приложении одна.
    ordered = sorted(theme["questions"], key=lambda q: (int(q.get("number") or 0), q.get("ordering") or 0))
    return {
        "id": str(theme["tourId"]),
        "title": clean_markup(theme.get("title") or "").strip(),
        "round": clean_markup(theme.get("round") or "").strip(),
        "pack": clean_markup(pack.get("title") or "").strip(),
        "packId": pack["id"],
        "date": pack.get("startDate"),
        "questions": [question_row(q, (i + 1) * 10) for i, q in enumerate(ordered)],
    }


def select(packs, cutoffs=CUTOFFS, min_themes=MIN_THEMES):
    """Темы, причины отбраковки и выбранный порог свежести."""
    reasons = collections.Counter()
    playable = []
    seen = set()
    for pack in sorted(packs, key=lambda p: p.get("startDate") or "", reverse=True):
        for theme in pack["themes"]:
            reason = theme_reason(theme)
            if reason is None:
                key = duplicate_key(" ".join(q.get("text") or "" for q in theme["questions"]))
                if key in seen:
                    reason = "duplicate"
                seen.add(key)
            if reason:
                reasons[reason] += 1
            else:
                playable.append(clean_theme(theme, pack))
    cutoff = cutoffs[-1]
    for c in cutoffs:
        if sum(1 for t in playable if (t["date"] or "") >= c) >= min_themes:
            cutoff = c
            break
    fresh = [t for t in playable if (t["date"] or "") >= cutoff]
    reasons["old"] = len(playable) - len(fresh)
    return fresh, reasons, cutoff


def main():
    with open(DUMP, encoding="utf-8") as f:
        packs = json.load(f)
    themes, reasons, cutoff = select(packs)
    total = sum(len(p["themes"]) for p in packs)

    shapes = collections.Counter(nominal_shape(t) for p in packs for t in p["themes"])
    print("номиналы в дампе:", ", ".join(f"{list(s)}: {n}" for s, n in shapes.most_common(5)))
    print(f"порог свежести: {cutoff}")
    print(f"тем {len(themes)} из {total}, вопросов {len(themes) * THEME_SIZE}")
    for key, n in reasons.most_common():
        print(f"    {key}: {n} — {REASONS[key]}")

    # Вопросы «Своей игры» не должны попадать в «Классику»: её свежие пакеты
    # отбирались по дате, а не по типу (T30).
    with open(GQ_CLEAN, encoding="utf-8") as f:
        classic = {r["id"].removeprefix("gq-") for r in json.load(f) if not r.get("excluded")}
    leaked = sum(1 for t in themes for q in t["questions"] if q["id"].removeprefix("si-") in classic)
    print(f"вопросов «Своей игры» в «Классике»: {leaked}")

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(themes, f, ensure_ascii=False, indent=1)
    print(f"-> {OUT}")
    if not themes:
        sys.exit("ни одной темы — отбор сломан")


if __name__ == "__main__":
    main()
