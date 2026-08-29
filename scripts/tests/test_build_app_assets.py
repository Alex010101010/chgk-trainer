"""Тесты сборщика ассета (T2b). Запуск: python3 scripts/tests/test_build_app_assets.py"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from build_app_assets import ASSET_VERSION, FIELDS, build, is_boilerplate, load_tehniki

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


def test_tehniki_examples_exist_in_corpus():
    with open(os.path.join(DATA, "gq_clean.json"), encoding="utf-8") as f:
        asset = build(json.load(f))
    by_id = {q["id"]: q for q in asset["questions"]}

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
        # Эталон должен быть достаточно большим, чтобы тап попадался, — иначе
        # приём недели не встретится ни разу за две недели.
        check(len(marked) >= 30, f"{t['id']}: эталон достаточного размера ({len(marked)})")
        check(
            not any(re.search(t["detect"], q["question"]) for q in marked),
            f"{t['id']}: приём не объявлен в тексте самих эталонных вопросов",
        )


if __name__ == "__main__":
    test_boilerplate_cut()
    test_excluded_dropped_and_count_matches()
    test_tehniki_examples_exist_in_corpus()
    print("FAILED" if _failures else "OK")
    sys.exit(1 if _failures else 0)
