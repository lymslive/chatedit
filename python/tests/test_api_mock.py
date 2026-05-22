"""测试 run_non_stream 完整流程，使用 mock call_api（不需要真实 API）"""
import sys, os, io, unittest, tempfile
from unittest.mock import patch
sys.path.insert(0, os.path.dirname(__file__))
from helper import load_ai_chat, make_opt

ai_chat = load_ai_chat()


class TestRunNonStreamMock(unittest.TestCase):
    def setUp(self):
        ai_chat.opt = make_opt()

    def _make_client(self):
        """返回 None 占位——call_api 会被 mock，不会真正使用 client"""
        return None

    def test_prints_response_to_stdout(self):
        ai_chat.opt = make_opt(append=False)
        captured = io.StringIO()
        with patch.object(ai_chat, 'call_api', return_value=('assistant', 'Hello World')):
            with patch('sys.stdout', new=captured):
                ai_chat.run_non_stream(None, 'model', {}, [], None)
        output = captured.getvalue()
        self.assertIn('Hello World', output)

    def test_reformat_1_adds_header(self):
        ai_chat.opt = make_opt(append=False, reformat=1)
        captured = io.StringIO()
        with patch.object(ai_chat, 'call_api', return_value=('assistant', 'Some reply')):
            with patch('sys.stdout', new=captured):
                ai_chat.run_non_stream(None, 'model', {}, [], None)
        output = captured.getvalue()
        self.assertIn('## assistant >>', output)
        self.assertIn('Some reply', output)

    def test_append_to_file(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
            f.write('## user >>\nhello\n')
            fname = f.name
        try:
            ai_chat.opt = make_opt(append=True, reformat=1)
            with patch.object(ai_chat, 'call_api', return_value=('assistant', 'Reply text')):
                with patch('sys.stdout', new=io.StringIO()):
                    ai_chat.run_non_stream(None, 'model', {}, [], fname)
            with open(fname, 'r') as f:
                content = f.read()
            self.assertIn('## assistant >>', content)
            self.assertIn('Reply text', content)
        finally:
            os.unlink(fname)

    def test_stdin_mode_append_goes_to_stdout(self):
        """input_file=None + --append：响应写入 stdout，不写文件"""
        ai_chat.opt = make_opt(append=True, reformat=1)
        captured = io.StringIO()
        with patch.object(ai_chat, 'call_api', return_value=('assistant', 'Stdout reply')):
            with patch('sys.stdout', new=captured):
                ai_chat.run_non_stream(None, 'model', {}, [], None)
        output = captured.getvalue()
        self.assertIn('## assistant >>', output)
        self.assertIn('Stdout reply', output)

    def test_fix_heading_applied_when_append(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
            f.write('## user >>\nhello\n')
            fname = f.name
        try:
            ai_chat.opt = make_opt(append=True, reformat=1)
            reply = '# Top level\n## Second level\nsome text\n'
            with patch.object(ai_chat, 'call_api', return_value=('assistant', reply)):
                with patch('sys.stdout', new=io.StringIO()):
                    ai_chat.run_non_stream(None, 'model', {}, [], fname)
            with open(fname, 'r') as f:
                content = f.read()
            # h1 → h3, h2 → h3
            self.assertIn('### Top level', content)
            self.assertIn('### Second level', content)
        finally:
            os.unlink(fname)


class TestDecodeToMd(unittest.TestCase):
    def test_decode_outputs_markdown(self):
        req_json = '{"messages":[{"role":"user","content":"hello"},{"role":"assistant","content":"hi"}]}'
        captured = io.StringIO()
        ai_chat.opt = make_opt()
        with patch('sys.stdin', io.TextIOWrapper(io.BytesIO(req_json.encode()))):
            with patch('sys.stdout', new=captured):
                ai_chat.decode_to_md()
        output = captured.getvalue()
        self.assertIn('## user >>', output)
        self.assertIn('hello', output)
        self.assertIn('## assistant >>', output)
        self.assertIn('hi', output)


if __name__ == '__main__':
    unittest.main(verbosity=2)
