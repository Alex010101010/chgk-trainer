"""Сводка по импорту индекса бинго (T16, шаг 7).

Числа, которыми задача закрывается, печатает сам скрипт — чтобы их не пришлось
восстанавливать грепом и чтобы следующий прогон было с чем сравнить.
"""
import json
import os
import re
from collections import Counter, defaultdict

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
DUMP = os.path.join(DATA_DIR, "bingo_index_dump.json")
QUESTIONS = os.path.join(DATA_DIR, "bingo_index_questions.json")
IMAGES = os.path.join(DATA_DIR, "bingo_images.json")
CLEAN = os.path.join(DATA_DIR, "bingo_clean.json")
OUT = os.path.join(DATA_DIR, "bingo_index_report.json")

FIELDS = ("question", "answer", "acceptance", "comment", "sources", "author",
          "tournament", "handoutImage")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def theme_key(name):
    """Сравнение имён тем: ё, регистр и пунктуация не должны разводить одну тему."""
    return re.sub(r"[^а-яa-z0-9 ]", " ", (name or "").lower().replace("ё", "е")).strip()


def percentiles(values):
    if not values:
        return {}
    ordered = sorted(values)
    return {
        "мин": ordered[0],
        "медиана": ordered[len(ordered) // 2],
        "макс": ordered[-1],
        "среднее": round(sum(ordered) / len(ordered), 1),
    }


def build():
    articles = load(DUMP)
    questions = load(QUESTIONS)
    images = load(IMAGES)
    clean = load(CLEAN)

    per_article = Counter(q["theme"] for q in questions)
    zero = [a["name"] for a in articles if not per_article.get(a["name"])]

    by_host = defaultdict(lambda: {"статей": 0, "взято": 0, "вопросов": 0})
    for article in articles:
        row = by_host[article["host"]]
        row["статей"] += 1
        if article.get("blocks"):
            row["взято"] += 1
        row["вопросов"] += per_article.get(article["name"], 0)

    images_by_host = defaultdict(lambda: {"ok": 0, "недоступно": 0})
    for image in images:
        images_by_host[image["host"]]["ok" if image["status"] == "ok" else "недоступно"] += 1
    ok_images = [i for i in images if i["status"] == "ok"]

    wiki_themes = {theme_key(r.get("theme")) for r in clean if r.get("source") == "wiki"}
    index_themes = {theme_key(r.get("theme")) for r in clean if r.get("source") == "index"}
    both = sorted(t for t in wiki_themes & index_themes if t)

    kept = [r for r in clean if not r["excluded"]]
    themes_kept = Counter(r.get("theme") for r in kept if r.get("theme"))

    return {
        "статьи": {
            "всего": len(articles),
            "взято": sum(1 for a in articles if a.get("blocks")),
            "не взято": [a["name"] for a in articles if not a.get("blocks")],
            "с нулём вопросов": zero,
            "по хостам": dict(by_host),
        },
        "вопросы из индекса": {
            "всего": len(questions),
            "на статью": percentiles(list(per_article.values())),
            "заполненность полей": {
                field: round(100 * sum(1 for q in questions if q.get(field)) / len(questions))
                for field in FIELDS
            },
            "с пустым текстом (вопрос-картинка)": sum(1 for q in questions if not q["question"]),
        },
        "картинки": {
            "всего": len(images),
            "скачано": len(ok_images),
            "недоступно": len(images) - len(ok_images),
            "раздаток скачано": sum(1 for i in ok_images if i["isHandout"]),
            "вес МБ": round(sum(i["bytes"] for i in ok_images) / 1024 / 1024, 1),
            "максимальная ширина иллюстрации": max(
                (i["width"] or 0) for i in ok_images if not i["isHandout"]
            ),
            "по хостам": dict(images_by_host),
        },
        "объединённый корпус бинго": {
            "всего строк": len(clean),
            "годных": len(kept),
            "по источникам": dict(Counter(r.get("source") for r in kept)),
            "тем": len(themes_kept),
            "тем с 3+ вопросами": sum(1 for n in themes_kept.values() if n >= 3),
            "тем в обоих источниках": both,
            "повторов помечено": sum(1 for r in clean if r.get("duplicateOf")),
        },
    }


def main():
    report = build()
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    articles = report["статьи"]
    print(f"Статей: взято {articles['взято']}/{articles['всего']}")
    for host, row in sorted(articles["по хостам"].items(), key=lambda kv: -kv[1]["статей"]):
        print(f"    {host:34} взято {row['взято']:3}/{row['статей']:3}, вопросов {row['вопросов']:4}")
    if articles["с нулём вопросов"]:
        print(f"  Статей с нулём вопросов: {len(articles['с нулём вопросов'])}")
        for name in articles["с нулём вопросов"]:
            print(f"    {name}")

    questions = report["вопросы из индекса"]
    print(f"\nВопросов из индекса: {questions['всего']}, на статью {questions['на статью']}")
    print("  Заполненность полей, %:")
    for field, share in questions["заполненность полей"].items():
        print(f"    {field:14} {share:3}")

    images = report["картинки"]
    print(f"\nКартинки: скачано {images['скачано']}/{images['всего']}, "
          f"{images['вес МБ']} МБ, раздаток {images['раздаток скачано']}")
    print(f"  Недоступно {images['недоступно']}: " + ", ".join(
        f"{host} {row['недоступно']}"
        for host, row in images["по хостам"].items() if row["недоступно"]
    ))

    corpus = report["объединённый корпус бинго"]
    print(f"\nКорпус бинго: годных {corpus['годных']}/{corpus['всего строк']} "
          f"{corpus['по источникам']}")
    print(f"  Тем {corpus['тем']}, из них с 3+ вопросами {corpus['тем с 3+ вопросами']}")
    print(f"  Тем в обоих источниках: {len(corpus['тем в обоих источниках'])} "
          f"{corpus['тем в обоих источниках']}")
    print(f"  Повторов помечено: {corpus['повторов помечено']}")
    print(f"\nОтчёт: {OUT}")


if __name__ == "__main__":
    main()
