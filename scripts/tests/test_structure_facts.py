"""Тесты колод фактов (T15). Запуск: python3 scripts/tests/test_structure_facts.py"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from structure_facts import (
    DECKS,
    DUMP,
    FIXES,
    SOURCES,
    apply_fixes,
    build,
    card_id,
    cards_from_sheet,
)

_failures = []


def check(condition, message):
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        _failures.append(message)


def cards(rows, sheet="Перифразы", images=()):
    src = next(x for x in SOURCES if x["sheet"] == sheet)
    return cards_from_sheet(src, {"name": sheet, "rows": rows, "images": list(images)})


def test_columns_by_header():
    a = cards([
        {"row": 1, "cells": ["Перифраз", "Значение", "Комментарий"]},
        {"row": 2, "cells": ["Архангельский мужик", "М.В. Ломоносов"]},
    ])
    b = cards([
        {"row": 1, "cells": ["Комментарий", "", "Значение", "Перифраз"]},
        {"row": 2, "cells": ["", "", "М.В. Ломоносов", "Архангельский мужик"]},
    ])
    check(len(a) == 1 and a[0]["front"] == "Архангельский мужик" and a[0]["back"] == "М.В. Ломоносов",
          "лицо и оборот берутся из колонок с нужными заголовками")
    check([(c["front"], c["back"], c["id"]) for c in a] == [(c["front"], c["back"], c["id"]) for c in b],
          "переставленные колонки дают те же карточки")


def test_row_without_back_dropped():
    got = cards([
        {"row": 1, "cells": ["Перифраз", "Значение"]},
        {"row": 2, "cells": ["Отец народов", "И.В. Сталин"]},
        {"row": 3, "cells": ["Кремлёвский горец"]},
    ])
    check([c["front"] for c in got] == ["Отец народов"], "строка без оборота выпадает")


def test_image_only_on_exact_row():
    got = cards([
        {"row": 1, "cells": ["Картина", "Автор"]},
        {"row": 2, "cells": ["Остров мёртвых", "Арнольд Бёклин"]},
        {"row": 3, "cells": ["Олимпия", "Эдуард Мане"]},
    ], sheet="Изобразительное искусство", images=[{"row": 2, "col": 3, "file": "a.jpg"},
                                                   {"row": 4, "col": 3, "file": "b.jpg"}])
    by = {c["front"]: c for c in got}
    check(by["Остров мёртвых"].get("image") == "a.jpg", "картинка с якорем в строке карточки доезжает")
    check("image" not in by["Олимпия"], "съехавший якорь к соседней строке не притягивается")


def test_fixes():
    deck = [{"id": "d-1", "front": "Марашал Победы", "back": "Жуков", "note": "x"},
            {"id": "d-2", "front": "Б", "back": "б"}]
    out = apply_fixes(deck, {"d-1": {"front": "Маршал Победы", "note": ""}, "d-2": {"drop": "брак"}})
    check(len(out) == 1 and out[0]["front"] == "Маршал Победы" and out[0]["id"] == "d-1",
          "правка меняет поле, но не id; drop удаляет карточку")
    check("note" not in out[0], "пустое значение в правке снимает поле")
    try:
        apply_fixes(deck, {"d-9": {"back": "x"}})
        check(False, "правка на несуществующую карточку роняет сборку")
    except SystemExit:
        check(True, "правка на несуществующую карточку роняет сборку")


def test_card_id_stable():
    check(card_id("perifrazy", "Отец народов") == card_id("perifrazy", " отец  народов"),
          "id не зависит от регистра и пробелов")
    check(card_id("a", "x") != card_id("b", "x"), "одно лицо в разных колодах — разные карточки")


def test_real_dump():
    with open(DUMP, encoding="utf-8") as f:
        dump = json.load(f)
    with open(FIXES, encoding="utf-8") as f:
        fixes = json.load(f)
    # Дубль лица внутри колоды — одна карточка.
    sheet = next(s for s in dump["sheets"] if s["name"] == "Перифразы")
    sheet["rows"].append({"row": 999, "cells": ["отец народов", "Сталин"]})
    result = build(dump, fixes)
    counts = {d["id"]: d["count"] for d in result["decks"]}
    check(counts["perifrazy"] == 189, f"перифразов 189, дубль склеен (сейчас {counts['perifrazy']})")
    check(all(counts[d] > 0 for d, _ in DECKS), "ни одной пустой колоды")
    ids = [c["id"] for c in result["cards"]]
    check(len(ids) == len(set(ids)), "id карточек уникальны")
    check(sum(1 for c in result["cards"] if c.get("image")) == 7, "у семи картин есть картинка")


if __name__ == "__main__":
    test_columns_by_header()
    test_row_without_back_dropped()
    test_image_only_on_exact_row()
    test_fixes()
    test_card_id_stable()
    test_real_dump()
    print("FAILED" if _failures else "OK")
    sys.exit(1 if _failures else 0)
