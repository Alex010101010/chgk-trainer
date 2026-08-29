"""Нормализованные блоки статьи индекса бинго (T16, шаг 1).

Три хоста отдают статью тремя разными способами, но дальше по конвейеру идёт
одна форма — список блоков `{type, text, images}`. Разборщик вопросов не знает,
из какого хоста пришёл блок: иначе каждая правка формата множилась бы на три.

Разбор (`parse_*`) отделён от сети (`fetch_*`) намеренно — тесты гоняют разбор
на сохранённых фикстурах и в сеть не ходят.
"""
import copy
import json
import re
import time
import urllib.parse

import requests

from scrape_bingo_wiki import HEADERS, RETRY_SLEEPS, parse_html, polite_get

# Версия добытчиков. Статья, взятая прежней версией, скачана — но не обязательно
# годна; без отдельного поля «скачано» и «скачано годным кодом» не различить.
# Тот же приём, что `DECODER_VERSION` в `scrape_bingo_wiki.py`.
FETCHER_VERSION = 1

# VK отдаёт статью только браузерному User-Agent. С проектным UA приходит
# **статус 200** и страница «Памылка» на 123 КБ — без контейнера статьи и в
# другой кодировке. То есть неверный UA выглядит не как ошибка, а как пустая
# статья, и молча уехал бы в дамп. Отсюда и браузерный UA здесь, и проверка
# контейнера в `parse_vk`.
VK_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
    )
}

TELEGRAPH_API = "https://api.telegra.ph/getPage"
# Сам `telegra.ph` из части сетей режется на TLS-хендшейке, а `api.telegra.ph`
# отвечает. Побочная выгода: API отдаёт готовое дерево узлов, и HTML-парсер под
# телеграф не нужен вовсе.
TELEGRAPH_BASE = "https://telegra.ph"

NOTION_CHUNK = "/api/v3/loadPageChunk"


def _norm(text):
    """Схлопнуть пробелы. `\\xa0` — не пробел для регулярок, а в статьях его много."""
    if not text:
        return ""
    return re.sub(r"\s+", " ", text.replace("\xa0", " ")).strip()


def block(type_, text, images=None):
    return {"type": type_, "text": _norm(text), "images": images or []}


def _keep(b):
    """Блок без текста и без картинок не несёт ничего — разделители, пустые абзацы."""
    return bool(b and (b["text"] or b["images"]))


# --------------------------------------------------------------------------- VK

VK_CONTAINER = '//div[contains(@class,"article_view")]'
VK_TAGS = {
    "p": "p",
    "blockquote": "quote",
    "aside": "aside",
    "cite": "p",
    "h1": "heading",
    "h2": "heading",
    "h3": "heading",
    "h4": "heading",
    "figure": "figure",
    "ul": "list",
    "ol": "list",
}


def _html_images(el):
    """Картинки блока и подпись к ним. `figcaption` — подпись, а не проза."""
    caption = _norm(" ".join(c.text_content() for c in el.xpath(".//figcaption")))
    images = []
    for img in el.xpath(".//img"):
        src = img.get("src") or img.get("data-src") or ""
        if src.startswith("http"):
            images.append({"src": src, "caption": caption or None})
    return images, caption


def _html_text(el):
    """Текст блока без подписи к картинке — иначе подпись слипается с прозой.

    Подписи выкусываются из копии дерева, а не вычитаются из строки: подпись
    вроде «Джон Стейнбек» встречается и в прозе, и замена по тексту убрала бы
    оба вхождения.
    """
    clone = copy.deepcopy(el)
    for cap in clone.xpath(".//figcaption"):
        cap.getparent().remove(cap)
    return clone.text_content()


def parse_vk(raw_bytes):
    """Блоки статьи VK или None, если статьи на странице нет.

    None — это «не взяли», а не «статья пустая»: VK отвечает 200 и страницей
    «Памылка», когда UA не браузерный, и молчаливый пустой список записал бы
    такую страницу в дамп как успешную.
    """
    tree = parse_html(raw_bytes)
    container = tree.xpath(VK_CONTAINER)
    if not container:
        return None
    blocks = []
    for el in container[0]:
        if not isinstance(el.tag, str):
            continue
        type_ = VK_TAGS.get(el.tag, "p")
        images, caption = _html_images(el)
        # У блока-картинки текст — это подпись, а не проза. Одинаково во всех
        # трёх добытчиках: разборщик вопросов не должен угадывать по хосту.
        text = caption if type_ == "figure" else _html_text(el)
        blocks.append(block(type_, text, images))
    return [b for b in blocks if _keep(b)]


def fetch_vk(url):
    r, err = polite_get_with_headers(url, VK_HEADERS)
    if r is None:
        return None, err
    blocks = parse_vk(r.content)
    if blocks is None:
        return None, "нет контейнера статьи (страница-заглушка VK?)"
    return blocks, None


# -------------------------------------------------------------------- telegraph

TELEGRAPH_TAGS = {
    "p": "p",
    "blockquote": "quote",
    "aside": "aside",
    "h3": "heading",
    "h4": "heading",
    "figure": "figure",
    "ul": "list",
    "ol": "list",
}


def _tg_walk(node, out_images, skip=()):
    """Текст узла телеграфа; картинки складываются в `out_images` по дороге."""
    if isinstance(node, str):
        return node
    tag = node.get("tag")
    if tag == "img":
        src = (node.get("attrs") or {}).get("src") or ""
        if src.startswith("/"):
            src = TELEGRAPH_BASE + src
        if src:
            out_images.append({"src": src, "caption": None})
        return ""
    if tag == "br":
        return " "
    if tag in skip:
        return ""
    return "".join(_tg_walk(ch, out_images, skip) for ch in node.get("children") or [])


def _tg_block(node):
    if isinstance(node, str):
        return block("p", node)
    tag = node.get("tag")
    type_ = TELEGRAPH_TAGS.get(tag, "p")
    images = []
    # У figure текст блока — это подпись; у остальных подписи и нет.
    text = _tg_walk(node, images, skip=() if type_ == "figure" else ("figcaption",))
    if type_ == "figure":
        caption = _norm(text) or None
        for img in images:
            img["caption"] = caption
    return block(type_, text, images)


def parse_telegraph(payload):
    """Блоки статьи телеграфа или None, если API ответил отказом."""
    if not payload.get("ok"):
        return None
    blocks = [_tg_block(n) for n in payload["result"].get("content") or []]
    return [b for b in blocks if _keep(b)]


def fetch_telegraph(url):
    path = urllib.parse.urlparse(url).path.strip("/")
    r, err = polite_get(TELEGRAPH_API, params={"path": path, "return_content": "true"})
    if r is None:
        return None, err
    try:
        payload = r.json()
    except ValueError as e:
        return None, f"телеграф отдал не JSON: {e}"
    blocks = parse_telegraph(payload)
    if blocks is None:
        return None, f"телеграф: {payload.get('error')}"
    return blocks, None


# ------------------------------------------------------------------------ notion

NOTION_TAGS = {
    "text": "p",
    "quote": "quote",
    "callout": "p",
    "header": "heading",
    "sub_header": "heading",
    "sub_sub_header": "heading",
    "numbered_list": "list",
    "bulleted_list": "list",
    "toggle": "p",
    "image": "figure",
}


def dashed_page_id(raw):
    """`383ceff1e975...` → `383ceff1-e975-...`. loadPageChunk принимает только с дефисами."""
    raw = raw.replace("-", "")
    return "-".join([raw[:8], raw[8:12], raw[12:16], raw[16:20], raw[20:32]])


def _notion_value(record):
    """recordMap иногда завёрнут дважды: {'value': {'value': {...}, 'role': …}}."""
    value = record.get("value")
    if isinstance(value, dict) and "value" in value:
        value = value["value"]
    return value if isinstance(value, dict) else None


def _notion_prop(value, name):
    """Свойство Notion — массив отрезков `[текст, [форматы]]`; нужен только текст."""
    segments = (value.get("properties") or {}).get(name) or []
    return "".join(seg[0] for seg in segments if seg)


def _notion_text(value):
    return _notion_prop(value, "title")


def notion_image_url(value, origin):
    """Вложение отдаётся только через прокси самого сайта, с подписью в query."""
    source = ((value.get("properties") or {}).get("source") or [[""]])[0][0]
    if not source:
        return None
    if source.startswith("http"):
        return source
    return (
        f"{origin}/image/{urllib.parse.quote(source, safe='')}"
        f"?table=block&id={value.get('id')}&spaceId={value.get('space_id')}&cache=v2"
    )


def parse_notion(payload, page_id, origin):
    """Блоки страницы Notion или None, если корневого блока в ответе нет.

    Обход — по структурному `content[]` родителя, а не по оглавлению страницы:
    крауль по оглавлению молча пропускает то, чего в нём нет (T1 потерял так три
    темы из 139).
    """
    records = (payload.get("recordMap") or {}).get("block") or {}
    blocks = {k: _notion_value(v) for k, v in records.items()}
    root = blocks.get(page_id)
    if not root:
        return None

    out = []

    def walk(block_id):
        value = blocks.get(block_id)
        if not value or not value.get("alive", True):
            return
        type_ = NOTION_TAGS.get(value.get("type"))
        if type_ == "figure":
            url = notion_image_url(value, origin)
            caption = _norm(_notion_prop(value, "caption")) or None
            out.append(block("figure", caption or "", [{"src": url, "caption": caption}] if url else []))
        elif type_:
            out.append(block(type_, _notion_text(value)))
        for child in value.get("content") or []:
            walk(child)

    for child in root.get("content") or []:
        walk(child)
    return [b for b in out if _keep(b)]


def fetch_notion(url):
    parsed = urllib.parse.urlparse(url)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    page_id = dashed_page_id(parsed.path.rsplit("/", 1)[-1])
    body = {
        "pageId": page_id,
        "limit": 300,
        "cursor": {"stack": []},
        "chunkNumber": 0,
        "verticalColumns": False,
    }
    payload, err = _post_json(origin + NOTION_CHUNK, body)
    if payload is None:
        return None, err
    blocks = parse_notion(payload, page_id, origin)
    if blocks is None:
        return None, "в ответе нет корневого блока страницы"
    return blocks, None


# ------------------------------------------------------------------------- сеть


def polite_get_with_headers(url, headers, timeout=30):
    """`polite_get` из T1, но со своими заголовками — VK нужен браузерный UA."""
    last_error = "не пробовали"
    for pause in (0,) + RETRY_SLEEPS:
        if pause:
            time.sleep(pause)
        try:
            r = requests.get(url, headers={**HEADERS, **headers}, timeout=timeout)
            r.raise_for_status()
            return r, None
        except Exception as e:
            last_error = str(e)
    return None, last_error


def _post_json(url, body, timeout=30):
    last_error = "не пробовали"
    for pause in (0,) + RETRY_SLEEPS:
        if pause:
            time.sleep(pause)
        try:
            r = requests.post(
                url,
                data=json.dumps(body),
                headers={**HEADERS, "Content-Type": "application/json"},
                timeout=timeout,
            )
            r.raise_for_status()
            return r.json(), None
        except Exception as e:
            last_error = str(e)
    return None, last_error


FETCHERS = {"vk.com": fetch_vk, "telegra.ph": fetch_telegraph}


def fetch_article(host, url):
    """(блоки, None) либо (None, текст ошибки). Хост берётся из `bingo_index.json`."""
    if host.endswith("notion.site"):
        return fetch_notion(url)
    fetcher = FETCHERS.get(host)
    if not fetcher:
        return None, f"нет добытчика под хост {host}"
    return fetcher(url)
