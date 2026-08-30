"""Разбор блоков статей индекса в вопросы (T16, шаг 3).

`data/bingo_index_dump.json` → `data/bingo_index_questions.json`, поля один в
один как у `structure_bingo_dump.py` — дальше обе цепочки сходятся в санитайзере.

Формат в статьях плавает сильнее, чем в вики, и парсер здесь снисходительный
намеренно: метка вопроса встречается как `Вопрос 5:`, `Вопрос #2:`, `Вопрос 35`
без двоеточия, `Вопрос` без номера, `Вопрос-дуплет.` и `ВОПРОС 34` внутри строки
турнира. Строгий парсер потерял бы примерно шестьдесят вопросов молча.
"""
import json
import os
import re

from structure_bingo_dump import slugify

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
IN_JSON = os.path.join(DATA_DIR, "bingo_index_dump.json")
OUT_JSON = os.path.join(DATA_DIR, "bingo_index_questions.json")

# Метка вопроса. Номер необязателен: у части статей он живёт в строке турнира
# («БЕСКОНЕЧНЫЕ ЗЕМЛИ: ТОМ XI, ВОПРОС 34»), а сам блок начинается просто с «Вопрос».
QUESTION_MARKER = re.compile(
    r"(?i)^\s*вопрос(?:ы)?\b[\s ]*[№#]?[\s ]*(\d+)?[\s ]*"
    r"(?:[-–—]\s*(?:дуплет|блиц))?[\s ]*[:.\)]?[\s ]*"
)

# Метки полей. `Источники` без скобок и `ИСТОЧНИКИ` капсом — тоже они.
FIELD_LABELS = [
    ("answer", r"ответ"),
    ("acceptance", r"зач[её]т"),
    ("comment", r"коммент\w*"),
    ("sources", r"источник\w*(?:\(и\))?|источники"),
    ("author", r"автор\w*(?:\(ы\))?|авторы"),
]
FIELD_RE = re.compile(
    r"(?i)^\s*(?:" + "|".join(f"(?P<{k}>{p})" for k, p in FIELD_LABELS) + r")\s*:\s*"
)

# Метка вопроса не в начале строки: «… 2008-04-18 Вопрос 4: …». Номер обязателен —
# иначе резало бы по слову «вопрос» в обычной прозе.
EMBEDDED_MARKER = re.compile(r"(?i)\bвопрос\s*[№#]?\s*\d+\s*[:.]?")

# Разделитель между вопросами одной темы — блок целиком из «ИЛИ».
OR_SEPARATOR = re.compile(r"(?i)^\s*(?:или|\*{2,}|—{2,})\s*$")

# Блок-объявление раздатки: сама раздатка идёт следующим блоком — картинкой
# либо текстом. Встречается и в скобках: «[Раздатка:]».
HANDOUT_DECLARATION = re.compile(
    r"(?i)^\s*\[?\s*(?:раздаточн\w+\s+материал|раздатка)\s*:?\s*\]?\s*$"
)
# Тот же маркер в начале текста вопроса: «[Раздатка: ] Назовите француза…».
HANDOUT_PREFIX = re.compile(r"(?i)^\s*\[\s*(?:раздаточн\w+\s+материал|раздатка)\s*:?\s*\]?\s*")

# Строка турнира: «Кубок Гармонии. Элемент Шестой: Магия · Июнь 2022». Двоеточие
# внутри неё есть, поэтому по двоеточию её опознавать нельзя — только по виду:
# коротко, с точкой-разделителем или годом.
TOURNAMENT_HINT = re.compile(r"·|\b(?:19|20)\d{2}\b|\bтур\b|\bэтап\b|\bчемпионат\b|\bкубок\b", re.I)
TOURNAMENT_MAX = 160


def is_marker(text):
    m = QUESTION_MARKER.match(text)
    if not m:
        return None
    rest = text[m.end():].strip()
    # «Вопросы Дмитрия Жаркова, клуб "Мозговорот"» — это заголовок подборки,
    # а не метка вопроса: за меткой либо ничего, либо сам текст вопроса.
    if text.lower().lstrip().startswith("вопросы") and not m.group(1):
        return None
    return {"number": m.group(1), "rest": rest}


def is_field(text):
    m = FIELD_RE.match(text)
    if not m:
        return None
    name = m.lastgroup
    return {"name": name, "value": text[m.end():].strip()}


def looks_like_tournament(block):
    if block["type"] not in ("quote", "p", "heading"):
        return False
    text = block["text"]
    if not text or len(text) > TOURNAMENT_MAX:
        return False
    if is_marker(text) or is_field(text):
        return False
    return bool(TOURNAMENT_HINT.search(text))


# Границы между пронумерованными источниками в одной строке. Номер ограничен
# двумя цифрами, иначе резало бы «1999. — С. 42.» внутри одной библиографической
# ссылки. Вторая ветка — без пробела перед номером: у 222 записей ссылка
# упирается прямо в следующий номер («…/451235/2. http://…»), и правило,
# требующее пробел, оставляло их одной склейкой.
SOURCE_SPLIT = re.compile(r"\s(?=[1-9]\d?\.\s)|(?<=\S)\s*(?=[1-9]\d?\.\s*https?://)")


def split_sources(value):
    parts = SOURCE_SPLIT.split(value)
    parts = [re.sub(r"^[1-9]\d?\.\s*", "", p).strip() for p in parts]
    return [p for p in parts if p]


def collect_record(blocks, start, end, taken_tournament, skip=None):
    """Один вопрос из блоков [start, end). `start` — блок с меткой вопроса.

    `skip` — номер блока, уже отданного под строку турнира. В notion он идёт
    ПОСЛЕ метки, и без этого его текст уезжает в начало вопроса: «Скрулл Кап:
    второй этап · июнь 2022 Герой романа под названием «Кишот»…».
    """
    marker = is_marker(blocks[start]["text"])
    question_parts = [marker["rest"]] if marker["rest"] else []
    handout_images = []
    fields = {"answer": None, "acceptance": None, "comment": None, "sources": [], "author": None}
    current = None
    in_body = True

    for i in range(start + 1, end):
        if i == skip:
            continue
        block = blocks[i]
        text = block["text"]
        if OR_SEPARATOR.match(text):
            continue
        field = is_field(text)
        if field:
            in_body = False
            current = field["name"]
            value = field["value"]
            if current == "sources":
                fields["sources"] = split_sources(value)
            else:
                fields[current] = value
            continue
        if in_body:
            # Картинка внутри тела вопроса — это раздатка, а не иллюстрация темы.
            handout_images.extend(img["src"] for img in block["images"])
            if not HANDOUT_DECLARATION.match(text) and text:
                question_parts.append(text)
        elif current and text and not block["images"]:
            # Продолжение последнего поля: длинный комментарий бывает разбит на
            # несколько блоков.
            if current == "sources":
                fields["sources"].extend(split_sources(text))
            elif fields[current]:
                fields[current] = f"{fields[current]} {text}"

    question = HANDOUT_PREFIX.sub("", " ".join(p for p in question_parts if p)).strip()
    # «Вопрос*:» + картинка — вопрос, текст которого и есть картинка. Пустой
    # текст здесь не ошибка разбора: запись едет дальше, а негодной её объявит
    # санитайзер — и с причиной, а не молчаливым выпадением из корпуса.
    question = "" if not re.search(r"\w", question) else question
    if not fields["answer"]:
        return None
    return {
        "tournament": taken_tournament,
        "question": question,
        "answer": fields["answer"],
        "acceptance": fields["acceptance"],
        "comment": fields["comment"],
        "sources": fields["sources"],
        "author": fields["author"],
        "handoutImage": handout_images[0] if handout_images else None,
    }


def record_end(blocks, start, next_start):
    """Запись кончается там, где после полей пошла проза статьи или разделитель.

    Иначе следующий абзац «как это выглядит» уехал бы в `Автор` предыдущего
    вопроса — а он идёт вплотную и в vk, и в телеграфе.
    """
    seen_field = False
    for i in range(start + 1, next_start):
        text = blocks[i]["text"]
        if is_field(text):
            seen_field = True
            continue
        if OR_SEPARATOR.match(text):
            return i
        if seen_field and blocks[i]["type"] in ("p", "heading", "figure", "list"):
            return i
    return next_start


def split_embedded_markers(blocks):
    """Разрезать блоки, где турнир и метка склеены в одну строку.

    «БЕСКОНЕЧНЫЕ ЗЕМЛИ: ТОМ XI, ВОПРОС 34» и «X Чемпионат Украины … 2008-04-18
    Вопрос 4: Одна из народных примет…» — метка не в начале строки, и парсер,
    ищущий её только с начала, теряет вопрос целиком.

    Возвращает новый список блоков и номера тех, что заведомо являются строкой
    турнира: их не надо опознавать эвристикой, они получены разрезом.
    """
    out = []
    forced = set()
    for block in blocks:
        text = block["text"]
        m = EMBEDDED_MARKER.search(text) if block["type"] == "quote" else None
        prefix = text[: m.start()].strip() if m else ""
        if not m or not prefix or len(prefix) > TOURNAMENT_MAX or is_field(prefix):
            out.append(block)
            continue
        forced.add(len(out))
        out.append({"type": "quote", "text": prefix, "images": []})
        out.append({"type": "quote", "text": text[m.start():].strip(), "images": block["images"]})
    return out, forced


def structure_article(article):
    blocks, forced_tournament = split_embedded_markers(article.get("blocks") or [])
    starts = [i for i, b in enumerate(blocks) if is_marker(b["text"])]
    slug = slugify(article["name"])
    out = []
    used_tournament = set()

    # Турниры разбираются до записей: строка турнира следующего вопроса стоит
    # вплотную к полям предыдущего, и без этого она уезжает хвостом в его
    # `Автор` или `Источники`.
    tournament_at = {}
    for start in starts:
        for back in (start - 1, start - 2):
            if back < 0 or back in used_tournament:
                continue
            if back in forced_tournament or looks_like_tournament(blocks[back]):
                tournament_at[start] = back
                used_tournament.add(back)
                break

    for n, start in enumerate(starts):
        next_start = starts[n + 1] if n + 1 < len(starts) else len(blocks)
        end = min(record_end(blocks, start, next_start),
                  tournament_at.get(next_start, next_start))

        taken = tournament_at.get(start)
        tournament = blocks[taken]["text"] if taken is not None else None
        # В notion блок метки — голое «Вопрос 35», а турнир идёт следующей
        # строкой, уже после неё.
        skip = None
        if tournament is None and start + 1 < end and looks_like_tournament(blocks[start + 1]):
            tournament = blocks[start + 1]["text"]
            used_tournament.add(start + 1)
            skip = start + 1

        record = collect_record(blocks, start, end, tournament, skip=skip)
        if not record:
            continue
        out.append({
            "id": f"ix-{slug}-{len(out) + 1}",
            "theme": article["name"],
            "source": "index",
            "articleUrl": article["url"],
            **record,
        })
    return out


def main():
    with open(IN_JSON, encoding="utf-8") as f:
        articles = json.load(f)

    all_questions = []
    per_article = []
    for article in articles:
        questions = structure_article(article)
        per_article.append((article["name"], len(questions)))
        all_questions.extend(questions)

    zero = [name for name, count in per_article if count == 0]
    print(f"Статей обработано: {len(per_article)}")
    print(f"Всего вопросов извлечено: {len(all_questions)}")
    print(f"С раздаткой-картинкой: {sum(1 for q in all_questions if q['handoutImage'])}")
    print(f"Без турнира: {sum(1 for q in all_questions if not q['tournament'])}")
    print(f"Статей с 0 вопросов: {len(zero)}")
    for name in zero:
        print(f"    {name}")

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(all_questions, f, ensure_ascii=False, indent=2)
    print(f"Сохранено в {OUT_JSON}")


if __name__ == "__main__":
    main()
