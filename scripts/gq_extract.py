import json
import re


def extract_balanced(text, start_idx, open_ch, close_ch):
    depth = 0
    i = start_idx
    in_string = False
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\\":
            i += 2
            continue
        if ch == '"':
            in_string = not in_string
        elif not in_string:
            if ch == open_ch:
                depth += 1
            elif ch == close_ch:
                depth -= 1
                if depth == 0:
                    return text[start_idx:i + 1]
        i += 1
    return None


def unescape_json_fragment(fragment):
    wrapped = '"' + fragment + '"'
    inner_text = json.loads(wrapped)
    return json.loads(inner_text)


def extract_questions(html_text):
    questions = []
    seen_ids = set()
    for m in re.finditer(r'\\"questions\\":\[', html_text):
        bracket_start = m.end() - 1
        frag = extract_balanced(html_text, bracket_start, '[', ']')
        if not frag:
            continue
        try:
            arr = unescape_json_fragment(frag)
        except Exception:
            continue
        for q in arr:
            qid = q.get("id")
            if qid in seen_ids:
                continue
            seen_ids.add(qid)
            questions.append(q)
    return questions


def extract_authors_map(html_text):
    mapping = {}
    for m in re.finditer(r'\\"authors\\":\[', html_text):
        bracket_start = m.end() - 1
        frag = extract_balanced(html_text, bracket_start, '[', ']')
        if not frag:
            continue
        try:
            arr = unescape_json_fragment(frag)
        except Exception:
            continue
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
