"""Тесты контент-пайплайна (T11). Запуск: python3 scripts/tests/test_sanitize.py

Без внешних зависимостей и без сети: разбор страницы проверяется на фикстуре.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sanitize_dumps import accept_variants, clean_question, exclusion_reason, sanitize
from scrape_bingo_wiki import extract_article_text

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")

_failures = []


def check(condition, message):
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        _failures.append(message)


def test_parsing_keeps_guillemets():
    """Красно-зелёный: прежний fix_mojibake оставлял на этой странице 2 символа
    U+FFFD на месте «ёлочек» — при том что страница в архиве чистый UTF-8."""
    with open(os.path.join(FIXTURES, "ab_ovo.html"), "rb") as f:
        text = extract_article_text(f.read())
    check(text.count("�") == 0, "в разобранной статье нет U+FFFD")
    check("«От яйца до яблока»" in text, "ёлочки на месте")


def test_host_instruction_is_fixed_not_dropped():
    raw = '[Ведущему: сделать паузу перед словом "пикассо"] Кого назвали так же?'
    cleaned = clean_question(raw)
    check(not cleaned.startswith("["), "инструкция ведущему вырезана")
    check(cleaned.startswith("Кого назвали"), "текст вопроса уцелел")
    check(exclusion_reason(cleaned, "Уорхол.", None, raw)[0] is None,
          "вопрос с инструкцией ведущему не отбраковывается")

    указание = "[Указание ведущему: не говорить про заглавную букву.] Что это?"
    check(clean_question(указание).startswith("Что это"),
          "«Указание ведущему» тоже вырезается")

    # Инструкция чтецу бывает единственным признаком раздатки — срезав её,
    # нельзя потерять сам факт.
    организаторам = ("[Указание организаторам по раздаточному материалу: команда "
                     "получает один комплект.] Некоторые решения принимают не везде. Где?")
    check(exclusion_reason(clean_question(организаторам), "ответ", None, организаторам)[0]
          == "handout",
          "раздатка, названная только в инструкции организаторам, всё равно видна")

    # А маркер `Перед вами` — наоборот, виден только после снятия инструкции.
    перед = "[Ведущему: пауза] Перед вами схема. Что это?"
    check(exclusion_reason(clean_question(перед), "ответ", None, перед)[0] == "handout",
          "«Перед вами» после инструкции чтецу распознаётся")


def test_vnimanie_is_not_a_handout():
    """195 gq-вопросов начинаются с «Внимание» — почти все это «Внимание, слово
    АЛЬФА — замена», играбельный текстовый вопрос. Наивное правило ^Внимание
    зарезало бы их все."""
    question = "Внимание, слово АЛЬФА в вопросе — замена.\nВо внутреннем дворе поместья..."
    check(exclusion_reason(question, "ответ", None)[0] is None,
          "«Внимание, слово X — замена» остаётся в корпусе")


def test_structural_markers_are_excluded():
    cases = [
        ("Перед вами АЛЬФА-крест. Что мы заменили?", "handout"),
        ("Раздаточный материал прилагается. Что это?", "handout"),
        ("Чёрным прямоугольником скрыты АЛЬФЫ. Что мы заменили?", "handout"),
        ("[Аудио: http://example.org/1] Назовите исполнителя.", "media"),
        ("Смотрите картинку: http://gotquestions.online/pics/1.jpg", "media"),
        ("Дуплет. 1. Первый вопрос. 2. Второй вопрос.", "duplet"),
        ('"Анатомический" блиц от поэта. 1. Закончите отрывок. 2. А это?', "duplet"),
    ]
    for question, expected in cases:
        actual = exclusion_reason(question, "ответ", None)[0]
        check(actual == expected, f"{expected}: {question[:35]!r} -> {actual}")

    # Всё, что ниже, — регрессии из ручной вычитки выборки 30/30: правило,
    # выведенное из одних плохих примеров, резало ровно эти вопросы.
    kept = [
        ("Прослушайте фрагмент стихотворения Веры Павловой: «Смерть — знак "
         "равенства — я минус любовь». Правильно ли это?",
         "«прослушайте» — обращение к чтецу, текст фрагмента тут же"),
        ("Команда выиграла блиц на турнире. Назовите её капитана.",
         "«блиц» без нумерации частей — содержание, а не формат"),
        ("Вопреки названию, ЧЕРНЫЙ КВАДРАТ является КВАДРАТОМ только в "
         "Антерсельве. Что мы заменили?",
         "чёрный квадрат без «скрыт» — это не раздатка"),
    ]
    for question, why in kept:
        check(exclusion_reason(question, "ответ", None)[0] is None, why)

    check(exclusion_reason("Что это?", "ответ", "МетаЧГК")[0] == "meta_theme",
          "метатема исключается")
    check(exclusion_reason("", "ответ", None)[0] == "empty", "пустой вопрос")
    check(exclusion_reason("Вопрос?", "", None)[0] == "no_answer", "пустой ответ")


def test_accept_variants():
    variants = accept_variants("Уорхол (Энди Уорхол).", "")
    check("уорхол" in variants and "энди уорхол" in variants,
          f"скобочный вариант разобран: {variants}")

    check("уорхол" in accept_variants("Уорхол.", "Энди Уорхол."),
          "хвостовая точка снята")
    check("энди уорхол" in accept_variants("Уорхол.", "Энди Уорхол."),
          "зачёт добавлен вариантом")

    boilerplate = accept_variants("Гамма.", "точный ответ.")
    check(boilerplate == ["гамма"],
          f"болванка «точный ответ» в варианты не попадает: {boilerplate}")

    check("1984.5" in accept_variants("1984.", '"1984.5", "1984 с половиной".')
          or "1984.5" in " ".join(accept_variants("1984.", '"1984.5", "1984 с половиной".')),
          "закавыченные варианты зачёта разобраны")

    check(accept_variants("Ёлка.", "") == ["елка"], "ё приводится к е")

    # Регрессия: всё после «Незачёт:» — это ответы, которые не принимаются.
    rejected = accept_variants("Атомный реактор.", "Незачет: Термоядерный реактор.")
    check("термоядерный реактор" not in rejected,
          f"незачтённый вариант не попадает в допустимые: {rejected}")
    check("атомный реактор" in rejected, "сам ответ при этом на месте")
    check("рапира" in accept_variants("рапира / сабля / шпага.", ""),
          "слэш с пробелами разделяет варианты")
    for whole in ('"AC/DC".', "Температура (5/9 градуса).", '"1984 1/2".'):
        variants = accept_variants(whole, "")
        check(all(len(v) > 3 for v in variants),
              f"слэш без пробелов не режет ответ: {whole} -> {variants}")
        check(not any(v.endswith(('"', '.', '«', '»')) for v in variants),
              f"кавычки и точки сняты полностью: {whole} -> {variants}")

    check("перельман" in accept_variants("Перельман.", "по фамилии «Перельман» без неверных уточнений"),
          "«без неверных уточнений» — это не список незачёта, вариант сохраняется")


def test_sanitize_end_to_end():
    rows = [
        {"id": "a", "question": "Перед вами\xa0\xa0крест.", "answer": "Гамма.", "acceptance": "точный ответ."},
        {"id": "b", "question": "[Чтецу: пауза] Кто это?", "answer": "Павлов.", "acceptance": None},
    ]
    out = sanitize(rows, "bingo")
    check(out[0]["excluded"] == "handout", "раздатка помечена")
    check(out[1]["excluded"] is None, "нормальный вопрос пропущен")
    check(out[1]["questionRaw"].startswith("[Чтецу"), "исходный текст сохранён")
    check(out[1]["corpus"] == "bingo", "корпус проставлен")
    check(all(r["acceptVariants"] for r in out), "варианты не пусты при непустом ответе")
    check("\xa0" not in out[0]["question"], "неразрывные пробелы схлопнуты")


def main():
    for test in [
        test_parsing_keeps_guillemets,
        test_host_instruction_is_fixed_not_dropped,
        test_vnimanie_is_not_a_handout,
        test_structural_markers_are_excluded,
        test_accept_variants,
        test_sanitize_end_to_end,
    ]:
        print(test.__name__)
        test()
    if _failures:
        print(f"\nПРОВАЛЕНО: {len(_failures)}")
        sys.exit(1)
    print("\nВсе проверки пройдены.")


if __name__ == "__main__":
    main()
