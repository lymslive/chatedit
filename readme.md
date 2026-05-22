# chatedit — 可编辑的命令行 AI 聊天工具

利用 API 编程方式与大语言模型聊天，同时提供友好接口让用户自由编辑多轮会话中发送
给模型的具体内容，实现精确控制输入。

适用场合：
- 学习、研究 AI 模型的 API 典型调用方式
- 需要手动删改历史轮对话、精确控制每轮输入内容时
- 以 Markdown 文件管理对话历史，持久化保存多轮聊天

## 功能概览

| 工具 | 语言 | 功能 |
|------|------|------|
| `bash/ai-curl.sh` | Bash | 封装 curl，发送 JSON 请求到 AI API |
| `perl/ai-chat.pl` | Perl | 解析 Markdown 聊天文件，组装并发送 API 请求，回写文件 |
| `python/ai-chat.py` | Python | 与 `ai-chat.pl` 功能对等的 Python 实现，使用 `openai` SDK 替代 curl |

Perl 版与 Python 版接口完全一致，可互换使用；两者也可与 Bash 版管道联用：

```bash
cat chat.md | perl/ai-chat.pl --encode | bash/ai-curl.sh
python3 python/ai-chat.py -a chat.md   # Python 版等价用法
```

## 快速开始

### 1. 配置 API 环境

在项目根目录（或 `~/.chatedit/`）创建 `ai-curl.env`（或 `ai-chat.env`）文件：

```bash
API_URL=https://api.example.com/v1/chat/completions
API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxx
API_MODEL=gpt-4o
```

文件格式为标准 shell 赋值语法（`=` 两侧无空格），与 bash `source` 兼容。

### 2. 发送单条消息（ai-curl.sh）

```bash
# 发送 JSON 文件
bin/ai-curl testdata/chat-simple.json

# 从 STDIN 发送纯文本（--simple 模式）
echo "你好，请介绍一下自己" | bin/ai-curl --simple

# 带 system 提示的纯文本发送
echo "1+1等于几" | bin/ai-curl --simple --system "只用中文回答，保持简洁"
echo "1+1等于几" | bin/ai-curl --simple --system @testdata/system-chinese.txt
```

### 3. Markdown 聊天文件（ai-chat.pl / ai-chat.py）

创建聊天文件 `chat.md`（格式见 [docs/chat-format.md](docs/chat-format.md)）：

```markdown
## Q >> 你好，请简单介绍你自己。
```

发送并将回复追加到文件：

```bash
perl/ai-chat.pl -a chat.md
```

执行后终端会打印 AI 回复，同时 `chat.md` 末尾自动追加：

```markdown
## assistant >>

你好！我是 ...
```

多轮对话只需在文件末尾继续追加用户问题，再次运行即可。

## 详细用法

### bash/ai-curl.sh

```
用法: ai-curl [选项] [json_file]
      ai-curl [选项] < input.json

选项:
  --env <file>      指定 env 配置文件
  --url <url>       API URL（覆盖 env 文件）
  --key <key>       API Key（覆盖 env 文件）
  --model <model>   模型名（覆盖 env 文件）
  -s, --simple      将输入视为纯文本，自动拼装为最简 chat JSON
  --system <msg>    在 simple 模式下插入 system 消息；以 @ 开头时读取文件
  -j, --json        输出原始 JSON（默认用 jq 提取聊天内容）
  -d, --debug       打印调试信息，保留临时文件
  -h, --help        显示帮助
```

env 文件查找顺序（`$PROG` 为脚本名去掉 `.sh`，优先级从高到低）：
1. `--env` 指定的文件
2. `./$PROG.env`（`$PROG != ai-curl` 时再回退 `./ai-curl.env`）
3. `./.chatedit/$PROG.env`（同上回退）
4. `~/.chatedit/$PROG.env`（同上回退）

### perl/ai-chat.pl

```
用法: ai-chat.pl [选项] [input.md]
      ai-chat.pl [选项] < input.md

选项（API 连接）:
  --env <file>       指定 env 文件
  --url <url>        API URL
  --key <key>        API Key
  --model <model>    模型名
  --system [msg]     system 消息；以 @ 开头时读取文件；
                     空参数或不带参数时抑止自动查找
  -t, --template <file>  指定 JSON 模板文件

选项（行为）:
  -a, --append       将 AI 回复追加到输入 .md 文件（阶段二）；
                     STDIN 模式则先将原输入复制到 stdout 再接续追加回复
  --reformat 0|1     控制格式化输出（添加 ## role >> 标题行 + 修正标题等级）；
                     追加文件时默认开启，打印 stdout 时默认关闭
  -s, --simple       将整个输入当成简单 user 消息，跳过 Markdown 解析
  -j, --json         直接输出原始 API 响应 JSON，忽略 -a
  --stream           启用流式响应（SSE），实时打印到 stdout

选项（调试）:
  -d, --debug        打印调试信息到 stderr
  --postdir <dir>    将发送的请求 JSON 保存到指定目录
  --encode           只输出组装的 JSON（pretty），不发请求
  --decode           逆向：输入 API JSON，输出 markdown 对话段
  -h, --help             显示帮助
```

配置文件查找顺序，以 `env` 为例（`prog` 为脚本名去掉 `.pl`，优先级从高到低）：
- 命令行选项 --env
- 查找同程序名 ./prog.env ./.chatedit/prog.env ~/.chatedit/prog.env
- 查找通用名 ./ai-chat.env ./.chatedit/ai-chat.env ~/.chatedit/ai-chat.env

同理，未指定 --system 时自动查找 `prog.sys` 或 `ai-chat.sys` 文件，
未指定 `--template` 时自动查找 `prog.json` 或 `ai-chat.json` 文件。

可以用 `""` 或 `0` 选项值来抑制查找配置文件，只用程序默认值。

### python/ai-chat.py

与 `ai-chat.pl` 选项完全对应，直接替换调用即可：

```bash
python3 python/ai-chat.py -a chat.md
python3 python/ai-chat.py --stream -a chat.md
python3 python/ai-chat.py --encode chat.md | jq .
```

主要差异：
- 使用 `openai` SDK 发请求（无需 curl），需要预先安装：
  ```bash
  sudo apt install python3-openai   # Debian/Ubuntu，安装的版本为 1.12.0
  ```
- `API_URL` 支持完整路径（如 `https://api.xxx.com/v1/chat/completions`）或只写到 `/v1`，两种格式均可
- 不支持 Anthropic 原生格式响应（只支持 OpenAI 兼容格式）

## Markdown 聊天文件格式

详见 [docs/chat-format.md](docs/chat-format.md)，核心规则如下：

- `## role >>` 开启一个对话段，role 可为 `system`/`user`/`assistant`，或缩写 `P`/`Q`/`A`
- `# ` 开头为注释行（不转为 message）
- 不满足格式的 `##` 也视为注释段
- 三反引号代码块内的特殊标记被忽略
- 对话段内 `@path` 引入文件内容，`!cmd` 捕获命令输出

示例：

```markdown
# 这是注释，不会发送给模型

## system >> 请用中文简洁回答

## Q >> 1+1 等于几？

## A >> 2

## Q >> 不是小学数学，是陈景润研究的那个数论问题，请科普一下。
```

## 多轮对话工作流

```bash
# 初始问题
cat > chat.md <<'EOF'
## Q >> 请推荐三本关于算法的书籍。
EOF

# 第一轮发送（回复打印到终端 + 追加到文件）
perl/ai-chat.pl -a chat.md

# 在文件末尾追加新问题后再次发送
echo -e "\n## Q >> 其中哪本最适合初学者？" >> chat.md
perl/ai-chat.pl -a chat.md
```

## 管道联用示例

```bash
# 降级兼容：ai-chat.pl 组装 JSON，ai-curl.sh 发送
cat chat.md | perl/ai-chat.pl --encode | bash/ai-curl.sh

# 编解码互逆验证
cat chat.md | perl/ai-chat.pl --encode | perl/ai-chat.pl --decode

# 只看 json 组装结果（不发请求），可选管道至其他 json 工具进一步分析处理
perl/ai-chat.pl --encode chat.md | jq .
```

## 安装

将脚本复制到 `$PATH`（默认安装到 `~/bin`，仅在源文件比已安装版本新时才复制）：

```bash
make install                            # 安装三个脚本：ai-chat.pl、ai-curl.sh、ai-chat.py
make install INSTALL_DIR=/usr/local/bin # 指定目录
```

## Vim 插件

`vim/` 是一个 **git 子模块**，指向独立仓库 [lymslive/chatedit-vim](https://github.com/lymslive/chatedit-vim)。
克隆本仓库后需执行以下命令初始化子模块：

```bash
git submodule update --init
```

可安装到 Vim 8+ 的 native packages（二选一）：

```bash
mkdir -p ~/.vim/pack/chatedit/start
# 方式 A：软链接到已初始化的子模块目录
ln -s /path/to/chatedit/vim ~/.vim/pack/chatedit/start/chatedit
# 方式 B：直接单独克隆插件仓库
git clone git@github.com:lymslive/chatedit-vim.git ~/.vim/pack/chatedit/start/chatedit
```

安装后在 vim 中编辑聊天文件时可用以下命令（需要 `ai-chat.pl` 在 `$PATH`）：

| 命令 | 功能 |
|------|------|
| `:AI` | 调用 `ai-chat.pl`，将回复追加到文件末尾 |
| `:'<,'>AI` | 将选区作为聊天输入，回复插入选区下方 |
| `:AR` | 以 `--simple` 模式调用，回复替换当前文件内容 |
| `:'<,'>AR` | 以 `--simple` 模式调用，回复替换选区内容 |

插入模式缩写、normal 模式标题等级快捷键等 Vim 编辑功能，
详见 [vim/readme.md](vim/readme.md)。

## 目录结构

```
chatedit/
├── bash/
│   └── ai-curl.sh          # curl 封装脚本
├── bin/
│   └── ai-curl             # 软链接 → ../bash/ai-curl.sh
├── perl/
│   └── ai-chat.pl          # Markdown 聊天文件转换与 API 调用脚本（Perl）
├── python/
│   ├── ai-chat.py          # 与 ai-chat.pl 功能对等的 Python 实现
│   └── tests/              # Python 单元测试（unittest）
├── vim/                    # git 子模块 → github.com/lymslive/chatedit-vim
│   ├── plugin/
│   │   └── chatedit.vim    # Vim 插件主体（:AI / :AR 命令）
│   ├── autoload/
│   │   └── chatedit.vim    # 异步实现（Vim 8+ job API）
│   ├── ftplugin/
│   │   └── markdown.vim    # Markdown 文件类型插件（对话标题缩写）
│   └── doc/
│       └── chatedit.txt    # Vim 帮助文档
├── docs/
│   └── chat-format.md      # Markdown 聊天文件格式规范
├── testdata/
│   ├── ai-curl.env         # env 配置示例（填入真实 key 后可用）
│   ├── chat-simple.json    # 最简 API 请求 JSON 示例
│   ├── chat-system.json    # 带 system prompt 的请求 JSON 示例
│   ├── chat-hello.md       # 简单对话 Markdown 示例
│   └── chat-system.md      # 带 system 消息的多轮对话示例
├── Makefile                # test / install / help
├── ai-curl.env             # 本地 API 配置（不纳入版本控制）
└── readme.md
```

## 依赖

| 工具 | 说明 |
|------|------|
| `curl` | HTTP 请求（`ai-curl.sh` / `ai-chat.pl` 必须） |
| `jq` | JSON 输出格式化（可选，`ai-curl.sh` 未安装时降级输出原始 JSON） |
| `perl 5` + `JSON::PP` | Perl 5.14+ 自带，无需额外安装（`ai-chat.pl` 使用） |
| `envsubst` | 环境变量替换（`gettext` 包，`ai-curl.sh` 使用） |
| `python3` + `openai` SDK | `ai-chat.py` 使用；SDK 安装：`sudo apt install python3-openai` |

## 兼容的 API 格式

- **OpenAI 兼容格式**（kimi、deepseek 等）：`ai-chat.pl` 与 `ai-chat.py` 均支持
- **Anthropic 原生格式**：仅 `ai-chat.pl` 支持（响应提取 `.content[].text`）；Anthropic 也提供 OpenAI 兼容端点，`ai-chat.py` 可通过该端点使用

## 长期计划

| 状态 | 实现 |
|------|------|
| 已完成 | Bash curl 封装（`bash/ai-curl.sh`） |
| 已完成 | Perl 实现（`perl/ai-chat.pl`） |
| 已完成 | Vim 插件集成（`vim/` 子模块） |
| 已完成 | Python 实现（`python/ai-chat.py`） |
| 计划中 | Node.js 实现 |
| 计划中 | 编译型实现（C++ / Rust / Go） |
| 计划中 | Web 浏览器前端页面 |
