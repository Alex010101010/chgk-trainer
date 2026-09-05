"""Сборка ассетов приложения (T2b, T3, T14).

`data/gq_clean.json` + `data/bingo_clean.json` → `app/assets/questions.json`.
Корпуса лежат в одном файле и различаются полем `corpus`: режим бинго читает
оба (отвлекающие вопросы — из gq), и второй ассет всё равно грузился бы вместе
с первым, зато кешей стало бы два. Ассет не коммитится: он
детерминированно выводится из дампа, который уже в git, а T11 перегоняет
корпус не раз — каждая перегонка иначе клала бы в историю новый блоб на 8.5 МБ.
Забытая генерация не даёт пустой экран: несобранный ассет роняет `flutter test`.

Вторым файлом едет `app/assets/articles.json` — справка по клише из
`data/bingo_articles.json`. Отдельным ассетом, а не полем вопроса: справка
одна на тему (их 333), а вопросов 8.5 тысяч, и в вопросах она лежала бы
тридцатью копиями каждая. Читается лениво, при первом открытии карточки.
"""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
GQ_IN = os.path.join(ROOT, "data", "gq_clean.json")
BINGO_IN = os.path.join(ROOT, "data", "bingo_clean.json")
ARTICLES_IN = os.path.join(ROOT, "data", "bingo_articles.json")
TEHNIKI = os.path.join(ROOT, "app", "assets", "tehniki.json")
HANDOUTS = os.path.join(ROOT, "app", "assets", "handouts")
OUT = os.path.join(ROOT, "app", "assets", "questions.json")
ARTICLES_OUT = os.path.join(ROOT, "app", "assets", "articles.json")

# Версия формата ассета. Читатель — `AssetQuestionRepository`.
ASSET_VERSION = 1

# Поля, которые едут в приложение. `tournament` и `complexity` не едут:
# экран раскрытия их не показывает, а `complexity` вдобавок нельзя трактовать
# как процент взятия (у части вопросов там два числа, см. «Состояние контента»).
FIELDS = (
    "id",
    "corpus",
    "question",
    "answer",
    "acceptance",
    "acceptVariants",
    "comment",
    "sources",
    "author",
    # Настоящее клише. У gq всегда None, у бинго — название темы сетки (T3).
    "theme",
    # Имя файла раздатки в `app/assets/handouts/` (T20). None — раздатки нет.
    "handout",
    # Эталон приёмов: проставляется здесь, а не в приложении. Регулярки живут
    # в авторском `tehniki.json` рядом с объяснением приёма — приложение их
    # не видит и не исполняет.
    "tehniki",
)

# Формулировки зачёта, не несущие информации: «зачёт: точный ответ» на экране
# — просто шум. Среди годных таких 397 из 2448 непустых.
ACCEPTANCE_BOILERPLATE = {"точный ответ", "по смыслу"}


def is_boilerplate(acceptance):
    if not acceptance:
        return True
    return re.sub(r"[\s.]+$", "", acceptance.strip().lower()) in ACCEPTANCE_BOILERPLATE


def load_tehniki():
    with open(TEHNIKI, encoding="utf-8") as f:
        return json.load(f)["tehniki"]


def handout_file(row):
    """Имя файла раздатки для вопроса или None.

    Падаем, а не кладём вопрос без картинки: санитайзер вернул его в корпус
    именно потому, что картинка есть, и «Перед вами…» без раздатки — это
    вопрос, который нельзя взять.
    """
    if not row.get("handoutImage"):
        return None
    for ext in (".jpg", ".png"):
        if os.path.exists(os.path.join(HANDOUTS, row["id"] + ext)):
            return row["id"] + ext
    raise SystemExit(
        f"Нет раздатки для вопроса {row['id']}. "
        f"Собери картинки: python3 scripts/build_handout_assets.py"
    )


def detect_tehniki(row, tehniki):
    """Эталон приёмов — высокая точность, низкая полнота.

    Приём засчитан, только если правило сработало по **комментарию** и НЕ
    сработало по тексту вопроса: во втором случае приём объявлен в самом
    вопросе, и угадывать нечего. Отсутствие приёма в этом списке не значит,
    что приёма нет, — поэтому «нет» здесь не эталон, а незнание.
    """
    found = []
    for t in tehniki:
        rx = re.compile(t["detect"])
        if rx.search(row.get("comment") or "") and not rx.search(row.get("question") or ""):
            found.append(t["id"])
    return found


def build(rows, tehniki=None):
    tehniki = tehniki if tehniki is not None else load_tehniki()
    out = []
    for r in rows:
        if r.get("excluded") is not None:
            continue
        item = {k: r.get(k) for k in FIELDS}
        if is_boilerplate(item["acceptance"]):
            item["acceptance"] = None
        item["tehniki"] = detect_tehniki(r, tehniki)
        item["handout"] = handout_file(r)
        out.append(item)
    # `count` ловит обрезанный файл: без него усечённый ассет распарсится как
    # валидный короткий список и режим молча пойдёт по огрызку корпуса.
    return {"v": ASSET_VERSION, "count": len(out), "questions": out}


def build_articles(rows):
    """Справка едет только для тем, которые есть в собранном корпусе: тема без
    вопросов в сетку не попадёт, и открывать её справку неоткуда."""
    themes = {q["theme"] for q in rows if q.get("theme")}
    if not os.path.exists(ARTICLES_IN):
        raise SystemExit(
            f"Нет {ARTICLES_IN}. Собери справки: "
            f"python3 scripts/structure_bingo_articles.py"
        )
    with open(ARTICLES_IN, encoding="utf-8") as f:
        articles = [a for a in json.load(f) if a["theme"] in themes]
    return {"v": ASSET_VERSION, "count": len(articles), "articles": articles}


def load_rows():
    rows = []
    for path in (GQ_IN, BINGO_IN):
        with open(path, encoding="utf-8") as f:
            rows.extend(json.load(f))
    return rows


def main():
    asset = build(load_rows())
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(asset, f, ensure_ascii=False, separators=(",", ":"))
    size_mb = os.path.getsize(OUT) / 1024 / 1024
    print(f"{asset['count']} вопросов -> {OUT} ({size_mb:.2f} МБ)")
    by_corpus = {}
    for q in asset["questions"]:
        by_corpus[q["corpus"]] = by_corpus.get(q["corpus"], 0) + 1
    themes = {q["theme"] for q in asset["questions"] if q["theme"]}
    handouts = sum(1 for q in asset["questions"] if q["handout"])
    print(f"    корпуса: {by_corpus}, тем бинго: {len(themes)}, раздаток: {handouts}")
    marked = {}
    for q in asset["questions"]:
        for t in q["tehniki"]:
            marked[t] = marked.get(t, 0) + 1
    for t, n in sorted(marked.items()):
        print(f"    приём {t}: эталон на {n} вопросах")

    articles = build_articles(asset["questions"])
    with open(ARTICLES_OUT, "w", encoding="utf-8") as f:
        json.dump(articles, f, ensure_ascii=False, separators=(",", ":"))
    without = len(themes) - articles["count"]
    print(f"{articles['count']} справок -> {ARTICLES_OUT} (без справки тем: {without})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
