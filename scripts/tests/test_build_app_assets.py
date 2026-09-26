"""Тесты сборщика ассета (T2b). Запуск: python3 scripts/tests/test_build_app_assets.py"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from build_app_assets import (
    ASSET_VERSION,
    FIELDS,
    HANDOUTS,
    IMAGES_SRC,
    article_image_name,
    article_images,
    build,
    build_articles,
    build_facts,
    fact_image_name,
    handout_file,
    is_boilerplate,
    load_rows,
    load_tehniki,
)

DATA = os.path.join(os.path.dirname(__file__), "..", "..", "data")

_failures = []


def check(condition, message):
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        _failures.append(message)


def test_boilerplate_cut():
    check(is_boilerplate("Точный ответ."), "«Точный ответ.» — болванка")
    check(is_boilerplate("по смыслу"), "«по смыслу» — болванка")
    check(is_boilerplate(None), "пустой зачёт — болванка")
    check(
        not is_boilerplate("в любом порядке"),
        "«в любом порядке» болванкой не считается: это настоящее правило",
    )


def test_excluded_dropped_and_count_matches():
    with open(os.path.join(DATA, "gq_clean.json"), encoding="utf-8") as f:
        rows = json.load(f)
    with open(os.path.join(DATA, "sanitize_report.json"), encoding="utf-8") as f:
        kept = json.load(f)["gq"]["по причинам"]["kept"]

    asset = build(rows)
    check(asset["v"] == ASSET_VERSION, "версия формата проставлена")
    check(
        asset["count"] == len(asset["questions"]),
        "count равен длине списка — иначе обрезанный файл не поймать",
    )
    check(asset["count"] == kept, f"вопросов ровно kept из отчёта санитайзера ({kept})")
    check(
        all(q.get("excluded") is None for q in asset["questions"]),
        "отбракованных в выводе нет",
    )
    check(
        not any(is_boilerplate(q["acceptance"]) and q["acceptance"] for q in asset["questions"]),
        "болванок зачёта в выводе не осталось",
    )
    check(
        all(set(q) == set(FIELDS) for q in asset["questions"]),
        "лишних полей не поехало",
    )
    check(
        all(q["acceptVariants"] for q in asset["questions"]),
        "у каждого вопроса непустой acceptVariants — иначе матчер бесполезен",
    )


def test_both_corpora_in_asset():
    """T3: бинго едет в тот же ассет и приносит с собой тему.

    Красный→зелёный: без `theme` в FIELDS ассет собрался бы как валидный, а
    режим бинго молча получил бы корпус, у которого не к чему привязать клетки.
    """
    asset = build(load_rows())
    by_corpus = {}
    for q in asset["questions"]:
        by_corpus[q["corpus"]] = by_corpus.get(q["corpus"], 0) + 1

    with open(os.path.join(DATA, "sanitize_report.json"), encoding="utf-8") as f:
        report = json.load(f)
    for corpus in ("gq", "bingo"):
        kept = report[corpus]["по причинам"]["kept"]
        check(by_corpus.get(corpus) == kept, f"корпус {corpus}: {kept} вопросов в ассете")

    bingo = [q for q in asset["questions"] if q["corpus"] == "bingo"]
    check(all(q["theme"] for q in bingo), "у каждого бинго-вопроса есть тема")
    check(
        all(q["theme"] is None for q in asset["questions"] if q["corpus"] == "gq"),
        "у gq темы нет — иначе «ни к одной» перестало бы быть верным ответом",
    )
    themes = {q["theme"] for q in bingo}
    check(
        len(themes) == report["bingo"]["тем осталось"],
        f"тем в ассете столько же, сколько в корпусе ({report['bingo']['тем осталось']})",
    )
    # Сетка — девять клеток; меньше девяти тем с непоказанным вопросом собрать её
    # не дадут, и режим не запустится вовсе.
    check(len(themes) >= 9, "тем хватает на сетку")


def test_handouts_reach_the_asset():
    """T20: у вопроса с раздаткой файл обязан лежать в ассетах.

    Красный→зелёный на тихом отказе: сборщик, который просто пропускает
    ненайденную картинку, кладёт в корпус вопрос «Перед вами…» без раздатки —
    игрок винит себя, а причина в забытом шаге сборки.
    """
    asset = build(load_rows())
    with_handout = [q for q in asset["questions"] if q["handout"]]
    check(len(with_handout) > 100, f"раздаток в ассете {len(with_handout)}")
    check(
        all(
            os.path.exists(os.path.join(HANDOUTS, q["handout"]))
            for q in with_handout
        ),
        "у каждой раздатки есть файл",
    )
    # С T21 раздатка есть у обоих корпусов: gq докачан `fetch_gq_handouts.py`.
    check(
        {q["corpus"] for q in with_handout} == {"bingo", "gq"},
        "раздатки есть и у бинго, и у gq",
    )
    # Вопрос с раздаткой, но без файла — падение, а не молчаливый пропуск.
    try:
        handout_file({"id": "нет-такого", "handoutImage": "http://x/y.jpg"})
        check(False, "ненайденная раздатка роняет сборку")
    except SystemExit:
        check(True, "ненайденная раздатка роняет сборку")


def test_tehniki_examples_exist_in_corpus():
    with open(os.path.join(DATA, "gq_clean.json"), encoding="utf-8") as f:
        asset = build(json.load(f))
    by_id = {q["id"]: q for q in asset["questions"]}
    all_ids = set()
    for name in ("gq_clean.json", "bingo_clean.json"):
        with open(os.path.join(DATA, name), encoding="utf-8") as f:
            all_ids |= {r["id"] for r in json.load(f)}

    for t in load_tehniki():
        for ex in t["examples"]:
            q = by_id.get(ex["questionId"])
            # Красный→зелёный: опечатка в id иначе тихо превратит контрольный
            # вопрос в обычный, и карточка урока будет ссылаться в пустоту.
            check(q is not None, f"{t['id']}: пример {ex['questionId']} есть в корпусе")
            if q is not None:
                check(
                    t["id"] in q["tehniki"],
                    f"{t['id']}: пример {ex['questionId']} помечен эталоном",
                )
            check(bool(ex["why"].strip()), f"{t['id']}: у примера {ex['questionId']} есть разбор")

        marked = [q for q in asset["questions"] if t["id"] in q["tehniki"]]
        # Эталон расходуется по вопросу за раунд (слот приёма недели), а
        # раундов в неделю меньше десяти. 25 — с запасом на неделю; порог был
        # 30, снижен под вычитанный руками эталон «bukvalno» (T4a, приём №3).
        check(len(marked) >= 25, f"{t['id']}: эталон достаточного размера ({len(marked)})")
        # Опечатка в `exclude` тихо оставила бы ложное срабатывание в эталоне.
        for qid in t.get("exclude", ()):
            check(qid in all_ids, f"{t['id']}: исключённый {qid} есть в корпусе")
        check(
            not any(re.search(t["detect"], q["question"]) for q in marked),
            f"{t['id']}: приём не объявлен в тексте самих эталонных вопросов",
        )


def test_article_images():
    """Иллюстрации статей (T14): имя выводится из скачанного исходника, раздатки
    вопросов в статью не идут, у статьи без картинок поля нет вовсе."""
    manifest = [
        {"articleName": "Ковентри", "file": "a.jpg", "isHandout": False},
        {"articleName": "Ковентри", "file": "b.png", "isHandout": False},
        {"articleName": "Ковентри", "file": "a.jpg", "isHandout": False},
        {"articleName": "Ковентри", "file": "h.jpg", "isHandout": True, "attachedTo": "b-1"},
        {"articleName": "Ковентри", "file": "нет-такого.jpg", "isHandout": False},
    ]
    real = [f for f in os.listdir(IMAGES_SRC)][:2]
    manifest[0]["file"] = manifest[2]["file"] = real[0]
    manifest[1]["file"] = real[1]
    manifest[3]["file"] = real[0]
    images = article_images(manifest)
    check(
        images.get("Ковентри") == [article_image_name(real[0]), article_image_name(real[1])],
        "картинки статьи — скачанные, без дублей и без раздатки вопроса",
    )
    check(article_image_name("x.png") == "art-x.jpg", "имя всегда JPEG с приставкой art-")

    rows = load_rows()
    arts = build_articles([r for r in rows if r.get("theme")], images={"Ковентри": ["art-x.jpg"]})
    by = {a["theme"]: a for a in arts["articles"]}
    check(by.get("Ковентри", {}).get("images") == ["art-x.jpg"], "поле images доезжает до статьи")
    check(
        all("images" not in a for t, a in by.items() if t != "Ковентри"),
        "у статьи без картинок поля images нет",
    )

    # Настоящий набор: каждое объявленное имя выводится из существующего исходника.
    real_images = article_images()
    srcs = {article_image_name(f) for f in os.listdir(IMAGES_SRC)}
    check(
        all(n in srcs for names in real_images.values() for n in names),
        f"все {sum(map(len, real_images.values()))} картинок статей есть в data/images",
    )


def test_facts():
    deck_file = {
        "source": "src", "decks": [{"id": "kartiny", "title": "Картины", "count": 2}],
        "cards": [
            {"id": "k-1", "deck": "kartiny", "ask": "?", "front": "Остров мёртвых", "back": "Бёклин",
             "image": sorted(os.listdir(IMAGES_SRC))[0], "sheet": "ИЗО", "row": 2},
            {"id": "k-2", "deck": "kartiny", "ask": "?", "front": "Олимпия", "back": "Мане",
             "image": "nonexistent.png"},
            {"id": "p-1", "deck": "perifrazy", "ask": "?", "front": "А", "back": "Б"},
        ],
    }
    facts = build_facts(deck_file)
    by = {c["id"]: c for c in facts["cards"]}
    check(facts["count"] == 3 and facts["source"] == "src", "count и источник в ассете")
    check(by["k-1"]["image"].startswith("fact-") and by["k-1"]["image"].endswith(".jpg"),
          "картинка карточки — fact-<исходник>.jpg")
    check("image" not in by["k-2"], "нескачанная картинка не объявляется")
    check("image" not in by["p-1"] and "note" not in by["p-1"], "у карточки без картинки и заметки полей нет")
    check("sheet" not in by["k-1"] and "row" not in by["k-1"], "служебные поля вычитки не едут")

    real = build_facts()
    srcs = {fact_image_name(f) for f in os.listdir(IMAGES_SRC)}
    pics = [c["image"] for c in real["cards"] if "image" in c]
    check(len(pics) == 7 and all(p in srcs for p in pics), "7 картинок карточек выводятся из data/images")


if __name__ == "__main__":
    test_boilerplate_cut()
    test_excluded_dropped_and_count_matches()
    test_both_corpora_in_asset()
    test_handouts_reach_the_asset()
    test_tehniki_examples_exist_in_corpus()
    test_article_images()
    test_facts()
    print("FAILED" if _failures else "OK")
    sys.exit(1 if _failures else 0)
