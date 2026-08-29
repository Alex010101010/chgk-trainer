"""Сборка ассета вопросов для приложения (T2b).

`data/gq_clean.json` → `app/assets/questions.json`. Ассет не коммитится: он
детерминированно выводится из дампа, который уже в git, а T11 перегоняет
корпус не раз — каждая перегонка иначе клала бы в историю новый блоб на 8.5 МБ.
Забытая генерация не даёт пустой экран: несобранный ассет роняет `flutter test`.
"""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
GQ_IN = os.path.join(ROOT, "data", "gq_clean.json")
TEHNIKI = os.path.join(ROOT, "app", "assets", "tehniki.json")
OUT = os.path.join(ROOT, "app", "assets", "questions.json")

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
        out.append(item)
    # `count` ловит обрезанный файл: без него усечённый ассет распарсится как
    # валидный короткий список и режим молча пойдёт по огрызку корпуса.
    return {"v": ASSET_VERSION, "count": len(out), "questions": out}


def main():
    with open(GQ_IN, encoding="utf-8") as f:
        rows = json.load(f)
    asset = build(rows)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(asset, f, ensure_ascii=False, separators=(",", ":"))
    size_mb = os.path.getsize(OUT) / 1024 / 1024
    print(f"{asset['count']} вопросов -> {OUT} ({size_mb:.2f} МБ)")
    marked = {}
    for q in asset["questions"]:
        for t in q["tehniki"]:
            marked[t] = marked.get(t, 0) + 1
    for t, n in sorted(marked.items()):
        print(f"    приём {t}: эталон на {n} вопросах")
    return 0


if __name__ == "__main__":
    sys.exit(main())
