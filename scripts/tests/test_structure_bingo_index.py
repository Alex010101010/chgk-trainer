"""Тесты разбора статей индекса в вопросы (T16, шаг 3).
Запуск: python3 scripts/tests/test_structure_bingo_index.py

Блоки собираются вручную: каждый тест — про одну конкретную форму, которая
реально встретилась в 199 статьях, и её видно прямо в тесте.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from structure_bingo_index import split_sources, structure_article

_failures = []


def check(condition, message):
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        _failures.append(message)


def blocks(*items):
    """(тип, текст) или (тип, текст, [ссылки на картинки])."""
    out = []
    for item in items:
        type_, text = item[0], item[1]
        images = [{"src": src, "caption": None} for src in (item[2] if len(item) > 2 else [])]
        out.append({"type": type_, "text": text, "images": images})
    return out


def article(name, *items, url="https://example.test/a"):
    return {"name": name, "url": url, "blocks": blocks(*items)}


def test_tournament_line_with_a_colon_survives():
    """Красно-зелёный: строка турнира сама содержит двоеточие — «Кубок Гармонии.
    Элемент Шестой: Магия · Июнь 2022». Разбор «всё до первого двоеточия — это
    метка» разрезал бы её пополам и потерял половину названия."""
    got = structure_article(article(
        "Тема",
        ("quote", "Кубок Гармонии. Элемент Шестой: Магия · Июнь 2022"),
        ("quote", "Вопрос 3: По легенде, короля убили. Кто он?"),
        ("quote", "Ответ: Пшемысл II."),
    ))
    check(len(got) == 1, "вопрос извлечён")
    check(
        got[0]["tournament"] == "Кубок Гармонии. Элемент Шестой: Магия · Июнь 2022",
        "строка турнира цела, а не обрезана по двоеточию",
    )
    check(got[0]["question"] == "По легенде, короля убили. Кто он?", "текст вопроса без метки")


def test_id_is_prefixed_so_it_cannot_collide_with_the_wiki_corpus():
    """Тема «Сумбур вместо музыки» есть и в вики-корпусе, и в индексе. Без
    префикса id `sumbur-vmesto-muzyki-1` столкнулись бы в общем корпусе."""
    got = structure_article(article(
        "Сумбур вместо музыки",
        ("quote", "Турнир · 2020"),
        ("quote", "Вопрос 1: Текст вопроса?"),
        ("quote", "Ответ: Ответ."),
    ))
    check(got[0]["id"] == "ix-sumbur-vmesto-muzyki-1", "id с префиксом ix-")
    check(got[0]["source"] == "index", "источник помечен")


def test_image_inside_the_question_body_is_a_handout():
    """Картинка между меткой и `Ответ:` — раздатка. Картинка после `Автор:` —
    иллюстрация темы, и к вопросу отношения не имеет."""
    got = structure_article(article(
        "Тема",
        ("quote", "Турнир · 2021"),
        ("quote", "Вопрос 2:"),
        ("figure", "", ["https://cdn.test/razdatka.png"]),
        ("quote", "Перед вами работа. Назовите город."),
        ("quote", "Ответ: Каррара."),
        ("quote", "Автор: Кто-то"),
        ("figure", "", ["https://cdn.test/illustration.png"]),
    ))
    check(len(got) == 1, "вопрос извлечён")
    check(got[0]["handoutImage"] == "https://cdn.test/razdatka.png", "раздатка привязана к вопросу")
    check(got[0]["question"] == "Перед вами работа. Назовите город.", "текст вопроса собран")


def test_image_only_question_keeps_an_empty_text_instead_of_vanishing():
    """«Вопрос*:» + картинка — вопрос, текст которого и есть картинка. Пустой
    текст здесь не ошибка разбора; негодной запись объявит санитайзер, с
    причиной, а не молчаливым выпадением из корпуса."""
    got = structure_article(article(
        "Тема",
        ("quote", "Вопрос*:"),
        ("figure", "", ["https://cdn.test/q.png"]),
        ("quote", "Ответ: «Происхождение войны»."),
    ))
    check(len(got) == 1, "запись не потеряна")
    check(got[0]["question"] == "", "мусорный текст «*:» не поехал как вопрос")
    check(got[0]["handoutImage"] == "https://cdn.test/q.png", "картинка привязана")


def test_marker_glued_to_the_tournament_line_is_split():
    """«БЕСКОНЕЧНЫЕ ЗЕМЛИ: ТОМ XI, ВОПРОС 34» — метка не в начале строки.
    Красно-зелёный: парсер, ищущий метку только с начала блока, теряет вопрос
    целиком и молча (так пропадала вся статья «Костёр тщеславия»)."""
    got = structure_article(article(
        "Костёр тщеславия",
        ("quote", "БЕСКОНЕЧНЫЕ ЗЕМЛИ: ТОМ XI, ВОПРОС 34"),
        ("quote", "Историк рассказывает, как купец предложил купить всё увиденное."),
        ("quote", "Ответ: костёр тщеславия."),
        ("quote", "Зачет: костёр Савонаролы."),
    ))
    check(len(got) == 1, "вопрос со склеенной меткой найден")
    check(got[0]["tournament"] == "БЕСКОНЕЧНЫЕ ЗЕМЛИ: ТОМ XI,", "префикс ушёл в турнир")
    check(got[0]["acceptance"] == "костёр Савонаролы.", "зачёт разобран")


def test_prose_after_the_record_does_not_leak_into_the_author_field():
    """За `Автор:` сразу идёт следующий абзац статьи. Без границы записи он
    уехал бы в поле автора — и в вики, и в телеграфе он стоит вплотную."""
    got = structure_article(article(
        "Тема",
        ("quote", "Турнир · 2019"),
        ("quote", "Вопрос 5: Текст вопроса?"),
        ("quote", "Ответ: Ответ."),
        ("quote", "Автор: Иван Иванов"),
        ("p", "Далее в статье рассказывается, как это выглядит на практике."),
    ))
    check(got[0]["author"] == "Иван Иванов", "в авторе только автор")
    check("Далее в статье" not in (got[0]["author"] or ""), "проза не затекла в поле")


def test_or_separator_starts_a_new_record():
    """Блок «ИЛИ» разделяет два вопроса одной темы."""
    got = structure_article(article(
        "Тема",
        ("quote", "Турнир А · 2018"),
        ("quote", "Вопрос 1: Первый?"),
        ("quote", "Ответ: Раз."),
        ("aside", "ИЛИ"),
        ("quote", "Турнир Б · 2019"),
        ("quote", "Вопрос 2: Второй?"),
        ("quote", "Ответ: Два."),
    ))
    check(len(got) == 2, "два вопроса, а не один")
    check([r["answer"] for r in got] == ["Раз.", "Два."], "ответы не перепутаны")
    check([r["id"] for r in got] == ["ix-tema-1", "ix-tema-2"], "нумерация сквозная по теме")


def test_record_without_an_answer_is_dropped():
    """Статья «Жугдэрдэмидийн Гуррагча» перечисляет вопросы без ответов —
    играть по ним нельзя, и в корпус они не едут."""
    got = structure_article(article(
        "Тема",
        ("quote", "Турнир · 2010"),
        ("quote", "Вопрос 62: Вопрос без ответа?"),
        ("p", "Проза статьи."),
    ))
    check(got == [], "запись без ответа не создана")


def test_sources_split_even_without_a_space_before_the_number():
    """У 222 записей ссылка упирается прямо в номер следующей: «…/451235/2.
    http://…». Правило, требующее пробел, оставляло их одной склейкой."""
    glued = "http://afisha.ru/movie/205810/review/451235/2. http://reichenbachfall.ch/index.php"
    check(
        split_sources(glued) == [
            "http://afisha.ru/movie/205810/review/451235/",
            "http://reichenbachfall.ch/index.php",
        ],
        "склейка без пробела разрезана",
    )
    check(
        split_sources("1. Первый источник 2. Второй источник") == ["Первый источник", "Второй источник"],
        "обычная нумерация с пробелами разрезана",
    )
    year = "С. Иванов. В поисках Константинополя. — М.: 2011. — С. 353."
    check(split_sources(year) == [year], "год «2011.» и страница «353.» не приняты за номера")


def main():
    for test in [
        test_tournament_line_with_a_colon_survives,
        test_id_is_prefixed_so_it_cannot_collide_with_the_wiki_corpus,
        test_image_inside_the_question_body_is_a_handout,
        test_image_only_question_keeps_an_empty_text_instead_of_vanishing,
        test_marker_glued_to_the_tournament_line_is_split,
        test_prose_after_the_record_does_not_leak_into_the_author_field,
        test_or_separator_starts_a_new_record,
        test_record_without_an_answer_is_dropped,
        test_sources_split_even_without_a_space_before_the_number,
    ]:
        print(test.__name__)
        test()
    if _failures:
        print(f"\nПРОВАЛЕНО: {len(_failures)}")
        sys.exit(1)
    print("\nВсе проверки пройдены.")


if __name__ == "__main__":
    main()
