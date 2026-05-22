"""共用 helper：加载 ai-chat.py 模块（文件名含连字符，不能直接 import）"""
import argparse
import importlib.util
import os
import sys


def load_ai_chat():
    src = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'ai-chat.py'))
    spec = importlib.util.spec_from_file_location('ai_chat', src)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_opt(**kwargs):
    """生成最小化的 opt namespace，供测试直接注入到模块全局"""
    defaults = dict(
        debug=False,
        env=None,
        template=None,
        url='',
        key='',
        model='',
        system=None,
        append=False,
        reformat=None,
        encode=False,
        decode=False,
        simple=False,
        json=False,
        postdir='',
        stream=False,
        version=False,
        help=False,
        input=None,
    )
    defaults.update(kwargs)
    return argparse.Namespace(**defaults)
