"""Тесты контент-пайплайна (T11). Запуск: python3 scripts/tests/test_sanitize.py

Без внешних зависимостей и без сети: разбор страницы проверяется на фикстуре.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sanitize_dumps import (
    accept_variants,
    clean_question,
    duplicate_key,
    exclusion_reason,
    mark_duplicates,
    sanitize,
)
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
    # Квадратные скобки — необязательная часть ответа (528 ответов из 9915).
    blini = accept_variants("[масленичные] блины.", "")
    check("блины" in blini and "масленичные блины" in blini,
          f"обе формы приняты: {blini}")
    check("масленичные" not in blini,
          "содержимое квадратных скобок само по себе ответом не становится")
    check(not any("[" in v or "]" in v for v in blini),
          "буквальных скобок в вариантах не остаётся")

    # Круглые скобки — полная форма, но только когда снаружи входит внутрь.
    check("энди уорхол" in accept_variants("Уорхол (Энди Уорхол).", ""),
          "полная форма имени принимается")
    explanation = accept_variants(
        "Температуру воздуха (1 градус по Фаренгейту равен 5/9 градуса).", "")
    check("температуру воздуха" in explanation, "сам ответ на месте")
    check(not any("фаренгейту" in v and "температуру" not in v for v in explanation),
          f"пояснение в скобках вариантом не становится: {explanation}")

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


def test_question_with_a_local_handout_image_is_playable():
    """T20: картинка скачана локально, цикл её показывает — вопрос играбелен.

    Красно-зелёный на главной ловушке задачи: наличие файла обязано закрывать
    разбор раздатки ЦЕЛИКОМ. Реализация, которая просто снимает проверку по
    `handoutImage`, оставляет в браке 40 из 105 вопросов — те, где текст прямо
    ссылается на картинку, то есть где раздатка нужнее всего."""
    text = "Назовите француза, изображенного на фотографиях."
    reason, _ = exclusion_reason(text, "Бертильон.", None, handout_image="images/a.jpg")
    check(reason is None, "с локальной картинкой вопрос играбелен")

    pered = "Перед вами таблица. Назовите пропущенное слово."
    reason, _ = exclusion_reason(pered, "Ответ", None, handout_image="images/a.jpg")
    check(reason is None, "«Перед вами» с картинкой тоже играбелен")
    reason, note = exclusion_reason(pered, "Ответ", None)
    check(reason == "handout", "а без файла «Перед вами» по-прежнему брак")
    check("раздаточный" in (note or ""), "причина названа своими словами")


def test_image_only_question_is_playable_with_a_file():
    """Вопрос, текст которого и есть картинка. С файлом он играется; без файла
    «пусто» — правда, играть нечем."""
    reason, _ = exclusion_reason("", "Каррара", None, handout_image="images/b.png")
    check(reason is None, "вопрос-картинка играется, если картинка есть")
    reason, _ = exclusion_reason("", "Каррара", None)
    check(reason == "empty", "а без картинки он по-прежнему пустой")


def test_duplicates_are_marked_not_deleted():
    """Один турнирный вопрос попадается и в gq, и в бинго. Принцип T11 —
    ничего не удалять: помечается `duplicateOf`, строка остаётся."""
    rows = [
        {"id": "gq-1", "question": "В 1937 году вышла повесть Стейнбека. Назовите её."},
        {"id": "ix-t-1", "question": "В 1937 году вышла повесть Стейнбека — назовите её!"},
        {"id": "ix-t-2", "question": "Совсем другой вопрос про другое."},
    ]
    marked = mark_duplicates(rows)
    check(marked == 1, "помечен ровно один повтор")
    check(rows[1]["duplicateOf"] == "gq-1", "оригиналом назван gq, а не бинго")
    check("duplicateOf" not in rows[0], "оригинал не помечен")
    check("duplicateOf" not in rows[2], "непохожий вопрос не помечен")
    check(len(rows) == 3, "ни одна строка не удалена")


def test_duplicate_key_ignores_punctuation_and_yo():
    check(
        duplicate_key("Ёлка, «ель» — назовите!") == duplicate_key("елка ель назовите"),
        "ё, кавычки и тире не мешают совпадению",
    )
    check(duplicate_key("   ") is None, "пустой вопрос ключа не даёт")


def main():
    for test in [
        test_parsing_keeps_guillemets,
        test_host_instruction_is_fixed_not_dropped,
        test_vnimanie_is_not_a_handout,
        test_structural_markers_are_excluded,
        test_accept_variants,
        test_sanitize_end_to_end,
        test_question_with_a_local_handout_image_is_playable,
        test_image_only_question_is_playable_with_a_file,
        test_duplicates_are_marked_not_deleted,
        test_duplicate_key_ignores_punctuation_and_yo,
    ]:
        print(test.__name__)
        test()
    if _failures:
        print(f"\nПРОВАЛЕНО: {len(_failures)}")
        sys.exit(1)
    print("\nВсе проверки пройдены.")


if __name__ == "__main__":
    main()
