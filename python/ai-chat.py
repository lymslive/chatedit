#!/usr/bin/env python3
# ai-chat.py - 将 markdown 聊天文件转换为 AI API 的 JSON 请求体并可直接发送请求
#
# 依赖：pip install openai（唯一第三方包，其余全部使用标准库）

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

VERSION = '1.0'

prog_name = os.path.splitext(os.path.basename(sys.argv[0]))[0]

# ---- 全局选项（由 parse_args 填充，供各函数访问） ----------------------------
opt = None


# ============================================================================
# 主入口
# ============================================================================

def main():
    global opt
    opt = parse_args()

    if opt.version:
        print(f'{prog_name} {VERSION}')
        sys.exit(0)

    if opt.help:
        usage()
        sys.exit(0)

    if opt.decode:
        decode_to_md()
        sys.exit(0)

    load_env()

    if opt.encode:
        opt.append = False  # --encode 时 --append 无效

    input_file = opt.input  # 位置参数

    fh = open_input(input_file)

    template = load_template()

    if opt.simple:
        content = fh.read()
        fh.close()
        content = content.rstrip()
        messages = [{'role': 'user', 'content': content}]
    else:
        messages = parse_chat(fh)
        fh.close()

    inject_system(messages)

    model_val = template.get('model', '')
    if re.search(r'\$\{?API_MODEL\}?', model_val):
        template['model'] = os.environ.get('API_MODEL', model_val)

    is_stream = opt.stream or template.get('stream') is True
    if is_stream:
        template['stream'] = True

    if opt.encode:
        template['messages'] = messages
        print(json.dumps(template, ensure_ascii=False, indent=2))
        sys.exit(0)

    api_url = os.environ.get('API_URL', '')
    api_key = os.environ.get('API_KEY', '')
    if not api_url:
        sys.stderr.write('错误: 未设置 API URL，请通过 --url 参数或 env 文件中的 API_URL 配置\n')
        sys.exit(1)
    if not api_key:
        sys.stderr.write('错误: 未设置 API KEY，请通过 --key 参数或 env 文件中的 API_KEY 配置\n')
        sys.exit(1)

    model = template.get('model', '')

    if opt.debug:
        masked = api_key[:6] + '****' + api_key[-4:] if len(api_key) >= 10 else '****'
        sys.stderr.write(f'[debug] POST {api_url} (key: {masked})\n')
        sys.stderr.write(f'[debug] model: {model}\n')

    if opt.postdir:
        save_to_postdir(opt.postdir, template, messages)

    try:
        from openai import OpenAI
    except ImportError:
        sys.stderr.write('错误: 请先安装 openai 包：pip install openai\n')
        sys.exit(1)

    client = make_client(api_url, api_key)

    if is_stream:
        run_stream(client, model, template, messages, input_file)
    else:
        run_non_stream(client, model, template, messages, input_file)


# ============================================================================
# 参数解析
# ============================================================================

def parse_args():
    parser = argparse.ArgumentParser(prog=prog_name, add_help=False)
    parser.add_argument('input', nargs='?', default=None,
                        help='输入 Markdown 文件（不指定则从 stdin 读取）')
    parser.add_argument('--template', '-t', default=None,
                        help='指定 JSON 模板文件')
    parser.add_argument('--debug', '-d', action='store_true',
                        help='输出调试信息到 stderr')
    parser.add_argument('--help', '-h', action='store_true',
                        help='显示帮助')
    parser.add_argument('--encode', action='store_true',
                        help='只输出组装的 JSON，不发送请求')
    parser.add_argument('--decode', action='store_true',
                        help='逆向：输入 API JSON，输出 Markdown 对话段')
    parser.add_argument('--append', '-a', action='store_true',
                        help='将 AI 回复追加到输入 .md 文件')
    parser.add_argument('--reformat', type=int, default=None,
                        help='控制格式化输出（0=关，1=开，默认按输出路径）')
    parser.add_argument('--env', default=None,
                        help='指定 env 文件')
    parser.add_argument('--url', default='',
                        help='API URL（覆盖 env 文件 API_URL）')
    parser.add_argument('--key', default='',
                        help='API Key（覆盖 env 文件 API_KEY）')
    parser.add_argument('--model', default='',
                        help='模型名（覆盖 env 文件 API_MODEL）')
    # --system 特殊用法：不传参数时 const=''，未指定时 None
    parser.add_argument('--system', nargs='?', const='', default=None,
                        help='system 消息；以 @ 开头时读取文件；不带参数时抑止自动查找')
    parser.add_argument('--simple', '-s', action='store_true',
                        help='将整个输入当成简单 user 消息')
    parser.add_argument('--json', '-j', action='store_true',
                        help='直接输出原始 API 响应 JSON')
    parser.add_argument('--postdir', default='',
                        help='将请求 JSON 保存到指定目录')
    parser.add_argument('--stream', action='store_true',
                        help='启用流式响应（SSE）')
    parser.add_argument('--version', '-v', action='store_true',
                        help='显示版本号')
    return parser.parse_args()


# ============================================================================
# 配置文件查找
# ============================================================================

def find_config_file(suffix):
    """按优先级搜索配置文件，prog_name 的所有目录优先于 ai-chat 回退"""
    dirs = ['.', './.chatedit']
    home = os.environ.get('HOME')
    if home:
        dirs.append(os.path.join(home, '.chatedit'))

    names = [f'{prog_name}.{suffix}']
    if prog_name != 'ai-chat':
        names.append(f'ai-chat.{suffix}')

    for name in names:
        for d in dirs:
            path = os.path.join(d, name)
            if os.path.isfile(path):
                if opt and opt.debug:
                    sys.stderr.write(f'[debug] 找到配置文件: {path}\n')
                return path
    return None


def find_env_file():
    return find_config_file('env')


def find_system_file():
    return find_config_file('sys')


def find_template_file():
    return find_config_file('json')


# ============================================================================
# 环境加载
# ============================================================================

def load_env():
    env_file = None

    if opt.env is not None:
        if not opt.env:
            if opt.debug:
                sys.stderr.write('[debug] --env 指定为空，抑止 env 文件查找\n')
        elif not os.path.isfile(opt.env):
            sys.stderr.write(f'警告: --env 指定的文件不存在: {opt.env}\n')
        else:
            env_file = opt.env
    else:
        env_file = find_env_file()

    if env_file:
        if opt.debug:
            sys.stderr.write(f'[debug] 加载 env 文件: {env_file}\n')
        with open(env_file, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                m = re.match(r'^(\w+)\s*=\s*(.*?)\s*$', line)
                if m:
                    k, v = m.group(1), m.group(2)
                    # 去除可能的引号
                    v = re.sub(r"^(['\"])(.*)\1$", r'\2', v)
                    os.environ.setdefault(k, v)

    if opt.url:
        os.environ['API_URL'] = opt.url
    if opt.key:
        os.environ['API_KEY'] = opt.key
    if opt.model:
        os.environ['API_MODEL'] = opt.model


# ============================================================================
# 模板加载
# ============================================================================

def default_template():
    return '{"model":"$API_MODEL","messages":[]}'


def load_template():
    file = None

    if opt.template is not None:
        if not opt.template:
            if opt.debug:
                sys.stderr.write('[debug] --template 指定为空，抑止模板文件查找\n')
        elif not os.path.isfile(opt.template):
            sys.stderr.write(f'警告: --template 指定的文件不存在: {opt.template}\n')
        else:
            file = opt.template
    else:
        file = find_template_file()

    if file:
        if opt.debug:
            sys.stderr.write(f'[debug] 模板文件: {file}\n')
        text = read_file_content(file)
    else:
        if opt.debug:
            sys.stderr.write('[debug] 使用内联默认模板\n')
        text = default_template()

    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        sys.stderr.write(f'错误: 模板 JSON 解析失败: {e}\n')
        sys.exit(1)

    # 删除 messages 字段（由 parse_chat 填充）
    data.pop('messages', None)
    return data


# ============================================================================
# 输入处理
# ============================================================================

def open_input(input_file):
    if input_file:
        try:
            fh = open(input_file, 'r', encoding='utf-8')
        except OSError as e:
            sys.stderr.write(f'错误: 无法打开文件 \'{input_file}\': {e}\n')
            sys.exit(1)
        if opt.debug:
            sys.stderr.write(f'[debug] 输入文件: {input_file}\n')
        return fh
    return open_stdin()


def open_stdin():
    if opt.debug:
        sys.stderr.write('[debug] 从 STDIN 读取输入（临时文件缓冲）\n')

    tmp = tempfile.NamedTemporaryFile(suffix='.md', delete=False, dir='/tmp')

    last_chunk = b''
    if opt.append:
        sys.stdout.buffer.flush()
        while True:
            chunk = sys.stdin.buffer.read(65536)
            if not chunk:
                break
            tmp.write(chunk)
            sys.stdout.buffer.write(chunk)
            last_chunk = chunk
        sys.stdout.buffer.flush()
        # 确保输出末尾有换行
        if last_chunk and not last_chunk.rstrip(b' \t').endswith(b'\n'):
            sys.stdout.buffer.write(b'\n')
            sys.stdout.buffer.flush()
    else:
        while True:
            chunk = sys.stdin.buffer.read(65536)
            if not chunk:
                break
            tmp.write(chunk)

    tmp.close()
    return open(tmp.name, 'r', encoding='utf-8')


# ============================================================================
# Markdown 聊天解析
# ============================================================================

ROLE_ABBR = {'P': 'system', 'Q': 'user', 'A': 'assistant'}


def normalize_role(raw):
    return ROLE_ABBR.get(raw.upper(), raw.lower())


def include_file(path):
    """读取文件内容，返回 (ok, lines_list)"""
    if not os.path.isfile(path):
        sys.stderr.write(f'警告: 引用文件不存在: {path}\n')
        return False, []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            lines = [line.rstrip('\n') for line in f]
        return True, lines
    except OSError as e:
        sys.stderr.write(f'警告: 无法读取文件 \'{path}\': {e}\n')
        return False, []


def run_command(cmd):
    """执行 shell 命令，返回 (ok, lines_list)"""
    if opt and opt.debug:
        sys.stderr.write(f'[debug] 执行命令: {cmd}\n')
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode != 0:
            sys.stderr.write(f'警告: 命令退出码非零 ({result.returncode}): {cmd}\n')
            return False, []
        output = result.stdout.rstrip('\n')
        return True, output.split('\n') if output else []
    except Exception as e:
        sys.stderr.write(f'警告: 命令执行失败: {e}\n')
        return False, []


def parse_chat(fh):
    """解析 Markdown 聊天文件，返回 message 列表"""
    messages = []
    cur_role = ''
    cur_lines = []
    in_code = False

    def flush():
        nonlocal cur_role, cur_lines
        if cur_role:
            content = '\n'.join(cur_lines)
            content = content.strip('\n')
            messages.append({'role': cur_role, 'content': content})
            cur_role = ''
            cur_lines = []

    for raw_line in fh:
        line = raw_line.rstrip('\n')

        if line.startswith('```'):
            in_code = not in_code
            if cur_role:
                cur_lines.append(line)
            continue

        if in_code:
            if cur_role:
                cur_lines.append(line)
            continue

        m = re.match(r'^##\s+(system|user|assistant|[PQA])\s*>>(.*)', line, re.IGNORECASE)
        if m:
            flush()
            cur_role = normalize_role(m.group(1))
            rest = m.group(2).lstrip()
            cur_lines = [rest] if rest else []
            continue

        # ## 非角色标题或 # 注释行：结束当前段落
        if re.match(r'^##([^#]|$)', line) or re.match(r'^#([^#]|$)', line):
            flush()
            continue

        if cur_role:
            # @file 导入
            m2 = re.match(r'^@\s*(\S.*)$', line)
            if m2:
                path = m2.group(1).rstrip()
                ok, included = include_file(path)
                if not ok:
                    cur_lines.append(f'{line} (Read Error)')
                elif not any(l.strip() for l in included):
                    cur_lines.append(f'{line} (Read Empty)')
                else:
                    cur_lines.extend(included)
                continue

            # !cmd 命令输出
            m3 = re.match(r'^!\s*(\S.*)$', line)
            if m3:
                cmd = m3.group(1).rstrip()
                ok, output = run_command(cmd)
                if not ok:
                    cur_lines.append(f'{line} (Read Error)')
                elif not any(l.strip() for l in output):
                    cur_lines.append(f'{line} (Read Empty)')
                else:
                    cur_lines.extend(output)
                continue

            cur_lines.append(line)

    flush()
    return messages


# ============================================================================
# 系统消息注入
# ============================================================================

def inject_system(messages):
    sys_content = None

    if opt.system is not None:
        if opt.system and opt.system != '0':
            sys_content = opt.system
            m = re.match(r'^@(.+)', sys_content)
            if m:
                path = m.group(1).strip()
                sys_content = read_file_content(path)
        # '' 或 '0' → 抑止，不插入
    else:
        sys_file = find_system_file()
        if sys_file:
            if opt.debug:
                sys.stderr.write(f'[debug] 使用 system 文件: {sys_file}\n')
            sys_content = read_file_content(sys_file)

    if sys_content:
        if not messages or messages[0]['role'] != 'system':
            messages.insert(0, {'role': 'system', 'content': sys_content})


# ============================================================================
# --decode 模式
# ============================================================================

def decode_to_md():
    args = sys.argv[1:]
    # 找到 --decode/--encode 之外的位置参数
    input_file = opt.input if opt else None

    if input_file:
        try:
            with open(input_file, 'rb') as f:
                json_bytes = f.read()
        except OSError as e:
            sys.stderr.write(f'错误: 无法打开文件 \'{input_file}\': {e}\n')
            sys.exit(1)
    else:
        json_bytes = sys.stdin.buffer.read()

    try:
        data = json.loads(json_bytes)
    except json.JSONDecodeError as e:
        sys.stderr.write(f'错误: 无法解析 JSON: {e}\n')
        sys.exit(1)

    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    for msg in data.get('messages', []):
        role = msg.get('role', 'unknown')
        content = msg.get('content', '')
        print(f'## {role} >>\n\n{content}\n')


# ============================================================================
# 工具函数
# ============================================================================

def read_file_content(path):
    """读取整个文件内容，去除首尾空白，失败时退出"""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        return content.strip()
    except OSError as e:
        sys.stderr.write(f'错误: 无法读取文件 \'{path}\': {e}\n')
        sys.exit(1)


def save_to_postdir(directory, template, messages):
    """将实际发送的请求 JSON 保存到 --postdir 目录，供调试用"""
    if not os.path.isdir(directory):
        sys.stderr.write(f'警告: --postdir 目录不存在: {directory}\n')
        return
    ts = time.strftime('%Y%m%d-%H%M%S')
    req = dict(template)
    req['messages'] = messages
    fname = os.path.join(directory, f'{prog_name}-{ts}-{os.getpid()}.json')
    try:
        with open(fname, 'w', encoding='utf-8') as f:
            json.dump(req, f, ensure_ascii=False, indent=2)
        if opt.debug:
            sys.stderr.write(f'[debug] 已保存请求 JSON: {fname}\n')
    except OSError as e:
        sys.stderr.write(f'警告: 无法写入 postdir 文件 \'{fname}\': {e}\n')


# ============================================================================
# 响应格式化
# ============================================================================

def fix_heading_level(content, in_code_state=None, has_top_heading=None):
    """
    修正 AI 回复中的 Markdown 标题等级。
    h1 → h3，h2 → h3，h3+ 各增加一级（最多 h6）。
    代码块（三反引号）内的标题保持原样。
    仅在遇到 h1/h2 标题后才开始修正（智能触发），若全文无 h1/h2 则不做任何修正。

    in_code_state: 列表 [bool]，供流式场景跨调用保持代码块状态。
    has_top_heading: 列表 [bool]，追踪是否已遇到 h1/h2 触发级标题。
    返回 (result_str, count)
    """
    state = in_code_state if in_code_state is not None else [False]
    has_top = has_top_heading if has_top_heading is not None else [False]
    lines = content.split('\n')
    count = 0
    for i, line in enumerate(lines):
        if line.startswith('```'):
            state[0] = not state[0]
            continue
        if state[0]:
            continue
        if not line.startswith('#'):
            continue
        level = len(line) - len(line.lstrip('#'))

        # 智能触发：尚未遇到 h1/h2 时，检查当前标题是否为触发级
        if not has_top[0]:
            if level <= 2:
                has_top[0] = True   # h1/h2 触发后续修正
            else:
                continue            # h3+ 且未触发，跳过修正

        count += 1
        if level == 1:
            lines[i] = '##' + line    # # → ###
        elif level < 6:
            lines[i] = '#' + line     # h2→h3, ..., h5→h6
        # level >= 6: 已到最大标题级，保持不变
    return '\n'.join(lines), count


def print_response(role, content, for_file):
    """
    将响应打印到 stdout。
    for_file: True=按文件模式（默认 reformat=1），False=按 stdout 模式（默认 reformat=0）
    """
    do_fmt = opt.reformat if opt.reformat is not None else (1 if for_file else 0)
    if do_fmt:
        content, _ = fix_heading_level(content)
    if do_fmt:
        sys.stdout.write(f'## {role} >>\n\n')
    sys.stdout.write(content + '\n')
    sys.stdout.flush()


def append_to_file(file_path, role, content):
    """
    追加响应到输入 .md 文件。
    返回 (lines_appended, reformed_count)
    """
    do_fmt = opt.reformat if opt.reformat is not None else 1

    reformed_count = 0
    if do_fmt:
        content, reformed_count = fix_heading_level(content)

    try:
        with open(file_path, 'a', encoding='utf-8') as wfh:
            wfh.write('\n')
            lines_appended = 0
            if do_fmt:
                wfh.write(f'## {role} >>\n\n')
                lines_appended += 2
            content_lines = content.split('\n')
            lines_appended += len(content_lines)
            wfh.write(content + '\n')
    except OSError as e:
        sys.stderr.write(f'错误: 无法写入文件 \'{file_path}\': {e}\n')
        sys.exit(1)

    return lines_appended, reformed_count


# ============================================================================
# API 客户端
# ============================================================================

def make_client(api_url, api_key):
    from openai import OpenAI
    # Perl 版 API_URL 通常包含完整路径（如 .../v1/chat/completions）
    # openai SDK 的 base_url 只需到 /v1，SDK 会自动追加具体端点
    base_url = re.sub(r'/chat/completions$', '', api_url)
    return OpenAI(base_url=base_url, api_key=api_key)


# ============================================================================
# API 调用：非流式
# ============================================================================

def call_api(client, model, messages):
    """非流式调用，返回 (role, content)"""
    resp = client.chat.completions.create(model=model, messages=messages)
    choice = resp.choices[0]
    role = choice.message.role or 'assistant'
    content = choice.message.content or ''
    return role, content


def call_api_raw(client, model, messages):
    """--json 非流式：打印原始响应 JSON"""
    with client.chat.completions.with_raw_response.create(
        model=model, messages=messages
    ) as response:
        sys.stdout.buffer.write(response.content)


# ============================================================================
# API 调用：流式
# ============================================================================

def call_api_stream(client, model, messages, reformat):
    """
    流式调用（SSE），实时输出到 stdout。
    reformat: 是否输出标题行并修正标题等级
    返回 (role, content)；content 为原始未修正文本
    """
    role = 'assistant'
    content = ''
    role_printed = False
    prev_ends_nl = True
    in_code_state = [False]
    has_top_heading = [False]

    stream = client.chat.completions.create(model=model, messages=messages, stream=True)
    for chunk in stream:
        delta = chunk.choices[0].delta if chunk.choices else None
        if delta is None:
            continue
        if getattr(delta, 'role', None):
            role = delta.role
        delta_text = getattr(delta, 'content', None) or ''
        if not delta_text:
            continue

        if reformat and not role_printed:
            sys.stdout.write(f'## {role} >>\n\n')
            role_printed = True
            prev_ends_nl = True

        if reformat:
            if prev_ends_nl:
                fixed, _ = fix_heading_level(delta_text, in_code_state, has_top_heading)
                sys.stdout.write(fixed)
            elif '\n' in delta_text:
                nl_pos = delta_text.index('\n')
                fixed_tail, _ = fix_heading_level(delta_text[nl_pos + 1:], in_code_state, has_top_heading)
                sys.stdout.write(delta_text[:nl_pos + 1] + fixed_tail)
            else:
                sys.stdout.write(delta_text)
        else:
            sys.stdout.write(delta_text)

        sys.stdout.flush()
        content += delta_text
        prev_ends_nl = delta_text.endswith('\n')

    return role, content


def call_api_stream_raw(client, model, messages):
    """--json --stream：转发原始 SSE 行"""
    with client.chat.completions.with_streaming_response.create(
        model=model, messages=messages, stream=True
    ) as response:
        for line in response.iter_lines():
            print(line)


# ============================================================================
# 运行模式：非流式
# ============================================================================

def run_non_stream(client, model, template, messages, input_file):
    if opt.json:
        call_api_raw(client, model, messages)
        return

    try:
        role, content = call_api(client, model, messages)
    except Exception as e:
        sys.stderr.write(f'错误: API 调用失败: {e}\n')
        sys.exit(1)

    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')

    if opt.append and input_file is None:
        # stdin 模式：输出到 stdout（已在 open_stdin 中复制原输入）
        print_response(role, content, True)
    else:
        print_response(role, content, False)

        if opt.append and input_file is not None:
            lines_appended, reformed = append_to_file(input_file, role, content)
            sys.stderr.write(
                f'# <!-- {lines_appended} lines appended to file: {input_file}; '
                f'reformated lines: {reformed} -->\n'
            )


# ============================================================================
# 运行模式：流式
# ============================================================================

def run_stream(client, model, template, messages, input_file):
    if opt.json:
        call_api_stream_raw(client, model, messages)
        return

    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')

    if opt.append and input_file is None:
        stdout_reformat = opt.reformat if opt.reformat is not None else 1
    else:
        stdout_reformat = opt.reformat if opt.reformat is not None else 0

    try:
        role, content = call_api_stream(client, model, messages, stdout_reformat)
    except Exception as e:
        sys.stderr.write(f'错误: 流式 API 调用失败: {e}\n')
        sys.exit(1)

    if content and not content.endswith('\n'):
        sys.stdout.write('\n')
    sys.stdout.flush()

    if opt.append and input_file is not None:
        lines_appended, reformed = append_to_file(input_file, role, content)
        sys.stderr.write(
            f'# <!-- {lines_appended} lines appended to file: {input_file}; '
            f'reformated lines: {reformed} -->\n'
        )


# ============================================================================
# 帮助信息
# ============================================================================

def usage():
    sys.stderr.write(f'''\
用法: {prog_name} [选项] [input.md]
      {prog_name} [选项] < input.md

将 Markdown 聊天文件解析为 AI API JSON 并直接发送请求，回复打印至 stdout；
可同时通过 --append/-a 将回复追加到输入文件。

选项（API 连接）:
  --env <file>       指定 env 文件（默认按优先级搜索 ai-chat.env）
  --url <url>        API URL（覆盖 env 文件 API_URL）
  --key <key>        API Key（覆盖 env 文件 API_KEY）
  --model <model>    模型名（覆盖 env 文件 API_MODEL）
  --system [msg]     system 消息；以 @ 开头时读取文件；不带参数时抑止自动查找
  -t, --template <file>  指定 JSON 模板文件

选项（行为）:
  -a, --append       将 AI 回复追加到输入 .md 文件；STDIN 模式则先将原输入复制到 stdout
  --reformat 0|1     控制格式化输出（0=关，1=开）；追加文件时默认 1，stdout 时默认 0
  -s, --simple       将整个输入当成简单 user 消息，跳过 Markdown 解析
  --stream           启用流式响应（SSE）

选项（调试）:
  --encode           只输出组装的 JSON（pretty），不发送请求
  --decode           逆向：输入 API JSON，输出 Markdown 对话段
  -j, --json         直接输出原始 API 响应 JSON，忽略 -a
  --postdir <dir>    将请求 JSON 保存到指定目录
  -d, --debug        打印调试信息到 stderr
  -v, --version      显示版本号
  -h, --help         显示此帮助

env 文件搜索顺序（PROG 为脚本名去掉 .py 后缀，如软链接 kimi-chat 则为 kimi-chat）:
  1. --env 指定的文件
  2. ./$PROG.env  （再回退 ./ai-chat.env）
  3. ./.chatedit/$PROG.env  （再回退 ./.chatedit/ai-chat.env）
  4. ~/.chatedit/$PROG.env  （再回退 ~/.chatedit/ai-chat.env）
''')


# ============================================================================
# 入口
# ============================================================================

if __name__ == '__main__':
    main()
