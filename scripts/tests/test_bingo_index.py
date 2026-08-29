"""Тесты добытчиков статей индекса бинго (T16, шаг 1).
Запуск: python3 scripts/tests/test_bingo_index.py

Без сети: четыре фикстуры — по одной на добытчика, взяты с живых статей 30.08.2026.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from bingo_index_blocks import (
    dashed_page_id,
    parse_notion,
    parse_telegraph,
    parse_teletype,
    parse_vk,
)

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")
BLOCK_TYPES = {"p", "quote", "aside", "heading", "figure", "list"}

NOTION_PAGE = "383ceff1-e975-8083-867d-e0820c8edb0b"
NOTION_ORIGIN = "https://planet-tabletop-d82.notion.site"

_failures = []


def all_sources():
    return (
        ("vk", load_vk()),
        ("telegraph", load_telegraph()),
        ("teletype", load_teletype()),
        ("notion", load_notion()),
    )


def check(condition, message):
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        _failures.append(message)


def load_vk():
    with open(os.path.join(FIXTURES, "vk_o_myshah_i_lyudyah.html"), "rb") as f:
        return parse_vk(f.read())


def load_telegraph():
    with open(os.path.join(FIXTURES, "telegraph_pepelnaya_sreda.json"), encoding="utf-8") as f:
        return parse_telegraph(json.load(f))


def load_teletype():
    with open(os.path.join(FIXTURES, "teletype_krasnaya_seledka.html"), "rb") as f:
        return parse_teletype(f.read())


def load_notion():
    with open(os.path.join(FIXTURES, "notion_alberto_giacometti.json"), encoding="utf-8") as f:
        return parse_notion(json.load(f), NOTION_PAGE, NOTION_ORIGIN)


def test_all_four_give_the_same_shape():
    """Смысл шага 1: дальше по конвейеру идёт одна форма, а не четыре."""
    for name, blocks in all_sources():
        check(bool(blocks), f"{name}: блоки извлечены")
        check(
            all(set(b) == {"type", "text", "images"} for b in blocks),
            f"{name}: у каждого блока ровно три поля",
        )
        check(
            all(b["type"] in BLOCK_TYPES for b in blocks),
            f"{name}: все типы блоков известны",
        )
        check(
            any(b["type"] == "quote" and b["text"].startswith("Вопрос") for b in blocks),
            f"{name}: блок с вопросом на месте",
        )


def test_vk_page_is_cp1251_not_utf8():
    """VK отдаёт статьи в **cp1251**, а не в utf-8.

    Красно-зелёный против типового допущения «нынче все сайты в utf-8»: с жёстко
    зашитым `encoding="utf-8"` эта фикстура даёт 3648 символов U+FFFD и ноль
    вхождений «Стейнбек» (проверено мутацией 30.08.2026).

    Против другой мутации — «пусть lxml угадает сам» — тест НЕ красный: у VK
    честный `<meta charset>`, и угадывание здесь попадает. Тот случай, что
    испортил вики-дамп, воспроизводится на архивных страницах с двойным набором
    meta, а не тут; его стережёт `test_parsing_keeps_guillemets` в test_sanitize.
    """
    blocks = load_vk()
    text = " ".join(b["text"] for b in blocks)
    check("Стейнбек" in text, "кириллица разобрана верно")
    check("�" not in text, "ни одного U+FFFD")
    check("Ð" not in text, "ни одного мойибейка latin-1")


def test_vk_stub_page_is_an_error_not_an_empty_article():
    """VK отвечает 200 и страницей «Памылка», если User-Agent не браузерный.
    Пустой список здесь записал бы такую страницу в дамп как успешную статью."""
    stub = b"<html><body><div class='page_block'>\xcf\xe0\xec\xfb\xeb\xea\xe0</div></body></html>"
    check(parse_vk(stub) is None, "страница без контейнера статьи -> None, а не []")
    check(load_vk() is not None, "настоящая статья при этом разбирается")


def test_images_carry_absolute_urls_and_captions():
    """Скачивать в шаге 5 будет нечего, если src остался относительным."""
    tg = load_telegraph()
    tg_images = [i for b in tg for i in b["images"]]
    check(bool(tg_images), "телеграф: картинки найдены")
    check(
        all(i["src"].startswith("https://telegra.ph/file/") for i in tg_images),
        "телеграф: относительный /file/... развёрнут в абсолютный URL",
    )
    check(
        any(i["caption"] == "Карл Шпицвег. «Пепельная среда»" for i in tg_images),
        "телеграф: подпись под картинкой сохранена",
    )

    vk_images = [i for b in load_vk() for i in b["images"]]
    check(bool(vk_images), "vk: картинки найдены")
    check(all(i["src"].startswith("https://") for i in vk_images), "vk: абсолютные URL")
    check(
        any(i["caption"] == "Джон Стейнбек (1902—1968)" for i in vk_images),
        "vk: подпись под картинкой сохранена",
    )


def test_notion_attachment_is_resolved_to_a_downloadable_url():
    """`attachment:<uuid>:image.png` сам по себе не скачивается: вложение отдаётся
    только через прокси сайта, с `table`, `id` и `spaceId` в query. А картинка,
    которую автор вставил внешней ссылкой, обязана проехать нетронутой — в этой
    статье так лежит раздатка с `gotquestions.online/pics/`."""
    images = [i for b in load_notion() for i in b["images"]]
    check(bool(images), "notion: картинки найдены")
    check(
        not any(i["src"].startswith("attachment:") for i in images),
        "notion: ни одной неразвёрнутой строки attachment:",
    )
    proxied = [i["src"] for i in images if i["src"].startswith(NOTION_ORIGIN + "/image/")]
    check(bool(proxied), "notion: вложения развёрнуты в прокси-URL")
    check(
        all("table=block" in src and "spaceId=" in src for src in proxied),
        "notion: подпись запроса на месте",
    )
    check(
        any(i["src"] == "https://gotquestions.online/pics/6297/415560_razdatka.png" for i in images),
        "notion: внешняя ссылка проехала нетронутой",
    )


def test_notion_walks_children_not_the_table_of_contents():
    """Обход по структурному `content[]`, включая вложенные блоки. Крауль по
    оглавлению молча теряет то, чего в оглавлении нет — так T1 потерял три темы."""
    payload = {
        "recordMap": {
            "block": {
                "root": {"value": {"id": "root", "type": "page", "content": ["a"]}},
                "a": {
                    "value": {
                        "id": "a",
                        "type": "numbered_list",
                        "properties": {"title": [["видимый пункт"]]},
                        "content": ["b"],
                    }
                },
                "b": {
                    "value": {
                        "id": "b",
                        "type": "text",
                        "properties": {"title": [["вложенный абзац"]]},
                    }
                },
            }
        }
    }
    blocks = parse_notion(payload, "root", NOTION_ORIGIN)
    texts = [b["text"] for b in blocks]
    check(texts == ["видимый пункт", "вложенный абзац"], "вложенный блок не потерян")
    check(parse_notion({"recordMap": {"block": {}}}, "root", NOTION_ORIGIN) is None,
          "ответ без корневого блока -> None, а не []")


def test_teletype_splits_lines_glued_by_br():
    """У teletype весь вопрос лежит одним `<section>`, метки разделены только
    `<br>`. Красно-зелёный: без разбиения `text_content()` склеивает название
    турнира с меткой — «ХимГумФестВопрос 28В книге…» — и разборщик меток
    промахивается по всем сразу."""
    blocks = load_teletype()
    texts = [b["text"] for b in blocks]
    check("ХимГумФест" in texts, "название турнира — отдельной строкой")
    check("Вопрос 28" in texts, "метка вопроса — отдельной строкой")
    check(
        not any(t.startswith("ХимГумФестВопрос") for t in texts),
        "склейки турнира с меткой нет",
    )
    check(
        sum(1 for t in texts if t.startswith("Вопрос ")) >= 6,
        "вопросы статьи найдены",
    )


def test_notion_page_id_gets_dashes():
    """loadPageChunk на id без дефисов отвечает ошибкой, а не страницей."""
    check(
        dashed_page_id("383ceff1e9758083867de0820c8edb0b") == NOTION_PAGE,
        "id из ссылки развёрнут в дефисный вид",
    )
    check(dashed_page_id(NOTION_PAGE) == NOTION_PAGE, "уже дефисный id не портится")


def test_whitespace_is_collapsed():
    """`\\xa0` не совпадает с `\\s` в части регулярок — разборщик вопросов
    промахнётся по меткам, если неразрывные пробелы доедут до него."""
    for name, blocks in all_sources():
        check(
            all("\xa0" not in b["text"] and b["text"] == b["text"].strip() for b in blocks),
            f"{name}: пробелы схлопнуты, края обрезаны",
        )


def main():
    for test in [
        test_all_four_give_the_same_shape,
        test_vk_page_is_cp1251_not_utf8,
        test_vk_stub_page_is_an_error_not_an_empty_article,
        test_images_carry_absolute_urls_and_captions,
        test_notion_attachment_is_resolved_to_a_downloadable_url,
        test_notion_walks_children_not_the_table_of_contents,
        test_teletype_splits_lines_glued_by_br,
        test_notion_page_id_gets_dashes,
        test_whitespace_is_collapsed,
    ]:
        print(test.__name__)
        test()
    if _failures:
        print(f"\nПРОВАЛЕНО: {len(_failures)}")
        sys.exit(1)
    print("\nВсе проверки пройдены.")


if __name__ == "__main__":
    main()
