"""测试 normalize_role：缩写与大小写处理"""
import sys, os, unittest
sys.path.insert(0, os.path.dirname(__file__))
from helper import load_ai_chat, make_opt

ai_chat = load_ai_chat()
ai_chat.opt = make_opt()


class TestNormalizeRole(unittest.TestCase):
    def test_full_names_lower(self):
        self.assertEqual(ai_chat.normalize_role('system'), 'system')
        self.assertEqual(ai_chat.normalize_role('user'), 'user')
        self.assertEqual(ai_chat.normalize_role('assistant'), 'assistant')

    def test_full_names_upper(self):
        self.assertEqual(ai_chat.normalize_role('SYSTEM'), 'system')
        self.assertEqual(ai_chat.normalize_role('USER'), 'user')
        self.assertEqual(ai_chat.normalize_role('ASSISTANT'), 'assistant')

    def test_mixed_case(self):
        self.assertEqual(ai_chat.normalize_role('System'), 'system')
        self.assertEqual(ai_chat.normalize_role('Assistant'), 'assistant')

    def test_abbr_upper(self):
        self.assertEqual(ai_chat.normalize_role('P'), 'system')
        self.assertEqual(ai_chat.normalize_role('Q'), 'user')
        self.assertEqual(ai_chat.normalize_role('A'), 'assistant')

    def test_abbr_lower(self):
        self.assertEqual(ai_chat.normalize_role('p'), 'system')
        self.assertEqual(ai_chat.normalize_role('q'), 'user')
        self.assertEqual(ai_chat.normalize_role('a'), 'assistant')


if __name__ == '__main__':
    unittest.main(verbosity=2)
