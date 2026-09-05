"""Тесты извлечения справки по клише (T14, срез).
Запуск: python3 scripts/tests/test_bingo_articles.py

Фикстуры — куски настоящих статей: вики-статья с оглавлением и разделом,
статья индекса с вопросом-цитатой.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from structure_bingo_articles import build, index_prose, wiki_prose

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


def test_index_prose_stops_at_the_first_quote():
    prose = index_prose(INDEX_BLOCKS)
    check("Мартина Лютера" in prose and "Реформации" in prose,
          "индекс: абзацы до вопроса на месте")
    check("Кубок Европы" not in prose and "индульгенция" not in prose,
          "индекс: вопрос и ответ в справку не попали")


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
        test_index_prose_stops_at_the_first_quote,
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
