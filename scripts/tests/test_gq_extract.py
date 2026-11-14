"""Регрессия T34: JSON внутри экранированной строки Next.js."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from gq_extract import extract_questions, extract_authors_map, extract_pack


def page(payload):
    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    return '<script>self.__next_f.push([1,' + json.dumps(raw) + '])</script>'


class ExtractTests(unittest.TestCase):
    def test_metadata_belongs_to_requested_pack(self):
        html = page({'pack': {'id': 99, 'title': 'рекомендация'}})
        html += page({'pack': {'id': 37, 'title': 'нужный'}})
        self.assertEqual(extract_pack(html,37)['title'],'нужный')
        with self.assertRaises(ValueError):
            extract_pack(html,5)

    def test_long_preamble_reference_uses_utf8_byte_length(self):
        text = 'Пакет содержит материалы 18+.'
        html = page({'pack': {'id': 37, 'info': '$aa'}})
        stream = '\naa:T' + format(len(text.encode('utf-8')),'x') + ',' + text + '\n'
        html += '<script>self.__next_f.push(' + json.dumps([1,stream]) + ')</script>'
        self.assertEqual(extract_pack(html,37)['info'],text)

    def test_unbalanced_brackets_do_not_drop_tour(self):
        for text in ('[Ведущему: не закрыли', 'лишняя ]', 'кавычки " и путь \\ ['):
            with self.subTest(text=text):
                qs = [{"id": 1, "text": text}, {"id": 2, "text": "сосед"}]
                self.assertEqual(extract_questions(page({"tours": [{"questions": qs}]})), qs)

    def test_all_tours_and_duplicate_ids(self):
        qs = [{"id": 1, "text": "первый"}, {"id": 2, "text": "второй"}]
        html = page({"tours": [{"questions": qs[:1]}, {"questions": qs}]})
        self.assertEqual(extract_questions(html), qs)

    def test_authors_with_brackets(self):
        authors = [{"questionId": 1, "person": {"name": 'Автор [ " \\'}}]
        self.assertEqual(extract_authors_map(page({"authors": authors})), {1: ['Автор [ " \\']})

    def test_malformed_arrays_fail_with_count_instead_of_partial_result(self):
        html = page({"questions": [{"id": 1}]}) + page('unused')
        broken = '<script>"' + '\\"questions\\":[broken' + '"</script>'
        with self.assertRaisesRegex(ValueError, r'questions.*1.*2'):
            extract_questions(html + broken)

    def test_missing_and_empty_arrays(self):
        self.assertEqual(extract_questions(page({"title": "пусто"})), [])
        self.assertEqual(extract_questions(page({"questions": []})), [])


if __name__ == '__main__':
    unittest.main()
