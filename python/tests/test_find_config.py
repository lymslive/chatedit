"""测试 find_config_file / load_env：搜索顺序、--env 选项处理"""
import sys, os, io, unittest, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from helper import load_ai_chat, make_opt

ai_chat = load_ai_chat()
ai_chat.opt = make_opt()


class TestFindConfigFile(unittest.TestCase):
    def setUp(self):
        # 记录原始 prog_name，测试后恢复
        self._orig_prog = ai_chat.prog_name

    def tearDown(self):
        ai_chat.prog_name = self._orig_prog

    def test_returns_none_when_not_found(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            orig_dir = os.getcwd()
            os.chdir(tmpdir)
            try:
                ai_chat.prog_name = 'ai-chat'  # 不产生额外回退
                # 使用不存在的 suffix，在空目录中肯定找不到
                result = ai_chat.find_config_file('nonexistent_suffix_xyz')
                self.assertIsNone(result)
            finally:
                os.chdir(orig_dir)

    def test_finds_file_in_current_dir(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            orig_dir = os.getcwd()
            os.chdir(tmpdir)
            try:
                ai_chat.prog_name = 'testprog'
                env_path = os.path.join(tmpdir, 'testprog.env')
                with open(env_path, 'w') as f:
                    f.write('KEY=val\n')
                result = ai_chat.find_config_file('env')
                self.assertEqual(os.path.abspath(result), os.path.abspath(env_path))
            finally:
                os.chdir(orig_dir)

    def test_fallback_to_ai_chat_suffix(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            orig_dir = os.getcwd()
            os.chdir(tmpdir)
            try:
                ai_chat.prog_name = 'other-prog'
                fallback = os.path.join(tmpdir, 'ai-chat.env')
                with open(fallback, 'w') as f:
                    f.write('KEY=val\n')
                result = ai_chat.find_config_file('env')
                self.assertEqual(os.path.abspath(result), os.path.abspath(fallback))
            finally:
                os.chdir(orig_dir)

    def test_no_fallback_when_prog_is_ai_chat(self):
        """prog_name == 'ai-chat' 时不重复搜索 ai-chat.env"""
        ai_chat.prog_name = 'ai-chat'
        # 搜索不存在的 suffix，只要不报错即可
        result = ai_chat.find_config_file('nonexistent_suffix_xyz')
        self.assertIsNone(result)


class TestLoadEnv(unittest.TestCase):
    def setUp(self):
        # 清理可能污染环境的 key
        for k in ('TEST_API_URL', 'TEST_API_KEY'):
            os.environ.pop(k, None)

    def test_loads_key_value_pairs(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write('TEST_API_URL=https://example.com/v1\n')
            f.write('TEST_API_KEY=sk-test\n')
            fname = f.name
        try:
            ai_chat.opt = make_opt(env=fname)
            ai_chat.load_env()
            self.assertEqual(os.environ.get('TEST_API_URL'), 'https://example.com/v1')
            self.assertEqual(os.environ.get('TEST_API_KEY'), 'sk-test')
        finally:
            os.unlink(fname)
            os.environ.pop('TEST_API_URL', None)
            os.environ.pop('TEST_API_KEY', None)

    def test_strips_quotes(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write("TEST_API_URL='https://quoted.com'\n")
            fname = f.name
        try:
            ai_chat.opt = make_opt(env=fname)
            ai_chat.load_env()
            self.assertEqual(os.environ.get('TEST_API_URL'), 'https://quoted.com')
        finally:
            os.unlink(fname)
            os.environ.pop('TEST_API_URL', None)

    def test_ignores_comments_and_blank_lines(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write('# comment line\n\nTEST_API_URL=clean\n')
            fname = f.name
        try:
            ai_chat.opt = make_opt(env=fname)
            ai_chat.load_env()
            self.assertEqual(os.environ.get('TEST_API_URL'), 'clean')
        finally:
            os.unlink(fname)
            os.environ.pop('TEST_API_URL', None)

    def test_cli_overrides_env_file(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write('API_URL=from_file\n')
            fname = f.name
        orig = os.environ.get('API_URL')
        try:
            ai_chat.opt = make_opt(env=fname, url='from_cli')
            ai_chat.load_env()
            self.assertEqual(os.environ.get('API_URL'), 'from_cli')
        finally:
            os.unlink(fname)
            if orig is None:
                os.environ.pop('API_URL', None)
            else:
                os.environ['API_URL'] = orig


if __name__ == '__main__':
    unittest.main(verbosity=2)
