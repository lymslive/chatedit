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

两者可单独使用，也可管道联用：

```bash
cat chat.md | perl/ai-chat.pl --encode | bash/ai-curl.sh
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

### 3. Markdown 聊天文件（ai-chat.pl）

创建聊天文件 `chat.md`（格式见 [docs/chat-format.md](docs/chat-format.md)）：

```markdown
## Q >> 你好，请简单介绍你自己。
```

然后发送并将回复写回文件：

```bash
perl/ai-chat.pl -i chat.md
```

执行后 `chat.md` 末尾会自动追加：

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

选项（行为）:
  -i, --inplace      原位修改 .md 文件（隐含 --header）；
                     STDIN 模式则先输出原内容再追加响应
  --header           在响应前打印 ## role >> 标题行
  --encode           只输出组装的 JSON（pretty），不发请求
  --decode           逆向：输入 API JSON，输出 markdown 对话段

选项（调试）:
  -t, --template <file>  指定 JSON 模板文件
  -d, --debug            打印调试信息到 stderr
  -h, --help             显示帮助
```

文件查找顺序（`$PROG` 为脚本名去掉 `.pl`，优先级从高到低）：

**env 文件**：`--env` > `./$PROG.env`（回退 `./ai-chat.env`）> `./.chatedit/$PROG.env`（同上）> `~/.chatedit/$PROG.env`（同上）

**system 文件**（未指定 `--system` 时自动查找）：
`./$PROG.sys`（回退 `./ai-chat.sys`）> `./.chatedit/$PROG.sys`（同上）> `~/.chatedit/$PROG.sys`（同上）

**模板 JSON 文件**：
`--template` > `./$PROG.json`（回退 `./ai-chat.json`）> `./.chatedit/$PROG.json`（同上）> `~/.chatedit/$PROG.json`（同上）> 内联默认模板

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

# 第一轮发送
perl/ai-chat.pl -i chat.md

# 在文件末尾追加新问题后再次发送
echo -e "\n## Q >> 其中哪本最适合初学者？" >> chat.md
perl/ai-chat.pl -i chat.md
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

## 目录结构

```
chatedit/
├── bash/
│   └── ai-curl.sh          # curl 封装脚本
├── bin/
│   └── ai-curl             # 软链接 → ../bash/ai-curl.sh
├── perl/
│   └── ai-chat.pl          # Markdown 聊天文件转换与 API 调用脚本
├── docs/
│   └── chat-format.md      # Markdown 聊天文件格式规范
├── testdata/
│   ├── ai-curl.env         # env 配置示例（填入真实 key 后可用）
│   ├── chat-simple.json    # 最简 API 请求 JSON 示例
│   ├── chat-system.json    # 带 system prompt 的请求 JSON 示例
│   ├── chat-hello.md       # 简单对话 Markdown 示例
│   └── chat-system.md      # 带 system 消息的多轮对话示例
├── ai-curl.env             # 本地 API 配置（不纳入版本控制）
└── readme.md
```

## 依赖

| 工具 | 说明 |
|------|------|
| `curl` | HTTP 请求（必须） |
| `jq` | JSON 输出格式化（可选，`ai-curl.sh` 未安装时降级输出原始 JSON） |
| `perl 5` + `JSON::PP` | Perl 5.14+ 自带，无需额外安装 |
| `envsubst` | 环境变量替换（`gettext` 包，`ai-curl.sh` 使用） |

## 兼容的 API 格式

- **OpenAI 兼容格式**（kimi、deepseek 等）：响应提取 `.choices[].message.content`
- **Anthropic 原生格式**：响应提取 `.content[].text`

## 长期计划

| 状态 | 实现 |
|------|------|
| 已完成 | Bash curl 封装（`bash/ai-curl.sh`） |
| 进行中 | Perl 实现（`perl/ai-chat.pl`） |
| 计划中 | Vim 插件集成 |
| 计划中 | Python / Node.js 实现 |
| 计划中 | 编译型实现（C++ / Rust / Go） |
| 计划中 | Web 浏览器前端页面 |
