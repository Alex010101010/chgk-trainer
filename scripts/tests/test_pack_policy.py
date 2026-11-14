import sys
from pathlib import Path
from datetime import date
import unittest
import json
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from pack_policy import audience, cutoff, in_horizon
from sanitize_dumps import sanitize


class PolicyTests(unittest.TestCase):
    def test_dates_are_first_played_not_uploaded(self):
        now=date(2026,11,14)
        self.assertTrue(in_horizon('2016-11-14',now))
        for value in ('2016-11-13','2026-11-15',None,'unknown'):
            self.assertFalse(in_horizon(value,now))
        self.assertEqual(cutoff(date(2024,2,29)),date(2014,2,28))

    def test_explicit_18_overrides_false_flag(self):
        for pack in ({'title':'ЧерноСлив (18+)','adultOnly':False},
                     {'title':'Обычный','info':'Вопросы на чёрную тематику.'},
                     {'title':'Кубок поручика Ржевского – 2024','adultOnly':False},
                     {'title':'Кубки Ржевского'},
                     {'adultOnly':True}):
            self.assertEqual(audience(pack)[0],'adult')

    def test_black_sea_is_not_an_adult_label(self):
        self.assertEqual(audience({'title':'Кубок Чёрного моря','metadataChecked':True})[0],'standard')
        self.assertEqual(audience({'title':'Эротический турнир','metadataChecked':True})[0],'review')
        self.assertEqual(audience({'info':'$1a','metadataChecked':True})[0],'review')
        self.assertEqual(audience({'title':'обычный'})[0],'review')

    def test_adult_and_unverified_questions_cannot_enter_standard_pool(self):
        base = dict(question='Назовите город.',answer='Минск',packDate='2026-01-01',packSelected=True)
        for category in ('adult','review'):
            row=sanitize([{**base,'packAudience':category}],'gq',fresh_since='2016-11-14')[0]
            self.assertEqual(row['excluded'],category)
        # Бинго не ограничивается возрастом пакета.
        self.assertIsNone(sanitize([{**base,'packDate':'2001-01-01'}],'bingo')[0]['excluded'])
        self.assertEqual(sanitize([{**base,'takenDown':True}],'gq')[0]['excluded'],'taken_down')

    def test_real_prepared_corpus_obeys_catalog(self):
        data=Path(__file__).resolve().parents[2]/'data'
        catalog={p['id']:p for p in json.loads((data/'pack_catalog.json').read_text())}
        standard=[q for q in json.loads((data/'gq_clean.json').read_text()) if not q['excluded']]
        self.assertTrue(standard)
        for q in standard:
            pack=catalog[q['packId']]
            self.assertEqual(pack['audience'],'standard')
            self.assertTrue(pack['selected'])
            self.assertTrue(in_horizon(pack['startDate']))
            self.assertEqual(q['packDate'],pack['startDate'])
        adult_ids={q['id'] for p in json.loads((data/'gq_adult_dump.json').read_text()) for q in p['questions']}
        self.assertFalse(adult_ids & {q['id'] for q in standard})


if __name__=='__main__':
    unittest.main()
