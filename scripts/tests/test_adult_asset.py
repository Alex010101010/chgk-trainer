"""T36: отдельный набор 18+ без возрастного фильтра и смешивания."""
import copy
import json
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_app_assets import build_adult, build, load_rows

class AdultAssetTest(unittest.TestCase):
    def test_live_dump_is_separate_and_keeps_old_pack(self):
        adult = build_adult()
        ordinary = build(load_rows())
        self.assertGreater(adult['count'], 0)
        self.assertEqual(adult['count'], len(adult['questions']))
        self.assertFalse({q['id'] for q in adult['questions']} &
                         {q['id'] for q in ordinary['questions']})
        self.assertTrue(any(q['packDate'] == '2013-04-27' for q in adult['questions']))
        self.assertTrue(any(q['handoutText'] for q in adult['questions']))
        self.assertTrue(all(not q['handout'] for q in adult['questions']))

    def test_unverified_pack_is_rejected(self):
        for pack in ({'id': 1, 'audience': 'adult'},
                     {'id': 1, 'audience': 'standard', 'metadataChecked': True}):
            with self.assertRaises(ValueError):
                build_adult([{'pack': pack, 'questions': []}])

    def test_cleanup_and_unavailable_handout(self):
        pack = {'id': 1, 'audience': 'adult', 'metadataChecked': True,
                'startDate': '2000-01-01'}
        q = {'id': 'test-text', 'question': 'Назовите персонажа.',
             'answer': 'A &amp; B', 'sources': ['source'], 'razdatkaText': 'Текст &amp; текст'}
        bad = dict(q, id='test-image', razdatkaText=None, razdatkaPic='missing.png')
        asset = build_adult([{'pack': pack, 'questions': [q, bad]}])
        self.assertEqual(asset['count'], 1)
        self.assertEqual(asset['questions'][0]['answer'], 'A & B')
        self.assertEqual(asset['questions'][0]['handoutText'], 'Текст & текст')

if __name__ == '__main__':
    unittest.main()
