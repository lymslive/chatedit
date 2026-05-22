"""测试 parse_chat 状态机：角色段落、注释、代码块、@file、!cmd"""
import sys, os, io, unittest, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from helper import load_ai_chat, make_opt

ai_chat = load_ai_chat()
ai_chat.opt = make_opt()


def parse(text):
    return ai_chat.parse_chat(io.StringIO(text))


class TestParseChatBasic(unittest.TestCase):
    def test_single_user(self):
        msgs = parse('## user >>\nhello\n')
        self.assertEqual(len(msgs), 1)
        self.assertEqual(msgs[0]['role'], 'user')
        self.assertEqual(msgs[0]['content'], 'hello')

    def test_multi_turn(self):
        text = '## user >>\nhi\n## assistant >>\nbye\n'
        msgs = parse(text)
        self.assertEqual(len(msgs), 2)
        self.assertEqual(msgs[0]['role'], 'user')
        self.assertEqual(msgs[1]['role'], 'assistant')

    def test_role_abbreviations(self):
        text = '## P >>\nsys msg\n## Q >>\nuser msg\n## A >>\nasst msg\n'
        msgs = parse(text)
        self.assertEqual(msgs[0]['role'], 'system')
        self.assertEqual(msgs[1]['role'], 'user')
        self.assertEqual(msgs[2]['role'], 'assistant')

    def test_inline_content_after_arrow(self):
        msgs = parse('## user >> inline text\n')
        self.assertEqual(msgs[0]['content'], 'inline text')

    def test_comment_line_h1_ignored(self):
        text = '# this is a comment\n## user >>\nhello\n'
        msgs = parse(text)
        self.assertEqual(len(msgs), 1)
        self.assertEqual(msgs[0]['content'], 'hello')

    def test_non_role_h2_separator(self):
        text = '## user >>\nhello\n## Not a role\n## assistant >>\nbye\n'
        msgs = parse(text)
        self.assertEqual(len(msgs), 2)

    def test_content_stripped_leading_trailing_newlines(self):
        text = '## user >>\n\nhello\n\n'
        msgs = parse(text)
        self.assertEqual(msgs[0]['content'], 'hello')

    def test_multiline_content(self):
        text = '## user >>\nline1\nline2\nline3\n'
        msgs = parse(text)
        self.assertEqual(msgs[0]['content'], 'line1\nline2\nline3')

    def test_empty_input(self):
        msgs = parse('')
        self.assertEqual(msgs, [])

    def test_no_role_header(self):
        msgs = parse('just some text\n')
        self.assertEqual(msgs, [])


class TestParseChatCodeBlock(unittest.TestCase):
    def test_heading_inside_code_block_ignored(self):
        text = '## user >>\n```\n## system >> fake\n```\nreal content\n'
        msgs = parse(text)
        self.assertEqual(len(msgs), 1)
        self.assertIn('## system >> fake', msgs[0]['content'])

    def test_hash_comment_inside_code_block_ignored(self):
        text = '## user >>\n```bash\n# shell comment\n```\nend\n'
        msgs = parse(text)
        self.assertIn('# shell comment', msgs[0]['content'])

    def test_code_block_preserved(self):
        text = '## user >>\n```\ncode here\n```\n'
        msgs = parse(text)
        self.assertIn('```', msgs[0]['content'])
        self.assertIn('code here', msgs[0]['content'])


class TestParseChatFileInclude(unittest.TestCase):
    def test_include_existing_file(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            f.write('file content here\n')
            fname = f.name
        try:
            text = f'## user >>\n@{fname}\n'
            msgs = parse(text)
            self.assertIn('file content here', msgs[0]['content'])
        finally:
            os.unlink(fname)

    def test_include_missing_file(self):
        text = '## user >>\n@/nonexistent/file.txt\n'
        msgs = parse(text)
        self.assertIn('Read Error', msgs[0]['content'])

    def test_include_empty_file(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            fname = f.name
        try:
            text = f'## user >>\n@{fname}\n'
            msgs = parse(text)
            self.assertIn('Read Empty', msgs[0]['content'])
        finally:
            os.unlink(fname)


class TestParseChatCommand(unittest.TestCase):
    def test_command_output(self):
        text = '## user >>\n! echo hello_cmd\n'
        msgs = parse(text)
        self.assertIn('hello_cmd', msgs[0]['content'])

    def test_command_failure(self):
        text = '## user >>\n! false\n'
        msgs = parse(text)
        self.assertIn('Read Error', msgs[0]['content'])

    def test_command_empty_output(self):
        text = '## user >>\n! true\n'
        msgs = parse(text)
        self.assertIn('Read Empty', msgs[0]['content'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
