"""Тесты колод фактов (T15). Запуск: python3 scripts/tests/test_structure_facts.py"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from structure_facts import (
    DECKS,
    DUMP,
    FIXES,
    MASK,
    PROSE_SOURCES,
    SOURCES,
    apply_fixes,
    build,
    card_id,
    cards_from_sheet,
    prose_cards,
    split_head,
    unmasked,
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
    check(sum(1 for c in result["cards"] if c.get("image")) == 9,
          "картинки у семи картин и у двух абзацев прозы ИЗО")
    prose = [c for c in result["cards"] if c["ask"] == "Кто или что это?" and c.get("sheet") != "Перифразы"]
    check(len(prose) > 750, f"проза стала карточками (сейчас {len(prose)})")
    leaks = [c["id"] for c in prose if c["id"] not in fixes and unmasked(c["front"], c["back"])]
    check(leaks == [], f"на лице нет термина сквозь маску без вычитки: {leaks[:5]}")


def prose(rows, sheet="Рандом", images=()):
    src = next(x for x in PROSE_SOURCES if x["sheet"] == sheet)
    got, dropped = prose_cards(src, {"name": sheet, "rows": rows, "images": list(images)})
    return got, dropped


def test_prose_head_and_mask():
    got, _ = prose([{"row": 1, "cells": [
        "Альтамира — пещера в Испании. Рисунки Альтамиры открыты в 1879 году."]}])
    c = got[0]
    check(c["back"] == "Альтамира", "оборот — термин")
    check("Альтамир" not in c["front"] and c["front"].startswith("Пещера в Испании"),
          "на лице термина нет, лицо с заглавной")
    check(f"Рисунки {MASK} открыты" in c["front"], "склонённая форма термина замаскирована")
    check(c["note"].startswith("Альтамира —"), "на обороте абзац целиком")


def test_prose_variants_and_dates():
    got, _ = prose([
        {"row": 1, "cells": ["Иводзима (Ио) — остров. На Ио нет населения."]},
        {"row": 2, "cells": ["Ян Гевелий (1611-1687) — польский астроном."]},
        {"row": 3, "cells": ["Тест Бекдел (часто — тест Бехдель) — тест на предвзятость."]},
    ])
    check(f"На {MASK} нет" in got[0]["front"], "вариант из скобок замаскирован")
    check(got[1]["front"].startswith("(1611-1687) Польский"), "даты из скобок уходят на лицо подсказкой")
    check(got[2]["back"] == "Тест Бекдел", "тире внутри скобки не режет термин")


def test_prose_without_head_dropped():
    got, dropped = prose([{"row": 1, "cells": ["Нобелевская премия мира вручается в Осло"]}])
    check(got == [] and len(dropped) == 1, "абзац без «Термин —» выпадает и считается")
    check(split_head("Фра-Дьяволо — разбойник") == ("Фра-Дьяволо", "разбойник"),
          "дефис внутри слова — не тире")
    check(split_head("Этци- ледяная мумия") == ("Этци", "ледяная мумия"), "тире без пробела перед")


def test_prose_inline_in_pair_sheet():
    got, _ = prose([
        {"row": 1, "cells": ["Картина", "Автор"]},
        {"row": 2, "cells": ["Остров мёртвых", "Арнольд Бёклин"]},
        {"row": 67, "cells": ["Рой Лихтенштейн — американский художник, поп-арт."]},
    ], sheet="Изобразительное искусство", images=[{"row": 67, "col": 8, "file": "r.png"}])
    check([c["back"] for c in got] == ["Рой Лихтенштейн"], "в листе-паре прозой считается только одна первая ячейка")
    check(got[0].get("image") == "r.png", "картинка у строки прозы едет в карточку")


def test_fix_sub():
    deck = [{"id": "d-1", "front": "Дом Беккета. Беккет", "back": "Бекет", "note": "Бекет — Беккет, опечтка"}]
    out = apply_fixes(deck, {"d-1": {"sub": [["опечтка", "опечатка"], ["Беккет", MASK, "front"]]}})
    check(out[0]["note"] == "Бекет — Беккет, опечатка", "замена без поля правит и абзац; лицевая не трогает абзац")
    check("Беккет" not in out[0]["front"], "замена «front» правит лицо")
    try:
        apply_fixes(deck, {"d-1": {"sub": [["нет такого", "x"]]}})
        check(False, "устаревший фрагмент роняет сборку")
    except SystemExit:
        check(True, "устаревший фрагмент роняет сборку")


if __name__ == "__main__":
    test_columns_by_header()
    test_row_without_back_dropped()
    test_image_only_on_exact_row()
    test_fixes()
    test_card_id_stable()
    test_real_dump()
    test_prose_head_and_mask()
    test_prose_variants_and_dates()
    test_prose_without_head_dropped()
    test_prose_inline_in_pair_sheet()
    test_fix_sub()
    print("FAILED" if _failures else "OK")
    sys.exit(1 if _failures else 0)
