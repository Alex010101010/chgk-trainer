import re
import time
import lxml.html
import requests

HEADERS = {"User-Agent": "chgk-trainer-content-research/0.1 (non-commercial personal project)"}

def clean(text):
    return re.sub(r'\s+', ' ', text or '').strip()

def strip_label(text, labels):
    text = clean(text)
    for label in labels:
        m = re.match(rf'^{label}\s*:?\s*', text, flags=re.IGNORECASE)
        if m:
            return text[m.end():].strip()
    return text

def parse_tour_html(html):
    tree = lxml.html.fromstring(html)
    out = []
    for qdiv in tree.xpath('//div[contains(@class,"question")]'):
        def field(cls):
            p = qdiv.xpath(f'.//p[strong[contains(@class,"{cls}")]]')
            return clean(p[0].text_content()) if p else ''
        question = strip_label(field('Question'), [r'Вопрос\s*\d+'])
        answer = strip_label(field('Answer'), [r'Ответ'])
        comment = strip_label(field('Comments'), [r'Комментарий'])
        sources = strip_label(field('Sources'), [r'Источник\(и\)', r'Источник'])
        authors = strip_label(field('Authors'), [r'Автор\(ы\)', r'Авторы', r'Автор'])
        qid = qdiv.get('id', '')
        if question and answer:
            out.append({
                'id': qid, 'question': question, 'answer': answer,
                'comment': comment, 'sources': sources, 'authors': authors,
            })
    return out

if __name__ == '__main__':
    # Ad-hoc smoke test — db.chgk.info parser, kept as a fallback source (not used by
    # the active T5 pipeline, which uses gotquestions.online — see crawl_gotquestions.py).
    html = requests.get(
        "https://db.chgk.info/tour/vo03.3",
        headers=HEADERS,
        timeout=20,
    ).text
    items = parse_tour_html(html)
    print(f'Извлечено вопросов: {len(items)}')
    for it in items[:3]:
        print('---')
        for k, v in it.items():
            print(f'{k}: {v}')
