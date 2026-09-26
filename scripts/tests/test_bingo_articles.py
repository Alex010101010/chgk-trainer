"""Тесты извлечения справки по клише (T14, срез).
Запуск: python3 scripts/tests/test_bingo_articles.py

Фикстуры — куски настоящих статей: вики-статья с оглавлением и разделом,
статья индекса с вопросом-цитатой.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from structure_bingo_articles import build, index_prose, leaks, wiki_prose

_failures = []


def check(cond, name):
    print(("  ok  " if cond else "  ПРОВАЛ ") + name)
    if not cond:
        _failures.append(name)


WIKI_1984 = (
    'Роман-антиутопия Джорджа Оруэлла, написанный в 1948.\n'
    '\n'
    'Содержание\n'
    '\n'
    '1 События 1984 года\n'
    '2 Большой Брат\n'
    '\n'
    '  События 1984 года \n'
    'Помимо выхода фильма, в 1984 году произошло много всего.\n'
    '\n'
    '"Бархатный сезон - 2011" (Юрмала).  3 тур. Вопрос 11.\n'
    'Текст вопроса.\n'
    'Ответ: Уорхол.\n'
)

INDEX_BLOCKS = [
    {"type": "heading", "text": "95 тезисов", "images": []},
    {"type": "p", "text": "95 тезисов — документ Мартина Лютера.", "images": []},
    {"type": "p", "text": "От него отсчитывают начало Реформации.", "images": []},
    {"type": "quote", "text": "Кубок Европы. Вопрос 3.", "images": []},
    {"type": "p", "text": "Ответ: индульгенция.", "images": []},
]


def test_wiki_prose_stops_before_the_first_question():
    prose = wiki_prose(WIKI_1984)
    check("Роман-антиутопия" in prose, "вики: описание на месте")
    check("Уорхол" not in prose and "Ответ" not in prose,
          "вики: вопрос в справку не попал")


def test_wiki_table_of_contents_is_dropped():
    prose = wiki_prose(WIKI_1984)
    check("Содержание" not in prose, "вики: слово «Содержание» выброшено")
    check("2 Большой Брат" not in prose, "вики: строки оглавления выброшены")


def test_wiki_section_heading_is_marked_and_split_off():
    prose = wiki_prose(WIKI_1984)
    check("## События 1984 года" in prose, "вики: заголовок раздела помечен")
    check("События 1984 года Помимо выхода" not in prose,
          "вики: заголовок не склеен с абзацем")


def test_index_prose_keeps_text_before_the_question_and_drops_the_question():
    prose = index_prose(INDEX_BLOCKS)
    check("Мартина Лютера" in prose and "Реформации" in prose,
          "индекс: абзацы до вопроса на месте")
    check("Кубок Европы" not in prose and "индульгенция" not in prose,
          "индекс: вопрос и ответ в справку не попали")


# Кусок «Ковентри» (T31): три раздела, два из них — после вопросов. У первой
# записи в комментарии пустая строка — наивная граница «первая пустая строка
# после ответа» утащила бы хвост комментария в справку.
WIKI_COVENTRY = (
    'Ковентри появляется в вопросах по трём разным причинам.\n'
    '\n'
    '  Немецкая бомбардировка \n'
    'В 1940 году город был практически полностью уничтожен.\n'
    '\n'
    '"Знатокиада - 2009" (Эйлат).  2 тур. Вопрос 9.\n'
    'Кафедральный собор этого города был освящен в 1962 году. Назовите город.\n'
    'Ответ: Ковентри.\n'
    ' Комментарий: У Мандельштама:\n'
    '\n'
    '     Леди Годиву с распущенной рыжею гривой. Источник: 1. http://x.ru\n'
    '\n'
    '    3. http://y.ru Автор: Михаил Иванов (Саратов)\n'
    '\n'
    '  Леди Годива \n'
    'Ковентри и здесь оказался хорошим примером.\n'
    '\n'
    '"Покорение Меотиды - 2009" (Ейск).  2 тур. Вопрос 12.\n'
    'Назовите европейский город, где выбирают лучшую ЕЕ.\n'
    'Ответ: Ковентри.\n'
    ' Комментарий: Фестиваль. Автор: Григорий Алхазов (Кишинев)\n'
    '\n'
    '  Города-побратимы \n'
    'С Ковентри и Сталинграда началась история городов-побратимов.\n'
    '\n'
    '  См. также \n'
    'Сталинград\n'
)


def test_wiki_prose_takes_sections_after_questions():
    prose = wiki_prose(WIKI_COVENTRY)
    for h in ("## Немецкая бомбардировка", "## Леди Годива", "## Города-побратимы"):
        check(h in prose, f"вики: раздел «{h[3:]}» на месте")
    check("хорошим примером" in prose and "побратимов" in prose,
          "вики: проза после вопросов на месте")


def test_wiki_prose_leaks_nothing_from_records():
    prose = wiki_prose(WIKI_COVENTRY)
    for bit in ("Назовите", "Ответ", "Автор", "Годиву с распущенной", "http", "Эйлат"):
        check(bit not in prose, f"вики: «{bit}» из записи в справку не попало")
    check(leaks(prose) == [], "вики: страж утечек молчит")


def test_wiki_see_also_is_dropped_and_indented_list_is_not_a_heading():
    prose = wiki_prose(WIKI_COVENTRY)
    check("См. также" not in prose and "Сталинград\n" not in prose + "\n",
          "вики: «См. также» выброшено вместе с содержимым")
    films = wiki_prose("Фильмы:\n\n Иваново детство;\n Солярис.\n")
    check("• Иваново детство;\n• Солярис." in films and "## " not in films,
          "вики: строки с отступом — список, а не заголовок")


# Кусок «HAL 9000» и «Адрианова вала»: раздатка абзацами внутри записи,
# связка «или», запись без автора, стих, «Источники» со ссылками в конце.
INDEX_HAL = [
    {"type": "heading", "text": "HAL 9000"},
    {"type": "p", "text": "HAL 9000 — вымышленный компьютер."},
    {"type": "quote", "text": "Онлайн-турнир. Тур 2."},
    {"type": "quote", "text": "Вопрос 18:"},
    {"type": "p", "text": "Раздаточный материал"},
    {"type": "p", "text": "NY"},
    {"type": "quote", "text": "В машине героя установлен компьютер."},
    {"type": "quote", "text": "Ответ: 9000."},
    {"type": "quote", "text": "Автор: Александр Мерзликин"},
    {"type": "p", "text": "HAL был создан 12 января 1997 года."},
    {"type": "p", "text": "или"},
    {"type": "p", "text": "Вопрос 26"},
    {"type": "quote", "text": "Реконкиста · янв. 2023"},
    {"type": "quote", "text": "Текст второго вопроса."},
    {"type": "p", "text": "Ответ: IBM."},
    {"type": "quote", "text": "Комментарий: без автора."},
    {"type": "heading", "text": "Интересные факты"},
    {"type": "list", "text": "Киплинг посвятил валу три рассказа."},
    {"type": "aside", "text": "Я буду Риму здесь служить,"},
    {"type": "aside", "text": "Болота гатить, лес валить."},
    {"type": "list", "text": "Сцены «Короля Артура» происходят у вала."},
    {"type": "p", "text": "Источники:"},
    {"type": "list", "text": "https://ru.wikipedia.org/wiki/HAL_9000"},
]


def test_index_prose_takes_text_between_questions():
    prose = index_prose(INDEX_HAL, "HAL 9000")
    check("12 января 1997" in prose, "индекс: проза между вопросами на месте")
    check("## Интересные факты" in prose, "индекс: заголовок раздела помечен")
    check("## HAL 9000" not in prose, "индекс: заголовок-имя статьи выброшен")
    check("• Киплинг" in prose and "• Сцены" in prose, "индекс: пункты списка")
    check("Я буду Риму здесь служить,\nБолота гатить" in prose,
          "индекс: стих — один абзац построчно")


def test_index_prose_leaks_nothing_from_records():
    prose = index_prose(INDEX_HAL, "HAL 9000")
    for bit in ("Раздаточный", "NY", "установлен компьютер", "IBM", "Вопрос 26",
                "Реконкиста", "без автора", "Источники", "https"):
        check(bit not in prose, f"индекс: «{bit}» в справку не попало")
    check("\n\nили\n\n" not in f"\n\n{prose}\n\n", "индекс: связка «или» выброшена")
    check(leaks(prose) == [], "индекс: страж утечек молчит")


def test_record_without_author_does_not_swallow_the_prose_after_it():
    blocks = [
        {"type": "quote", "text": "Вопрос 1: Текст."},
        {"type": "quote", "text": "Ответ: Да."},
        {"type": "p", "text": "Проза после записи без автора."},
    ]
    check("Проза после записи" in index_prose(blocks),
          "индекс: запись без автора кончается на первом не-поле после ответа")


def test_wiki_wins_over_index_and_themes_outside_corpus_are_dropped():
    wiki = [{"name": "1984", "raw_text": WIKI_1984, "snapshot_url": "u1"}]
    index = [
        {"name": "1984", "blocks": INDEX_BLOCKS, "url": "u2"},
        {"name": "Чужая тема", "blocks": INDEX_BLOCKS, "url": "u3"},
    ]
    articles = build(wiki, index, themes={"1984"})
    check(len(articles) == 1, "тема вне корпуса в файл не поехала")
    check(articles[0]["source"] == "wiki",
          "вики поверх индекса: она пишет про вопросы, а не про предмет")


def test_theme_without_prose_is_absent():
    index = [{"name": "Пусто", "blocks": [{"type": "quote", "text": "Вопрос 1."}]}]
    articles = build([], index, themes={"Пусто"})
    check(articles == [], "тема без прозы: пустой справки не создаём")


def main():
    for test in [
        test_wiki_prose_stops_before_the_first_question,
        test_wiki_table_of_contents_is_dropped,
        test_wiki_section_heading_is_marked_and_split_off,
        test_index_prose_keeps_text_before_the_question_and_drops_the_question,
        test_wiki_prose_takes_sections_after_questions,
        test_wiki_prose_leaks_nothing_from_records,
        test_wiki_see_also_is_dropped_and_indented_list_is_not_a_heading,
        test_index_prose_takes_text_between_questions,
        test_index_prose_leaks_nothing_from_records,
        test_record_without_author_does_not_swallow_the_prose_after_it,
        test_wiki_wins_over_index_and_themes_outside_corpus_are_dropped,
        test_theme_without_prose_is_absent,
    ]:
        print(test.__name__)
        test()
    if _failures:
        print(f"\nПРОВАЛЕНО: {len(_failures)}")
        sys.exit(1)
    print("\nВсе проверки пройдены.")


if __name__ == "__main__":
    main()
