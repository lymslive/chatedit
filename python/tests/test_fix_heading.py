"""测试 fix_heading_level：标题等级修正、代码块保护、流式跨调用状态"""
import sys, os, unittest
sys.path.insert(0, os.path.dirname(__file__))
from helper import load_ai_chat, make_opt

ai_chat = load_ai_chat()
ai_chat.opt = make_opt()

fix = ai_chat.fix_heading_level


class TestFixHeadingLevel(unittest.TestCase):
    def _fix(self, text):
        result, count = fix(text)
        return result, count

    def test_h1_becomes_h3(self):
        result, count = self._fix('# Title')
        self.assertEqual(result, '### Title')
        self.assertEqual(count, 1)

    def test_h2_becomes_h3(self):
        result, count = self._fix('## Title')
        self.assertEqual(result, '### Title')
        self.assertEqual(count, 1)

    def test_h3_becomes_h4(self):
        result, count = self._fix('### Title')
        self.assertEqual(result, '#### Title')
        self.assertEqual(count, 1)

    def test_h5_becomes_h6(self):
        result, count = self._fix('##### Title')
        self.assertEqual(result, '###### Title')
        self.assertEqual(count, 1)

    def test_h6_unchanged(self):
        result, count = self._fix('###### Title')
        self.assertEqual(result, '###### Title')
        self.assertEqual(count, 1)

    def test_no_heading_unchanged(self):
        result, count = self._fix('just text')
        self.assertEqual(result, 'just text')
        self.assertEqual(count, 0)

    def test_multiline_mixed(self):
        text = '# H1\nsome text\n## H2\n### H3\n'
        result, count = self._fix(text)
        self.assertEqual(count, 3)
        lines = result.split('\n')
        self.assertEqual(lines[0], '### H1')
        self.assertEqual(lines[2], '### H2')
        self.assertEqual(lines[3], '#### H3')

    def test_heading_inside_code_block_preserved(self):
        text = '```\n# not a heading\n```\n# real heading\n'
        result, count = self._fix(text)
        self.assertEqual(count, 1)
        self.assertIn('# not a heading', result)
        self.assertIn('### real heading', result)

    def test_returns_tuple(self):
        ret = fix('# H')
        self.assertIsInstance(ret, tuple)
        self.assertEqual(len(ret), 2)


class TestFixHeadingStreamState(unittest.TestCase):
    """流式场景：跨调用保持代码块状态"""

    def test_state_survives_across_calls(self):
        state = [False]
        r1, _ = fix('```\n# inside code\n', state)
        # 代码块已开启，下一个 delta 中的标题不应被修正
        self.assertFalse(state[0] is False or '### inside' in r1)

        r2, c2 = fix('# still inside\n```\n', state)
        self.assertEqual(c2, 0)  # 代码块内不修正
        self.assertIn('# still inside', r2)

        # 代码块关闭后恢复修正
        r3, c3 = fix('# outside\n', state)
        self.assertEqual(c3, 1)
        self.assertIn('### outside', r3)

    def test_independent_state_per_call_when_none(self):
        # 不传 state 时，每次调用独立处理
        r1, c1 = fix('```\n# inside\n```\n# outside\n')
        self.assertEqual(c1, 1)
        self.assertIn('# inside', r1)
        self.assertIn('### outside', r1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
