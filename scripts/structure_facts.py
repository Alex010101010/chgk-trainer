"""Колоды карточек фактов (T15).

`data/facts_dump.json` + `data/facts_fixes.json` → `data/facts_cards.json`.

Листы-пары дают лицо и оборот напрямую. Колонки ищутся по заголовку, а не по
номеру: ширина листов — 26 колонок при трёх-четырёх заполненных, и порядок
колонок в таблице никто не обещал.

**Проза (T32)** — абзац-справка «Термин — описание» — переворачивается:
на лице описание, где термин спрятан маской, на обороте термин, под ним абзац
целиком. Это вспоминание по описанию, как на вопросе, а не чтение. Маска
ловит термин, варианты из скобок и слова термина по основе (слово без двух
последних букв) — так закрываются склонения; что проскочило, закрывается
правкой. Абзац без «Термин —» карточкой не становится.

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
    ("kartiny", "Искусство"),
    ("raznoe", "Разное"),
    ("random", "Рандом"),
    ("istoriya", "История"),
    ("literatura", "Литература"),
    ("nauki", "Науки"),
    ("hristianstvo", "Христианство"),
    ("greki", "Греки"),
    ("citaty", "Цитаты"),
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

# Прозаические листы → колода. `inline` — лист-пара, в котором ниже таблицы
# идут абзацы прозы в первой колонке (художники в ИЗО, спортсмены в «Спорте»).
# Шекспир — тоже цитаты, а колода из девяти карточек выглядела бы сломанной.
PROSE_SOURCES = [
    {"sheet": "Рандом", "deck": "random"},
    {"sheet": "История", "deck": "istoriya"},
    {"sheet": "Литература", "deck": "literatura"},
    {"sheet": "Науки", "deck": "nauki"},
    {"sheet": "Христианство", "deck": "hristianstvo"},
    {"sheet": "Греки", "deck": "greki"},
    {"sheet": "Цитаты", "deck": "citaty"},
    {"sheet": "Шекспир", "deck": "citaty"},
    {"sheet": "Изобразительное искусство", "deck": "kartiny", "inline": True},
    {"sheet": "Спорт", "deck": "raznoe", "inline": True},
]
PROSE_ASK = "Кто или что это?"
MASK = "[…]"
# Термин длиннее — это уже не термин, а начало рассказа («Ходила легенда, что…»).
TERM_MAX = 90
# Дальше головы тире не ищем: скобки с переводом и датами бывают длинными.
HEAD_SCAN = 400
# Слова, которые в термине встречаются, но маскировать их по всему тексту
# нельзя: «часто», «известная», «также» есть в каждом втором абзаце.
STOP_WORDS = {
    "часто", "также", "иначе", "известный", "известная", "известное", "известен",
    "настоящее", "время", "имя", "урождённая", "урожденная", "прозвище", "когда",
    "который", "которая", "этот", "была", "было", "были", "того", "свой", "англ",
    "франц", "итал", "греч", "латин", "нем", "лат", "исп", "года", "году", "годы",
}


def split_head(text):
    """«Термин — описание» → (термин, описание) или None.

    Тире ищется вне скобок: у «Тест Бекдел (часто — тест Бехдель) — тест…»
    первое тире стоит внутри скобки. Пробелы вокруг тире в таблице какие
    угодно («De Beers— …», «Этци- …»); дефис без пробелов — часть слова.
    Длина термина меряется без скобок: «Мейфлауэр (англ. Mayflower, дословно…)».
    """
    depth = 0
    for i, ch in enumerate(text[:HEAD_SCAN]):
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth = max(0, depth - 1)
        elif depth == 0 and (
            ch in "—–"
            or (ch == "-" and (text[i - 1: i].isspace() or text[i + 1: i + 2].isspace()))
        ):
            term, body = text[:i].strip(), text[i + 1:].lstrip("—–- ").strip()
            main = re.sub(r"\([^()]*\)", "", term).strip()
            # Точка внутри короткого термина — название («Маус. Рассказ
            # выжившего», «Лихорадка Св. Антония»), внутри длинного — рассказ.
            if not main or len(main) > TERM_MAX or not body or (". " in main and len(main) > 40):
                return None
            return term, body
    return None


def _words(text):
    return [w for w in re.findall(r"\w+", text) if not w.isdigit()]


def term_parts(term):
    """Термин без скобок, варианты из скобок и даты из скобок.

    «Ян Гевелий (1611-1687)» — даты уходят на лицо подсказкой.
    «Фра-Дьяволо (настоящее имя Микеле Пецца)» — вариант маскируется.
    """
    alts, dates = [], []
    for inner in re.findall(r"\(([^()]*)\)", term):
        if re.search(r"\d", inner) and not re.search(r"[A-Za-zА-Яа-яЁё]{3,}", inner.replace("род", "")):
            dates.append(inner.strip())
            continue
        inner = re.sub(r"\b[а-яё]{2,6}\.\s*", "", inner)  # «англ.», «фр.»
        for part in re.split(r"[,;]|\s[—–-]\s|\sили\s", inner):
            part = part.strip(" «»\"")
            if part and len(part.split()) <= 3:
                alts.append(part)
    main = re.sub(r"\s*\([^()]*\)", "", term).strip()
    return main, alts, dates


def stem(word):
    """Основа для маски. Длинное слово режется до пяти букв: производные
    расходятся раньше окончания — «Спунеризм» → «Спунера», «Пилтдаунский» →
    «Пилтдауна»."""
    return word[:5] if len(word) >= 7 else word[: max(4, len(word) - 2)]


def mask_term(body, main, alts):
    """Прячет термин в тексте. Сначала фразы целиком, потом слова термина по
    основе — «Бойс» ловит «Бойса», «Ковентри» ловит «Ковентри» в любом падеже."""
    phrases = sorted({main, *alts, main.strip(" «»\"")}, key=len, reverse=True)
    for ph in phrases:
        if len(ph) >= 2:
            # С хвостом слова: «Папильотка» в «папильотками» — маска целиком,
            # а не «[…]ми».
            body = re.sub(r"(?<!\w)" + re.escape(ph) + r"\w*", MASK, body, flags=re.IGNORECASE)
    # Из вариантов в скобках по основе прячутся только имена: «(закон
    # ограничивающего фактора)» иначе спрятал бы все «законы» и «факторы».
    words = {w.lower() for w in _words(main)}
    words |= {w.lower() for ph in alts for w in _words(ph) if w[:1].isupper()}
    long_words = {w for w in words if len(w) >= 4 and w not in STOP_WORDS}
    stems = {stem(w) for w in long_words}
    # Термин из одних коротких слов («Ра», «ЛЭП») — только точным словом.
    exact = set() if long_words else {w for w in words if w not in STOP_WORDS}

    def repl(m):
        tok = m.group(0).lower()
        if tok in exact or any(tok.startswith(st) for st in stems):
            return MASK
        return m.group(0)

    body = re.sub(r"\w+", repl, body)
    body = re.sub(re.escape(MASK) + r"(?:[\s\-]*" + re.escape(MASK) + r")+", MASK, body)
    return body


def unmasked(front, main):
    """Слова лица, похожие на слово термина, но не спрятанные маской, — список
    для вычитки: основа ловит не всё («Лев» → «Льва»)."""
    out = []
    for w in {w.lower() for w in _words(main) if len(w) >= 6 and w.lower() not in STOP_WORDS}:
        for tok in _words(front):
            if tok.lower()[:4] == w[:4] and tok not in out:
                out.append(tok)
    return out


def prose_cards(src, sheet):
    images = {img["row"]: img["file"] for img in sheet.get("images", [])}
    out, dropped = [], []
    for r in sheet["rows"]:
        filled = [c.strip() for c in r["cells"] if c.strip()]
        if not filled:
            continue
        if src.get("inline"):
            # В листе-паре прозой считается только строка с одной первой ячейкой.
            if len(filled) != 1 or not r["cells"][0].strip():
                continue
        text = re.sub(r"\s+", " ", " ".join(filled))
        # Знак ударения рвёт слово для маски: «Шампольо́н» — два токена.
        # На обороте абзац остаётся с ударениями.
        head = split_head(text.replace("\u0301", ""))
        if head is None:
            if not src.get("inline"):
                dropped.append((src["sheet"], r["row"], text[:80]))
            continue
        term, body = head
        main, alts, dates = term_parts(term)
        # «Рой Лихтенштейн - (1923-1997) — американский…»: даты после тире.
        m = re.match(r"^\(([^()]*)\)\s*[—–-]+\s*", body)
        if m and re.search(r"\d", m.group(1)) and not re.search(r"[A-Za-zА-Яа-яЁё]{3,}", m.group(1)):
            dates.append(m.group(1).strip())
            body = body[m.end():]
        front = mask_term(body, main, alts)
        front = front[:1].upper() + front[1:]
        if dates:
            front = f"({', '.join(dates)}) {front}"
        card = {
            "id": card_id(src["deck"], text),
            "deck": src["deck"],
            "ask": PROSE_ASK,
            "front": front,
            "back": main,
            "note": text,
            "sheet": src["sheet"],
            "row": r["row"],
        }
        if r["row"] in images:
            card["image"] = images[r["row"]]
        out.append(card)
    return out, dropped


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
        # `sub` — замены по фрагменту: опечатка правится и на лице, и в абзаце
        # на обороте, а длинное лицо не переписывается целиком. Заменяются все
        # вхождения. Фрагмент,
        # которого больше нет ни там, ни там, роняет сборку, как устаревшая правка.
        # Третий элемент "front" — замена только на лице: так закрывается
        # термин, проскочивший сквозь маску в другом написании.
        for old, new, *where in fix.get("sub", []):
            hit = False
            for key in where or ("front", "back", "note"):
                if old in c.get(key, ""):
                    c[key] = c[key].replace(old, new)
                    hit = True
            if not hit:
                raise SystemExit(f"Правка {c['id']}: фрагмента «{old}» в карточке нет")
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
    dropped, prose_ids = [], set()
    for src in PROSE_SOURCES:
        if src["sheet"] not in sheets:
            raise SystemExit(f"В выгрузке нет листа «{src['sheet']}»")
        got, lost = prose_cards(src, sheets[src["sheet"]])
        dropped += lost
        for c in got:
            if c["id"] not in seen:
                seen.add(c["id"])
                prose_ids.add(c["id"])
                cards.append(c)
    cards = apply_fixes(cards, fixes)
    decks = [
        {"id": d, "title": t, "count": sum(1 for c in cards if c["deck"] == d)}
        for d, t in DECKS
    ]
    return {"source": dump["source"], "fetched": dump["fetched"], "decks": decks,
            "cards": cards, "dropped": dropped, "prose_ids": prose_ids}


def main():
    with open(DUMP, encoding="utf-8") as f:
        dump = json.load(f)
    fixes = {}
    if os.path.exists(FIXES):
        with open(FIXES, encoding="utf-8") as f:
            fixes = json.load(f)
    result = build(dump, fixes)
    dropped = result.pop("dropped")
    # Карточка с правкой уже вычитана: ложное срабатывание стража — правка
    # с одной причиной `why`.
    leaks = [(c["id"], c["back"], w) for c in result["cards"]
             if c["id"] in result["prose_ids"] and c["id"] not in fixes
             for w in [unmasked(c["front"], c["back"])] if w]
    result.pop("prose_ids")
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    for d in result["decks"]:
        print(f"  {d['title']}: {d['count']}")
    pics = sum(1 for c in result["cards"] if c.get("image"))
    print(f"{len(result['cards'])} карточек, с картинкой {pics}, правок {len(fixes)} -> {OUT}")
    print(f"Абзацев прозы без «Термин —»: {len(dropped)}")
    print(f"Похоже на термин сквозь маску: {len(leaks)}")
    for cid, back, words in leaks:
        print(f"  {cid} {back}: {words}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
