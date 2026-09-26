"""Колоды карточек фактов (T15).

`data/facts_dump.json` + `data/facts_fixes.json` → `data/facts_cards.json`.

Карточки делаются только из листов-пар: у них есть лицо и оборот. Прозу (T32)
этот скрипт не трогает. Колонки ищутся по заголовку, а не по номеру: ширина
листов — 26 колонок при трёх-четырёх заполненных, и порядок колонок в таблице
никто не обещал.

**Правки лежат отдельно от выгрузки.** Вычитка обязательна — в таблице есть
опечатки и ошибки в фактах, — но править выгрузку нельзя: следующая перевыгрузка стёрла бы
правки молча. Поэтому `facts_fixes.json` — `{id карточки: правка}`, а правка,
чей id в колодах больше не встречается, роняет сборку: значит, лицо карточки
в таблице поменялось, и правку надо перенести руками.

**id карточки — колода плюс хэш лица из таблицы**, а не номер строки: строки
в таблицу вставляют, и номер съехал бы у всех карточек ниже. Правка лица через
`facts_fixes.json` id не меняет — прогресс игрока по карточке сохраняется.

Мат из таблицы не вычищается — решение игрока 26.09.2026: прозвища команд
вроде «Ливерхуй» — часть фактуры, а не вандализм.
"""
import hashlib
import json
import os
import re
import string
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
DUMP = os.path.join(ROOT, "data", "facts_dump.json")
FIXES = os.path.join(ROOT, "data", "facts_fixes.json")
OUT = os.path.join(ROOT, "data", "facts_cards.json")

# Колоды в порядке показа в списке.
DECKS = [
    ("perifrazy", "Перифразы"),
    ("olimpiady", "Олимпиады"),
    ("prototipy", "Прототипы"),
    ("nobel", "Нобелевские лауреаты из России"),
    ("psevdonimy", "Псевдонимы"),
    ("kartiny", "Картины"),
    ("raznoe", "Разное"),
]

# Лист → как из строки получается карточка. В шаблонах лица и оборота —
# названия колонок; строка, где хоть одна из них пуста, карточкой не
# становится. `note` — необязательные колонки оборота: «подпись», колонка;
# колонки может не быть вовсе.
# `header: None` — у листа нет строки заголовков, колонки названы здесь.
SOURCES = [
    {
        "sheet": "Перифразы", "deck": "perifrazy", "ask": "Кто или что это?",
        "front": "{Перифраз}", "back": "{Значение}",
        "note": [("", "Комментарий")],
    },
    {
        "sheet": "Олимпийские игры", "deck": "olimpiady", "ask": "Где проходили?",
        "front": "{Сезон} Олимпийские игры {Год}", "back": "{Город}, {Страна}",
        "note": [("Победитель", "Победитель"), ("", "Знаменательные события")],
    },
    {
        "sheet": "Прототипы", "deck": "prototipy", "ask": "Кто прототип?",
        "front": "{Персонаж}", "back": "{Прототип}",
        "note": [("", "Комментарий")],
    },
    {
        "sheet": "Лауреаты нобелевской премии из ", "deck": "nobel", "ask": "Кто лауреат?",
        "front": "{Дисциплина}, {Год}: {За что выдана}", "back": "{Лауреат}",
        "note": [("", "Примечание")],
    },
    {
        "sheet": "Псевдонимы", "deck": "psevdonimy", "ask": "Настоящее имя?",
        "front": "{Псевдоним}", "back": "{Настоящее имя}",
        "note": [("", "Это кто (who)"), ("", "Примечание")],
    },
    {
        "sheet": "Изобразительное искусство", "deck": "kartiny", "ask": "Кто автор?",
        "front": "{Картина}", "back": "{Автор}",
        "note": [("", "Комментарий")],
    },
    {
        "sheet": "Имена разных стран", "deck": "raznoe",
        "ask": "Как это имя звучит в других языках?",
        "header": ["Имя", "Формы"],
        "front": "{Имя}", "back": "{Формы}", "note": [],
    },
    {
        "sheet": "Латинские выражения", "deck": "raznoe", "ask": "Как переводится?",
        "front": "{Выражение}", "back": "{Перевод}",
        "note": [("", "Комментарий")],
    },
    {
        "sheet": "Спорт", "deck": "raznoe", "ask": "Чьё это прозвище?",
        "front": "{Прозвище}", "back": "{Название команды} ({Город})",
        "note": [("", "Факты")],
    },
]

def card_id(deck, front):
    norm = re.sub(r"\s+", " ", front.strip().lower().replace("ё", "е"))
    return f"{deck}-{hashlib.sha1(norm.encode('utf-8')).hexdigest()[:8]}"


def template_fields(template):
    return [f for _, f, _, _ in string.Formatter().parse(template) if f]


def render(template, row):
    return template.format_map(row).strip()


def cards_from_sheet(src, sheet):
    rows = sheet["rows"]
    if src.get("header") is not None:
        header, body = src["header"], rows
    else:
        header, body = rows[0]["cells"], rows[1:]
    index = {name.strip(): i for i, name in enumerate(header) if name.strip()}
    need = template_fields(src["front"]) + template_fields(src["back"])
    missing = [f for f in need if f not in index]
    if missing:
        raise SystemExit(f"Лист «{src['sheet']}»: нет колонок {missing}")

    images = {img["row"]: img["file"] for img in sheet.get("images", [])}
    out = []
    for r in body:
        cells = r["cells"]
        row = {name: (cells[i].strip() if i < len(cells) else "") for name, i in index.items()}
        if any(not row[f] for f in need):
            continue
        front = render(src["front"], row)
        note = "\n".join(
            (f"{label}: {row[col]}" if label else row[col])
            for label, col in src["note"]
            if row.get(col)
        )
        card = {
            "id": card_id(src["deck"], front),
            "deck": src["deck"],
            "ask": src["ask"],
            "front": front,
            "back": render(src["back"], row),
            "sheet": src["sheet"],
            "row": r["row"],
        }
        if note:
            card["note"] = note
        # Картинка — только с якорем ровно в строке карточки. Съехавший якорь
        # к соседней строке не притягивается: строки через одну бывают разными
        # картинами, и ошибка показала бы чужую картину. Такие — правкой.
        if r["row"] in images:
            card["image"] = images[r["row"]]
        out.append(card)
    return out


def apply_fixes(cards, fixes):
    by_id = {c["id"]: c for c in cards}
    stale = [k for k in fixes if k not in by_id]
    if stale:
        raise SystemExit(
            f"Правки без карточки (лицо в таблице поменялось?): {stale}. "
            f"Перенеси их на новые id в {FIXES}"
        )
    out = []
    for c in cards:
        fix = fixes.get(c["id"])
        if fix is None:
            out.append(c)
            continue
        if "drop" in fix:
            continue
        c = dict(c)
        for key in ("front", "back", "note", "image"):
            if key in fix:
                if fix[key]:
                    c[key] = fix[key]
                else:
                    c.pop(key, None)
        out.append(c)
    return out


def build(dump, fixes):
    sheets = {s["name"]: s for s in dump["sheets"]}
    cards, seen = [], set()
    for src in SOURCES:
        if src["sheet"] not in sheets:
            raise SystemExit(f"В выгрузке нет листа «{src['sheet']}»")
        for c in cards_from_sheet(src, sheets[src["sheet"]]):
            # Дубль лица внутри колоды — одна карточка: иначе один и тот же
            # вопрос шёл бы дважды с разным прогрессом.
            if c["id"] in seen:
                continue
            seen.add(c["id"])
            cards.append(c)
    cards = apply_fixes(cards, fixes)
    decks = [
        {"id": d, "title": t, "count": sum(1 for c in cards if c["deck"] == d)}
        for d, t in DECKS
    ]
    return {"source": dump["source"], "fetched": dump["fetched"], "decks": decks, "cards": cards}


def main():
    with open(DUMP, encoding="utf-8") as f:
        dump = json.load(f)
    fixes = {}
    if os.path.exists(FIXES):
        with open(FIXES, encoding="utf-8") as f:
            fixes = json.load(f)
    result = build(dump, fixes)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    for d in result["decks"]:
        print(f"  {d['title']}: {d['count']}")
    pics = sum(1 for c in result["cards"] if c.get("image"))
    print(f"{len(result['cards'])} карточек, с картинкой {pics}, правок {len(fixes)} -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
