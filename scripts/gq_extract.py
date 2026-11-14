import json
import re


def _extract_arrays(html_text, key):
    """Сначала снять экранирование JS-строки, затем читать массив как JSON.

    Ошибки считаются по всем найденным фрагментам; частичный результат
    нельзя выдавать за успешно прочитанную страницу.
    """
    arrays = []
    failed = 0
    matches = list(re.finditer(r'\\"%s\\":\[' % re.escape(key), html_text))
    for match in matches:
        start = end = match.end() - 1
        while end < len(html_text) and html_text[end] != '"':
            end += 2 if html_text[end] == "\\" else 1
        try:
            decoded = json.loads('"' + html_text[start:end] + '"')
            value, _ = json.JSONDecoder().raw_decode(decoded)
        except json.JSONDecodeError:
            failed += 1
            continue
        arrays.append(value)
    if failed:
        raise ValueError(f"{key}: не разобраны {failed} из {len(matches)} массивов")
    return arrays


def extract_questions(html_text):
    questions = []
    seen_ids = set()
    for arr in _extract_arrays(html_text, "questions"):
        for q in arr:
            qid = q.get("id")
            if qid in seen_ids:
                continue
            seen_ids.add(qid)
            questions.append(q)
    return questions


def extract_authors_map(html_text):
    mapping = {}
    for arr in _extract_arrays(html_text, "authors"):
        for entry in arr:
            qid = entry.get("questionId")
            person = entry.get("person") or {}
            name = person.get("name")
            if qid and name:
                mapping.setdefault(qid, []).append(name)
    return mapping


def extract_title(html_text):
    m = re.search(r"<title>([^<]*)</title>", html_text)
    return m.group(1) if m else None


def extract_pack(html_text, pack_id):
    """Именно запрошенный пакет, а не первый из рекомендаций на странице."""
    match = re.search(r'\\"pack\\":\{\\"id\\":%d,' % pack_id, html_text)
    if not match:
        raise ValueError(f'pack {pack_id}: нет метаданных')
    start = html_text.index('{', match.start())
    end = start
    while end < len(html_text) and html_text[end] != '"':
        end += 2 if html_text[end] == '\\' else 1
    decoded = json.loads('"' + html_text[start:end] + '"')
    pack, _ = json.JSONDecoder().raw_decode(decoded)
    if pack.get('id') != pack_id:
        raise ValueError(f'pack {pack_id}: получен другой пакет')
    info = pack.get('info') or ''
    if re.fullmatch(r'\$[0-9a-f]+', info):
        chunks = []
        for m in re.finditer(r'self\.__next_f\.push\(', html_text):
            value, _ = json.JSONDecoder().raw_decode(html_text[m.end():])
            if len(value) > 1 and value[0] == 1 and isinstance(value[1], str):
                chunks.append(value[1])
        stream = ''.join(chunks).encode('utf-8')
        ref = info[1:].encode('ascii')
        m = re.search(rb'(?:^|\n)' + ref + rb':T([0-9a-fA-F]+),', stream)
        if m:
            size = int(m[1], 16)
            pack['info'] = stream[m.end():m.end()+size].decode('utf-8')
    return pack


if __name__ == "__main__":
    # Ad-hoc smoke test: fetch any pack page fresh and run the extractor on it.
    import requests
    html = requests.get(
        "https://gotquestions.online/pack/7019",
        headers={"User-Agent": "chgk-trainer-content-research/0.1 (non-commercial personal project)"},
        timeout=20,
    ).text
    qs = extract_questions(html)
    authors = extract_authors_map(html)
    title = extract_title(html)
    print("title:", title)
    print("questions found:", len(qs))
    for q in qs[:3]:
        print("---")
        print("id:", q.get("id"), "number:", q.get("number"))
        print("text:", q.get("text"))
        print("answer:", q.get("answer"))
        print("zachet:", q.get("zachet"))
        print("comment:", q.get("comment"))
        print("source:", q.get("source"))
        print("complexity:", q.get("complexity"))
        print("authors:", authors.get(q.get("id")))
