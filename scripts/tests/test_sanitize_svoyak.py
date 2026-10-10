"""Тесты отбора тем «Своей игры» (T6). Запуск: python3 scripts/tests/test_sanitize_svoyak.py"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sanitize_svoyak import THEME_SIZE, select, theme_reason

_failures = []


def check(condition, message):
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        _failures.append(message)


def q(qid, number, text=None, answer="Ответ.", **extra):
    return {
        "id": qid,
        "number": number,
        "ordering": number,
        "text": text if text is not None else f"Вопрос номер {qid} про ЭТОТ предмет.",
        "answer": answer,
        "zachet": "",
        "comment": "",
        "source": "",
        "authorNames": [],
        **extra,
    }


def theme(tour_id, numbers=(10, 20, 30, 40, 50), round_title="Отбор", title="Тема", **override):
    questions = [q(tour_id * 100 + i, n) for i, n in enumerate(numbers)]
    for idx, fields in override.items():
        questions[int(idx[1:])].update(fields)
    return {"tourId": tour_id, "title": title, "round": round_title, "questions": questions}


def pack(pid, date, themes):
    return {"id": pid, "title": f"Пакет {pid}", "startDate": date, "themes": themes}


def test_theme_rules():
    check(theme_reason(theme(1)) is None, "нормальная тема из пяти проходит")
    check(theme_reason(theme(2, numbers=(10, 20, 30, 40))) == "size", "тема из четырёх отбракована")
    check(theme_reason(theme(3, q2={"razdatkaPic": "x.jpg"})) == "media", "тема с картинкой отбракована")
    check(theme_reason(theme(4, q0={"text": "Перед вами фото. Кто ОН?"})) == "media",
          "раздатка по тексту ловится тем же правилом, что в «Классике»")
    check(theme_reason(theme(5, q4={"answer": "."})) == "no_answer", "пустой ответ уносит тему")
    check(theme_reason(theme(6, round_title="Перестрелка")) == "not_a_theme", "перестрелка — не тема")
    check(theme_reason(theme(7, q1={"takenDown": True})) == "taken_down", "снятый вопрос уносит тему")


def test_select():
    packs = [
        pack(1, "2025-05-01", [theme(11), theme(12, numbers=(100, 200, 300, 400, 500))]),
        # Та же тема в другом пакете — повтор.
        pack(2, "2024-05-01", [dict(theme(11), tourId=21)]),
        pack(3, "2001-01-01", [theme(31)]),
    ]
    themes, reasons, cutoff = select(packs, cutoffs=("2020-10-10", "2015-10-10"), min_themes=2)
    ids = [t["id"] for t in themes]
    check(ids == ["11", "12"], f"свежие темы без повтора: {ids}")
    check(reasons["duplicate"] == 1 and reasons["old"] == 1, f"причины: {dict(reasons)}")
    check(cutoff == "2020-10-10", "порог — первый, на котором тем хватает")
    noms = [x["nominal"] for x in themes[1]["questions"]]
    check(noms == [10, 20, 30, 40, 50], f"номиналы 100–500 приведены по порядку: {noms}")
    check(all(len(t["questions"]) == THEME_SIZE for t in themes), "в каждой теме пять вопросов")
    first = themes[0]["questions"][0]
    check(first["id"] == "si-1100" and first["acceptVariants"] == ["ответ"],
          f"id с префиксом si- и варианты зачёта: {first['id']}, {first['acceptVariants']}")

    _, _, wide = select(packs, cutoffs=("2020-10-10", "2015-10-10"), min_themes=5)
    check(wide == "2015-10-10", "тем мало — порог расширяется")


if __name__ == "__main__":
    test_theme_rules()
    test_select()
    print("FAILED" if _failures else "OK")
    sys.exit(1 if _failures else 0)
