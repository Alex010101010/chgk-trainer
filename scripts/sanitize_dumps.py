"""Санитайзер дампов (T11).

Чистая функция «сырой дамп → чистый»: сырые файлы остаются нетронутым выводом
краулера, результат ложится рядом в `*_clean.json`. Ничего не удаляется —
отбракованное едет с полем-причиной, чтобы не краулить заново.
"""
import json
import os
import random
import re
import sys

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
GQ_IN = os.path.join(DATA_DIR, "gotquestions_dump.json")
# Бинго-корпус собирается из двух источников: вики (T1) и статей индекса (T16).
# Ниже по конвейеру корпус один — `bingo_clean.json`, — а разводит их поле
# `source`. Отдельный третий вход пришлось бы не забыть подключить в санитайзере,
# отчёте, T3 и T14; ровно там половина корпуса и теряется молча.
BINGO_IN = (
    (os.path.join(DATA_DIR, "bingo_questions.json"), "wiki"),
    (os.path.join(DATA_DIR, "bingo_index_questions.json"), "index"),
)
GQ_OUT = os.path.join(DATA_DIR, "gq_clean.json")
BINGO_OUT = os.path.join(DATA_DIR, "bingo_clean.json")
REPORT = os.path.join(DATA_DIR, "sanitize_report.json")
SAMPLE = os.path.join(DATA_DIR, "sanitize_sample.json")

# Темы-приёмы, а не темы-ответы: в вопросе «к какой из девяти» они
# несопоставимы с остальными, поэтому из пула сеток исключаются целиком.
META_THEMES = {"МетаЧГК", "Сленг ЧГК", "Замена по цитате", "Переворот раздатки"}

HOST_INSTRUCTION = re.compile(
    r"^\s*\[\s*(?:Ведущему|Чтецу|Читающему|Указание|Примечание|Замечание)[^\]]*\]\s*",
    re.IGNORECASE,
)

RE_HANDOUT_START = re.compile(r"(?i)^\s*перед вами")
RE_HANDOUT = re.compile(
    # «Чёрным прямоугольником скрыты…» — раздатка, не называющая себя раздаткой.
    r"(?i)(раздаточн|(?:чёрн|черн)\w*\s+(?:прямоугольник|квадрат)\w*\s+скрыт)"
)
# `прослушайте` в правило НЕ входит: в ЧГК это обращение к чтецу, а сам
# фрагмент приведён тут же текстом. Вычитка выборки показала, что по нему
# отбраковывались вполне играбельные вопросы — 58 в gq и 13 в bingo.
RE_MEDIA = re.compile(
    r"(?i)(\.jpg|\.jpeg|\.png|\.gif|/pics?/"
    r"|видеофрагмент|видеовопрос|аудиофрагмент|\[\s*аудио)"
)
# Либо маркер в начале строки, либо упоминание вместе с нумерацией частей:
# «"Анатомический" блиц … 1. … 2. …» — блиц, а «команда выиграла блиц на
# турнире» — содержание вопроса, и нумерации там нет.
RE_DUPLET_LINE = re.compile(r"(?im)^\s*\[?\s*(дуплет|блиц)")
RE_DUPLET_WORD = re.compile(r"(?i)\b(дуплет|блиц)")
RE_ENUMERATED = re.compile(r"(?s)\b1\s*[.)]\s.*\b2\s*[.)]\s")

# `acceptance` с таким содержимым не несёт ни одного синонима. Класть его в
# варианты значит сравнивать ответ игрока со строкой «точный ответ».
ACCEPTANCE_BOILERPLATE = {"точный ответ", "по смыслу", "только точный ответ"}

# «Атомный реактор. Незачет: Термоядерный реактор.» — всё после этого маркера
# перечисляет ответы, которые НЕ принимаются. Затащить их в варианты значит
# подсказывать «взял» на заведомо неверном ответе.
REJECTION_MARKER = re.compile(r"(?i)\bнезач[её]т\w*\b")


def as_text(value):
    if value is None:
        return ""
    if isinstance(value, list):
        return " ".join(str(v) for v in value)
    return str(value)


def clean_question(text):
    """Чинит то, что чинится: инструкция ведущему в квадратных скобках —
    служебная пометка для чтеца, сам вопрос без неё остаётся рабочим."""
    text = HOST_INSTRUCTION.sub("", text)
    text = text.replace("\xa0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def exclusion_reason(question, answer, theme, raw_question=None, handout_image=None):
    """Первое сработавшее правило. Только структурные маркеры: `^Внимание`
    сюда не входит — из 195 gq-совпадений почти все это «Внимание, слово
    АЛЬФА в вопросе — замена», то есть полностью играбельный вопрос.

    Подстрочные правила смотрят на ИСХОДНЫЙ текст, а не на очищенный: сама
    инструкция чтецу бывает единственным признаком раздатки («[Указание
    организаторам по раздаточному материалу: …]»), и срезав её первой,
    санитайзер перестал бы эту раздатку видеть.
    """
    raw = raw_question if raw_question is not None else question
    # Пустой текст при живой картинке — это вопрос-картинка, а не пустышка.
    if not question.strip() and not handout_image:
        return "empty", "пустой текст вопроса"
    # `answer` вида «.» встречается и после нормализации превращается в пустоту:
    # играть по такому вопросу нельзя, значит это отсутствие ответа.
    if not normalize_answer(answer):
        return "no_answer", "пустой ответ"
    if theme in META_THEMES:
        return "meta_theme", "тема-приём, а не тема-ответ"
    # Раздатка (T20). Картинка скачана локально — вопрос играбелен: цикл её
    # показывает. Наличие файла закрывает разбор раздатки ЦЕЛИКОМ, а не снимает
    # одно правило: без этого следующая проверка ловит 40 из 105 вопросов — те
    # самые, где текст прямо ссылается на картинку («Перед вами…»).
    #
    # Раздатка без файла остаётся браком: показать «Перед вами…» без картинки
    # хуже, чем не показать вопрос вовсе.
    if not handout_image:
        # `^перед вами` — по очищенному тексту: инструкция чтецу могла стоять
        # перед ним.
        if RE_HANDOUT_START.search(question) or RE_HANDOUT.search(raw):
            return "handout", "раздаточный материал"
    if RE_MEDIA.search(raw):
        return "media", "картинка, аудио или видео"
    if RE_DUPLET_LINE.search(raw) or (
        RE_DUPLET_WORD.search(raw) and RE_ENUMERATED.search(raw)
    ):
        return "duplet", "дуплет или блиц"
    return None, None


def normalize_answer(text):
    text = text.replace("\xa0", " ").replace("ё", "е").replace("Ё", "Е")
    text = re.sub(r"\s+", " ", text).strip()
    # По кругу до неподвижной точки: у «"AC/DC".» кавычка становится хвостовой
    # только после снятия точки, и за один проход её не убрать.
    previous = None
    while previous != text:
        previous = text
        text = text.strip("\"«»'“”").strip()
        text = text.rstrip(" .!?;,").strip()
    return text.lower()


def _split_alternatives(text):
    """Слэш считается разделителем только с пробелами по обе стороны:
    «рапира / сабля» — это варианты, а «AC/DC», «5/9 градуса» и «1984 1/2» —
    один ответ, и разрезав их, мы бы подсказывали «взял» за ответ «AC»."""
    parts = re.split(r"(?i)\s+или\s+|\s+/\s+|\s*;\s*", text)
    return [p for p in (part.strip() for part in parts) if p]


def _forms(text):
    """Формы одного ответа: скобки в ЧГК-ответах значат разное.

    `[…]` — необязательная часть: «[король] Артур» принимается и как «Артур»,
    и как «король Артур», но само «король» ответом не является. Таких ответов
    528 из 9915, и без разбора они давали вариант с буквальными скобками,
    который не совпал бы ни с чем.

    `(…)` — чаще полная форма того же ответа («Уорхол (Энди Уорхол)»), но
    иногда пояснение («Температуру воздуха (1 градус по Фаренгейту равен 5/9
    градуса по Цельсию)»). Содержимое скобок берётся вариантом только в первом
    случае — он опознаётся тем, что текст снаружи входит в текст внутри.
    """
    forms = [text]
    inside = re.findall(r"\(([^)]*)\)", text)
    if inside:
        without = re.sub(r"\s*\([^)]*\)", "", text)
        forms.append(without)
        outside_norm = normalize_answer(without)
        for part in inside:
            if outside_norm and outside_norm in normalize_answer(part):
                forms.append(part)
    if "[" in text:
        forms.append(re.sub(r"[\[\]]", "", text))
        forms.append(re.sub(r"\s*\[[^\]]*\]\s*", " ", text))
    return forms


def accept_variants(answer, acceptance):
    """Варианты, с которыми T2a сравнивает версию игрока.

    Хвостовая точка есть у 85% ответов gq и 97% bingo — без её снятия матч
    промахивается почти всегда, поэтому нормализация здесь не косметика.
    """
    raw = list(_forms(answer))

    acceptance = REJECTION_MARKER.split(acceptance, maxsplit=1)[0]
    acceptance_norm = normalize_answer(acceptance)
    if acceptance and acceptance_norm not in ACCEPTANCE_BOILERPLATE:
        raw.extend(_forms(acceptance))
        raw.extend(re.findall(r"[\"«]([^\"»]+)[\"»]", acceptance))

    variants = []
    for chunk in raw:
        for part in [chunk] + _split_alternatives(chunk):
            value = normalize_answer(part)
            if value and "[" not in value and "]" not in value and value not in variants:
                variants.append(value)
    return variants


def sanitize(rows, corpus):
    out = []
    for row in rows:
        question = clean_question(as_text(row.get("question")))
        answer = as_text(row.get("answer"))
        acceptance = as_text(row.get("acceptance"))
        theme = as_text(row.get("theme")) or None

        reason, note = exclusion_reason(
            question,
            answer,
            theme,
            raw_question=as_text(row.get("question")),
            handout_image=row.get("handoutImage"),
        )
        record = dict(row)
        record["corpus"] = corpus
        record["question"] = question
        if question != as_text(row.get("question")):
            record["questionRaw"] = as_text(row.get("question"))
        record["excluded"] = reason
        record["excludedBy"] = note
        record["acceptVariants"] = accept_variants(answer, acceptance)
        out.append(record)
    return out


def report_for(rows):
    reasons = {}
    for row in rows:
        key = row["excluded"] or "kept"
        reasons[key] = reasons.get(key, 0) + 1
    kept = [r for r in rows if not r["excluded"]]
    themes = {}
    for row in kept:
        theme = as_text(row.get("theme"))
        if theme:
            themes[theme] = themes.get(theme, 0) + 1
    by_source = {}
    for row in kept:
        source = row.get("source")
        if source:
            by_source[source] = by_source.get(source, 0) + 1
    return {
        "всего": len(rows),
        "осталось": len(kept),
        "по причинам": reasons,
        "по источникам": by_source,
        "повторов помечено": sum(1 for r in rows if r.get("duplicateOf")),
        "тем осталось": len(themes),
        "тем с 3+ вопросами": sum(1 for n in themes.values() if n >= 3),
        "пустых acceptVariants при непустом ответе": sum(
            1 for r in kept if as_text(r.get("answer")).strip() and not r["acceptVariants"]
        ),
        # Разведено намеренно: в gq остаточные U+FFFD сидят внутри URL в
        # `sources` — это битые ссылки на стороне источника, игроку они не
        # показываются. Порча в тексте вопроса — совсем другое дело.
        "U+FFFD в тексте": sum(
            as_text(r.get(f)).count("�")
            for r in rows
            for f in ("question", "answer", "acceptance", "comment")
        ),
        "U+FFFD в ссылках": sum(
            as_text(r.get("sources")).count("�") for r in rows
        ),
    }


def write_sample(rows, path, seed=20260829):
    """Выборка под ручную вычитку: фильтр, выведенный из одних плохих примеров,
    систематически режет здоровое, и узнать об этом можно только глазами."""
    rnd = random.Random(seed)
    excluded = [r for r in rows if r["excluded"]]
    kept = [r for r in rows if not r["excluded"]]
    sample = {
        "отбраковано (30)": [
            {"id": r.get("id"), "excluded": r["excluded"], "question": r["question"][:400]}
            for r in rnd.sample(excluded, min(30, len(excluded)))
        ],
        "пропущено (30)": [
            {"id": r.get("id"), "question": r["question"][:400]}
            for r in rnd.sample(kept, min(30, len(kept)))
        ],
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(sample, f, ensure_ascii=False, indent=2)


def load_gq():
    with open(GQ_IN, encoding="utf-8") as f:
        return json.load(f)


def load_bingo():
    """Оба источника бинго одним списком, с проставленным `source`."""
    rows = []
    for path, source in BINGO_IN:
        if not os.path.exists(path):
            raise SystemExit(
                f"нет {os.path.basename(path)} — собери его: "
                f"python3 scripts/{'structure_bingo_dump.py' if source == 'wiki' else 'crawl_bingo_index.py && python3 scripts/structure_bingo_index.py'}"
            )
        with open(path, encoding="utf-8") as f:
            rows.extend({**row, "source": row.get("source", source)} for row in json.load(f))
    return rows


def mark_duplicates(rows):
    """Один и тот же турнирный вопрос попадается и в gq, и в бинго.

    Ничего не удаляется — принцип T11: помечается `duplicateOf`, чтобы T3 мог
    не показывать в «Бинго» то, что игрок уже проходил в «Классике».
    """
    seen = {}
    duplicates = 0
    for row in rows:
        key = duplicate_key(row.get("question"))
        if not key:
            continue
        if key in seen and seen[key] != row.get("id"):
            row["duplicateOf"] = seen[key]
            duplicates += 1
        else:
            seen.setdefault(key, row.get("id"))
    return duplicates


def duplicate_key(question):
    """Первые 120 значащих символов: у одного вопроса в двух базах расходятся
    пунктуация, кавычки и хвост про «Назовите…», а начало совпадает."""
    text = re.sub(r"[^а-яa-z0-9 ]", " ", (question or "").lower().replace("ё", "е"))
    text = re.sub(r"\s+", " ", text).strip()[:120]
    return text or None


def main(seed=20260829):
    report = {}
    all_rows = []
    corpora = []
    for corpus, rows, dst in (("gq", load_gq(), GQ_OUT), ("bingo", load_bingo(), BINGO_OUT)):
        cleaned = sanitize(rows, corpus)
        corpora.append((corpus, cleaned, dst))

    # Дедуп — по обоим корпусам разом: gq идёт первым, поэтому оригиналом
    # считается он, а помечается повтор в бинго.
    duplicates = mark_duplicates([r for _, cleaned, _ in corpora for r in cleaned])
    print(f"Повторов между корпусами помечено: {duplicates}")

    for corpus, cleaned, dst in corpora:
        with open(dst, "w", encoding="utf-8") as f:
            json.dump(cleaned, f, ensure_ascii=False, indent=2)
        report[corpus] = report_for(cleaned)
        all_rows.extend(cleaned)

        print(f"{corpus}: {report[corpus]['осталось']}/{report[corpus]['всего']} -> {dst}")
        for key, count in sorted(report[corpus]["по причинам"].items()):
            print(f"    {key}: {count}")

    with open(REPORT, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    write_sample(all_rows, SAMPLE, seed=seed)
    print(f"Отчёт: {REPORT}; выборка под вычитку: {SAMPLE}")


if __name__ == "__main__":
    # Другой сид — другая выборка под вычитку: проверять правило на той же
    # выборке, по которой его правил, значит проверять подгонку.
    main(seed=int(sys.argv[1]) if len(sys.argv) > 1 else 20260829)
