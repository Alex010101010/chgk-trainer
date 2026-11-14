"""Форма строки gotquestions; запуск делегируется проверке метаданных пакетов.

Обновление: refresh_pack_catalog.py --source data --out <временная папка>.
Старый случайный выбор из непроверенного скана больше не используется.
"""
import re


def as_dump_row(q, pack):
    """Та же форма, что у `crawl_gotquestions.py`, — санитайзер её уже знает."""
    sources_raw = q.get("source") or ""
    sources = [s.strip() for s in re.split(r"\n|(?:\d+\.\s)", sources_raw) if s.strip()]
    return {
        "id": f"gq-{q.get('id')}",
        "theme": None,
        "tournament": pack["title"],
        "question": q.get("text"),
        "answer": q.get("answer"),
        "acceptance": q.get("zachet") or None,
        "comment": q.get("comment") or None,
        "sources": sources,
        "author": ", ".join(q.get("authorNames") or []) or None,
        "complexity": q.get("complexity") or None,
        "packId": pack["id"],
        "packDate": pack["startDate"],
        "razdatkaPic": (q.get("razdatkaPic") or "").strip() or None,
        "razdatkaText": (q.get("razdatkaText") or "").strip() or None,
        "takenDown": bool(q.get("takenDown")),
    }


def main():
    from refresh_pack_catalog import main as refresh
    return refresh()


if __name__ == "__main__":
    main()
