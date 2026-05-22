# Agent 工作日志

日志文件格式，每个二级标题开始一条日志。
由当前时间生成任务 ID，形如 `## TASK:yyyymmdd-hhmmss` ，
下行最好加一行等长的 `----------------------- 分隔线。

标注关键信息：
- 关联需求：需求 ID 形如 `TODO:yyyy-mm-dd/n`
- 执行工具：agent 工具名（所用 AI 模型名）

可选再概述一下核心需求目标。

然后本条工作日志正文可划分几个三级子标题，根据实际任务内容，比如可选如下章节：
- 实施步骤
- 变更总结
- 关键设计与权衡
- 测试验证
- 遗留未决任务

## TASK:20260509-121506
-----------------------

- 关联需求：TODO:2026-05-09/1
- 执行工具：Claude Code（claude-sonnet-4-6）

创建 `bash/ai-curl.sh` 脚本，封装 curl 调用 AI 模型 API，支持 env 文件配置、
环境变量替换、jq 输出提取，并在 `bin/` 建立软链接，`testdata/` 提供示例文件。

### 变更总结

新增文件：
- `bash/ai-curl.sh` — 主脚本
- `bin/ai-curl` — 软链接指向 `../bash/ai-curl.sh`
- `testdata/ai-curl.env` — env 配置示例
- `testdata/chat-simple.json` — 最简对话请求示例
- `testdata/chat-system.json` — 带 system prompt 的请求示例
- `testdata/chat-claude.json` — Anthropic 原生格式请求示例

### 关键设计与权衡

**命令行选项优先级**：解析阶段存入 `OPT_*` 中间变量，`source` env 文件后再用
`OPT_*` 覆盖 `API_*`，两步分离，逻辑清晰。

**变量导出**：`source` 加载的变量默认不导出，`envsubst` 作为子进程无法读取。
修复方法是在变量确定后显式 `export API_URL API_KEY API_MODEL`。

**JSON 传输**：使用 `curl -d @file` 直接传文件，避免 shell 变量展开引起的引号
问题，大文件同样安全。

**envsubst 安全替换**：`envsubst '$API_URL $API_KEY $API_MODEL'`（单引号）只替
换指定的三个变量，JSON 中其他 `$` 字符（如 `$ref`）不受影响。用 `grep` 先检测
是否含占位符，无则跳过，不产生多余临时文件。

**STDIN 与响应均用临时文件**：curl 响应可能很大，不适合放变量；STDIN 输入也先
写临时文件再用 `@file`。所有临时文件统一用 `TMP_FILES` 数组管理，`trap cleanup
EXIT` 确保清理。

**jq 输出兼容两种格式**：
- OpenAI 兼容格式（kimi、deepseek 等）：`.choices[].message.content`
- Anthropic 原生格式：`.content[].text`

**依赖检查**：启动时检查 `curl`（必须）和 `jq`（可选），`jq` 未安装时自动降级
为输出原始 JSON。

### 测试验证

使用项目根目录 `ai-curl.env`（配置 kimi API）实测：
- `bin/ai-curl testdata/chat-simple.json` — 正常输出 `assistant: ...`
- `bin/ai-curl --json testdata/chat-simple.json` — 输出原始 JSON 可管道处理
- `bin/ai-curl -d testdata/chat-simple.json` — debug 输出定位到 envsubst 变量
  未导出的 bug，修复后验证通过

### 遗留未决任务

- JSON 示例文件中 `model` 写死为 `$API_MODEL`，Anthropic 原生格式（`chat-claude.json`）
  实际未测试，需配置对应 API_URL 后验证。

## TASK:20260509-160151
-----------------------

- 关联需求：TODO:2026-05-09/2
- 执行工具：Claude Code（claude-sonnet-4-6）

为 `bash/ai-curl.sh` 增加 `--simple|-s` 和 `--system` 两个选项，支持将纯文本
直接作为聊天输入，无需手写 JSON，实现单轮快捷聊天。

### 变更总结

修改文件：
- `bash/ai-curl.sh` — 新增约 80 行，包括选项解析、`json_escape` 函数、simple 模式 JSON 拼装逻辑

新增功能：
- `--simple` / `-s`：将 STDIN 或位置参数文件视为纯文本，自动拼装为最简 chat JSON；
  若文件名以 `.json` 结尾则自动忽略，沿用原有行为。
- `--system <msg>`：在 simple 模式下于 messages 数组头部插入 system 消息；
  值以 `@` 开头时读取对应文件内容，否则直接使用字符串。

### 关键设计与权衡

**JSON 转义方案**：纯 `sed` + `awk`，无额外依赖：
- `sed` 处理三类字符：`\` → `\\`，`"` → `\"`，制表符 → `\t`
- `awk` 负责多行拼接，行间插入字面 `\n`，最终输出单行 JSON 字符串值

**转义顺序**：先转义 `\`（避免后续替换引入的 `\` 被二次转义），再转义 `"`。

**临时文件链路**：STDIN → `TMP_STDIN` → `json_escape` → `TMP_SIMPLE`（含 `$API_MODEL` 占位符）
→ `envsubst` → `TMP_SUBST` → curl，每步均纳入 `TMP_FILES` 统一清理。

**`.json` 后缀判断**：在读取文件之前判断（位置参数已知时），避免对合法 JSON 文件做不必要的文本转义。

**`--system` 作用域限制**：system 选项仅在 simple 模式下有意义，其他模式给出警告提示，不报错退出。

### 测试验证

以下命令在本地做了逻辑验证（未实际调用 API）：

```bash
# 普通文本
echo 'Hello, who are you?' | json_escape   # → Hello, who are you?

# 含引号
echo 'Say "hello"' | json_escape           # → Say \"hello\"

# 多行
printf 'line1\nline2\nline3' | json_escape # → line1\nline2\nline3

# 含反斜杠
echo 'path\to\file' | json_escape          # → path\\to\\file

# 拼装带 system 的 JSON 格式正确，model 字段含 $API_MODEL 占位符待 envsubst 替换
```

### 遗留未决任务

- 未对真实 API 端到端测试（需有效的 `ai-curl.env` 配置）。
- 尚未处理 `\r`（Windows 回车）的转义，如有跨平台需求可补充
  `sed 's/\r/\\r/g'` 一步。

## TASK:20260511-165415
-----------------------

- 关联需求：TODO:2026-05-11/1
- 执行工具：Claude Code（claude-sonnet-4-6）

新建 `perl/ai-chat.pl` 脚本，将遵循 `docs/chat-format.md` 规范的 markdown 聊天
文件解析转换为 AI API 的 JSON 请求体，可与 `bash/ai-curl.sh` 联用。

### 实施步骤

1. 阅读 `docs/chat-format.md`、`testdata/*.json` 及 `bash/ai-curl.sh` 了解现有格式与架构
2. 新建 `perl/ai-chat.pl` 脚本
3. 在 `testdata/` 中新增两个 `.md` 示例文件：`chat-hello.md`、`chat-system.md`

### 变更总结

新增文件：
- `perl/ai-chat.pl` — 约 200 行，含 POD 内嵌文档
- `testdata/chat-hello.md` — 简单问答示例
- `testdata/chat-system.md` — 带系统提示词的多轮对话示例

### 关键设计与权衡

**JSON 处理**：使用 Perl 5 核心模块 `JSON::PP`（v5.14+ 自带），避免第三方依赖。
模板中 `$API_MODEL` 等占位符是合法 JSON 字符串，`JSON::PP` 可正常解析；
输出时使用 `->pretty->canonical(0)` 保持可读性，key 顺序跟随 Perl hash（不强排序）。

**模板查找**：按优先级依次尝试 `--template` 选项、`./ai-chat.json`、`./.chatedit/ai-chat.json`、
`~/.chatedit/ai-chat.json`，均未找到则使用内联最小模板 `{"model":"$API_MODEL","messages":[]}`。
模板的 `messages` 字段（无论原值）总被解析内容替换。

**Markdown 解析**：
- 以行为单位扫描，用 `$in_code` 标志跟踪三反引号代码块，块内忽略所有特殊标记
- `## role >>` 匹配（大小写不敏感）开启新对话段，同时 flush 上一段
- `#` 开头（一级标题/注释）及不满足格式的 `##` 结束当前段
- `###` 及更深层标题在对话段内保留为内容
- `@file` / `!cmd` 在对话段内就地展开（注释段内展开暂未实现）
- 最终 content 去掉尾部空行，行间以 `\n` 连接

### 测试验证

```bash
# 基本功能
perl perl/ai-chat.pl testdata/chat-hello.md
# → 4 条 message，role/content 正确

# 带模板
perl perl/ai-chat.pl -t testdata/chat-system.json testdata/chat-system.md
# → 保留 temperature/max_tokens 字段，messages 被替换

# STDIN 输入 + 文档示例验证
perl perl/ai-chat.pl < (docs example heredoc)
# → 与 docs/chat-format.md 中期望 JSON 完全吻合

# 代码块内特殊标记忽略
perl perl/ai-chat.pl  (含 ``` 块的 heredoc)
# → 块内 ## role >> 不触发新段，保留为内容

# 调试模式
perl perl/ai-chat.pl -d testdata/chat-hello.md
# → stderr 打印模板来源、message 数量及每条 content_len
```

### 遗留未决任务

- 注释段（`# `）下的 `@file` / `!cmd` 展开后递归解析多段对话的功能尚未实现
- 尚未针对真实 API 端到端测试（需有效的 `ai-curl.env`）

## TASK:20260511-215428
-----------------------

- 关联需求：TODO:2026-05-11/2
- 执行工具：Claude Code（claude-sonnet-4-6）

优化 `perl/ai-chat.pl` 的外部引入规则与错误处理，同时修复 `###` 子标题处理 bug。

### 实施步骤

1. 阅读 `task_todo.md` 需求、`perl/ai-chat.pl` 源码、`docs/chat-format.md`
2. 修复 `###` 子标题 bug：`^##[^#]` 精确匹配二级标题，不再匹配 `###`
3. 改造 `read_file_lines` / `run_command` 返回 `($ok, @lines)` 格式
4. 在 `parse_chat` 调用处增加错误标记逻辑：失败加 `(Read Error)`，空输出加 `(Read Empty)`
5. 移除旧注释（"注释段内 `@` 可展开"），更新 POD 文档
6. 功能验证通过

### 变更总结

修改文件：
- `perl/ai-chat.pl` — 修复 `###` bug、增加错误处理、更新注释与 POD 文档

提交文件：
- `perl/ai-chat.pl` — 主要变更
- `docs/chat-format.md` — 上次任务漏提交，随本次补交

### 关键设计与权衡

**`###` bug 修复**：原 `^##` 正则会匹配 `###`，导致对话段内 `###` 子标题提前结束当前段。
改为 `^##[^#]` 或 `^##$` 精确匹配恰好两个 `#` 开头的行。

**错误处理设计**：`read_file_lines` 和 `run_command` 改为返回列表首元素 `$ok`（0/1）。
调用处统一处理三种情况：失败、空输出、正常输出。
"空输出"用 `grep { /\S/ }` 判断，全空白行也视为空。

**`@`/`!` 限制范围**：需求要求只在 `## role >>` 段内有效，当前代码本来就在 `if ($cur_role)` 块内，
只是旧注释错误说明"注释段内也可展开"，本次清除该错误注释。

### 测试验证

```
# ### 子标题保留在对话段内
echo '## Q >> 你好\n### 子标题\n继续' | perl ai-chat.pl
→ content 包含全部三行

# @ 文件不存在 → (Read Error)
@/nonexistent/file.txt → "@/nonexistent/file.txt (Read Error)"

# ! 命令失败 → (Read Error)
! exit 1 → "! exit 1 (Read Error)"

# ! 空输出 → (Read Empty)
! echo "" → "! echo \"\" (Read Empty)"

# ! 正常输出 → 内容行
! echo "有输出" → "有输出"
```

### COMMIT: cd37422e892155d392b0fe3b03161655610c84bf

## TASK:20260512-122319
-----------------------

- 关联需求：TODO:2026-05-11/1
- 执行工具：Claude Code（claude-sonnet-4-6）

### 任务需求

扩展 `perl/ai-chat.pl`，将 `bash/ai-curl.sh` 的 API 调用能力集成进来，实现：
- 直接读 `.md` 文件 → 组装 JSON → 调用 API → 写回文件（多轮对话）
- 支持 `-i`（原位修改）、`--header`、`--encode`（降级兼容）、`--decode`（逆向解码）
- 支持 `--env/--url/--key/--model` 连接参数，`--system` 及自动 `ai-chat.sys` 查找
- 错误处理：API 响应含 error 字段时打印原始 JSON 到 stderr

### 实施步骤

1. 阅读 `perl/ai-chat.pl`、`bash/ai-curl.sh`、`ai-curl.env`、测试数据
2. 评估 HTTP 请求技术方案，写入 `doing_plan.tmp/http-alternatives.md`，选定 curl 调用
3. 全量重写 `perl/ai-chat.pl`，新增：
   - `load_env` / `find_env_file` — env 文件加载与命令行优先级覆盖
   - `open_input` — 支持文件与 STDIN（临时文件缓冲，解决宽字符 in-memory filehandle 问题）
   - `inject_system` / `find_system_file` — system 消息自动注入
   - `call_api` — 列表形式 open curl，避免 shell 注入，原始字节读取响应
   - `parse_response` — 兼容 OpenAI 格式 `.choices[]` 与 Anthropic 格式 `.content[]`
   - `print_response` / `append_to_file` — 带/不带 `--header` 的输出逻辑
   - `decode_to_md` — `--decode` 逆向操作
   - `decode_to_md` 及 `open_file_or_stdin` 以原始字节读取，供 JSON::PP->utf8->decode
4. 调试 UTF-8 编码问题：统一在 `parse_response` 用 `->utf8->decode`，输出用 `>>:utf8`
5. 测试验证（见下）

### 关键设计

**curl 调用**：用 `open my $fh, '-|', 'curl', ...` 列表形式，不经 shell，API key 安全
**UTF-8 处理**：curl 响应以原始字节读取 → `JSON::PP->utf8->decode` → Perl 字符串 → `:utf8` 写文件
**STDIN 缓冲**：写临时文件而非 in-memory string filehandle，避免宽字符层问题
**`$API_MODEL` 替换**：模板 model 字段中 `$API_MODEL` 在 Perl 内替换，无需 envsubst

### 测试验证

```bash
# --encode 兼容原有管道
cat testdata/chat-hello.md | perl/ai-chat.pl --encode
→ 输出正确 JSON，model=kimi-k2.5，messages 中文正常

# --encode | --decode 互逆
cat testdata/chat-hello.md | perl/ai-chat.pl --encode | perl/ai-chat.pl --decode
→ 输出 ## user >> / ## assistant >> 对话段，内容还原正确

# 直接 API 调用（--header）
echo "## Q >>\n\n请介绍自己" | perl/ai-chat.pl --header
→ 输出 ## assistant >> 标题 + AI 回复

# -i 原位修改
perl/ai-chat.pl -i /tmp/test-inplace.md
→ 末尾追加 ## assistant >> 及 AI 回复，UTF-8 正确

# --encode | bash/ai-curl.sh 管道兼容
echo "## Q >> 1+1" | perl/ai-chat.pl --encode | bash/ai-curl.sh
→ assistant: 2

# --system 指定 / 抑止
perl/ai-chat.pl --system "只用中文回答" --header ...   → 正常插入 system
perl/ai-chat.pl --encode --system "" ...               → messages 不含 system
```

### 变更总结

修改文件：
- `perl/ai-chat.pl` — 全量扩展，保留原有 parse_chat / load_template 逻辑

新增文件：
- `doing_plan.tmp/http-alternatives.md` — HTTP 请求方案评估文档

### COMMIT: cc2396e1080cd304168743651c2494b532f63849

## TASK:20260512-183920
-----------------------

**需求**: TODO:2026-05-12/3 模型回复中文时偶发乱码分析与修复

### 根因分析

`call_api()` 函数（`perl/ai-chat.pl` 第 277 行）对写临时 JSON 文件的句柄设置了
`:utf8` 层，但 `$request_json` 变量已经是 `JSON::PP->new->utf8->encode` 输出的
UTF-8 字节串（Perl 内部无 utf8 flag）。将字节串写入 `:utf8` 句柄会触发双重编码：
汉字 3 字节变 6 字节，curl 发送乱码给 API，返回结果也乱。

- `testdata/chat-system.md` 正常：模板及该文件内容均为 ASCII，双重编码不影响单字节字符
- `--encode | bash/ai-curl.sh` 正常：`--encode` 写默认 STDOUT（无 `:utf8` 层），字节原样输出

### 修复

将 `call_api()` 中 `binmode $tmp_fh, ':utf8'` 改为 `binmode $tmp_fh, ':raw'`，一行改动。

### 关于"去掉 utf8 模式只当字节流"的疑问

真正纯字节方案行不通：若输入以 `:raw` 读取，Perl 字符串无 utf8 flag，
`JSON::PP->utf8->encode` 会把每个字节当 Latin-1 码点重新 UTF-8 编码，汉字反而乱。

正确的做法是在 IO 边界保持一致：
- 输入 `:utf8` 读 → Perl 内部字符串
- `JSON::PP->utf8->encode` → UTF-8 字节串
- 写文件/curl 用 `:raw`（这是修复的关键）
- API 返回字节 → `JSON::PP->utf8->decode` → Perl 字符串
- 打印终端 `:utf8`

性能上 UTF-8 编解码对话文本可忽略不计。

### 变更文件

- `perl/ai-chat.pl` — `call_api()` 一行 bugfix

### COMMIT: 209897dcd0aab8da93c7b75525f56cfaf9946622

## TASK:20260513-122409
-----------------------

**需求**: 2026-05-13/1 — 为 perl/ai-chat.pl 完善单元测试

### 分析

`ai-chat.pl` 是单文件 Perl 脚本，所有逻辑写在 `main::` 包中。
Perl 社区规范单元测试使用 `t/` 目录 + `.t` 文件 + `Test::More`，用 `prove` 运行。
测试脚本通过 `require` 加载被测文件，前提是主执行代码被 `unless (caller)` 保护，
`our` 变量让测试可直接读写 package 全局选项，`*main::call_api` 符号表替换实现 mock。

### 实现

**`perl/ai-chat.pl` 修改（3处）**

1. 全局选项变量 `my $opt_*` 改为 `our $opt_*`，使测试可直接设置选项状态。
2. 提取主流程为 `sub run()`，`unless (caller)` 块仅一行 `run()`，代码结构更清晰。
3. `parse_chat` 的 flush 闭包追加 `$content =~ s/^\n+//`，去掉段首空行，
   解决 `decode_to_md` 标题后空行在反复迭代中累积的问题，确保 encode→decode 幂等。

**测试文件 `perl/t/`（6个）**

| 文件 | 覆盖范围 |
|------|----------|
| `01-normalize-role.t` | `normalize_role`：缩写/大小写规范化 |
| `02-parse-chat.t` | `parse_chat`：基本角色、注释、代码块、`@file`、`!cmd`、空行处理 |
| `03-parse-response.t` | `parse_response`：OpenAI 格式、Anthropic 格式、错误/空/Unicode |
| `04-decode-to-md.t` | `decode_to_md`：JSON → Markdown 输出内容与顺序 |
| `05-mock-api.t` | 完整流程 mock：`call_api` 符号表替换，覆盖 OpenAI/Anthropic/error/Unicode |
| `06-encode-decode-roundtrip.t` | subprocess 集成测试：`--encode`/`--decode` 功能及 2 轮迭代幂等性 |

共 95 个测试全部通过（`prove perl/t/`）。

### mock API 方案说明

无需安装额外 CPAN 模块，仅用 Perl 内置机制：
```perl
{
    no warnings 'redefine';
    local *main::call_api = sub { return $canned_json_response };
    # 在此作用域内 call_api 返回预设响应
}
```
`local` 确保作用域结束自动恢复原函数，互不干扰。

### 运行测试

```bash
prove perl/t/          # 运行所有测试
prove perl/t/02-parse-chat.t   # 运行单个测试文件
```

### 变更文件

- `perl/ai-chat.pl` — our 变量、sub run()、parse_chat 首部空行修复
- `perl/t/01-normalize-role.t`（新增）
- `perl/t/02-parse-chat.t`（新增）
- `perl/t/03-parse-response.t`（新增）
- `perl/t/04-decode-to-md.t`（新增）
- `perl/t/05-mock-api.t`（新增）
- `perl/t/06-encode-decode-roundtrip.t`（新增）

### COMMIT: 4d3864dac66c2a716a6c4290beb33886b3e13130

## TASK:20260513-145043
-----------------------

**需求**: 2026-05-13/2 — 自动查找辅助配置文件功能优化

### 分析

两个脚本中配置文件查找逻辑当前使用固定文件名，要改为随脚本名（`$0`）变化，
并保留通用名（`ai-chat.env` / `ai-curl.env`）的回退兼容查找。

`ai-chat.pl` 原来查的是 `ai-curl.env`，按需求同步纠正为先查 `ai-chat.env`。

### 实现

**`perl/ai-chat.pl`**

- 新增 `use File::Basename qw(basename)` 及模块级变量 `$prog_name = basename($0, '.pl')`
- 更新 `find_env_file`：candidates 从 `$opt_env` 开始，再对每个搜索目录依次加 `$prog_name.env` 和回退 `ai-chat.env`（仅当 `$prog_name ne 'ai-chat'` 时）
- 同样模式更新 `find_system_file`（`.sys` 文件）
- 同样模式更新 `find_template_file`（`.json` 文件）
- 更新 usage 文档注明 `$PROG` 搜索规则

**`bash/ai-curl.sh`**

- 新增 `PROG="$(basename "$0" .sh)"` 取脚本名
- 更新 `find_env_file`：对三个搜索目录依次加 `$PROG.env` 和回退 `ai-curl.env`（仅当 `$PROG != "ai-curl"`）

### 软链接效果示例

```bash
ln -s /path/to/ai-chat.pl ~/bin/kimi-chat
kimi-chat -i chat.md
# 依次查找: ./kimi-chat.env, ./.chatedit/kimi-chat.env, ~/.chatedit/kimi-chat.env
# 再回退:  ./ai-chat.env, ./.chatedit/ai-chat.env, ~/.chatedit/ai-chat.env
```

### 测试验证

`prove perl/t/` — 全部 95 个测试通过，无回归。

### COMMIT: 3793274c754643a5f999ddea9502f7066377fea5

## TASK:20260513-154929
-----------------------

**需求**: 2026-05-13/3 — ai-chat.pl 功能扩展 -j -s --postdir

### 实现

**`perl/ai-chat.pl`**

- 将 `my $prog_name` 改为 `our $prog_name`，供单元测试文件直接覆盖
- 新增三个选项变量及 `GetOptions` 注册：
  - `$opt_simple` / `-s/--simple`：整个输入当成简单 user 消息，跳过 Markdown 解析
  - `$opt_json` / `-j/--json`：直接输出原始 API 响应 JSON，忽略 `-i`
  - `$opt_postdir` / `--postdir <dir>`：将请求 JSON 保存到指定目录，命名格式 `prog-yyyymmdd-hhmmss.json`
- 在 `run()` 中：`--simple` 时 slurp 整个文件内容为单条 `user` 消息；`--json` 时在 `call_api` 后直接打印原始响应并退出
- 提取 `save_to_postdir($dir, $json)` 辅助函数（便于单元测试），目录不存在时打印告警
- 更新 `usage()` 说明与 POD 文档

### 新增测试

**`perl/t/07-new-options.t`**

- `--simple --encode`：验证纯文本输入成为单条 `user` 消息（包含中文内容、忽略 Markdown 标记）
- `save_to_postdir`：验证文件在目录中按时间戳命名创建，内容正确；目录不存在时打印告警
- `--json`：mock `call_api`，验证原始 JSON 被直接输出

**`perl/t/08-find-env.t`**

- 覆盖 `find_env_file` 的各种查找路径：`--env` 显式路径、CWD `prog_name.env`、`.chatedit/prog_name.env`、`ai-chat.env` 回退、无文件时返回 undef
- 覆盖 `load_env` 基本解析（KEY=value、注释行、空行）
- 使用 `testdata/` 中的实际测试文件验证

**testdata 新增文件**

- `testdata/test-prog.env` — 用于 CWD 同名查找测试
- `testdata/.chatedit/test-chatedit.env` — 用于 .chatedit 子目录查找测试
- `testdata/ai-chat.env` — 用于 ai-chat.env 回退查找测试

### 测试验证

`prove perl/t/` — 全部 127 个测试通过（新增 32 个），无回归。

### COMMIT: d995479f4b948e7401210adfbe45b009adb7e253

## TASK:20260514-121333
-----------------------

**需求**: 2026-05-14/1 — ai-chat.pl 支持流式响应与解析

### 实现

**`perl/ai-chat.pl`**

- 新增全局选项 `$opt_stream` / `--stream`：启用流式 SSE 响应
- 在 `run()` 中，build template 后检测流式：`$opt_stream` 或模板中已含 `"stream":true` 均触发
  - 检测为流式时自动将 `$template->{stream} = JSON::PP::true` 写入请求 JSON
  - `--encode` 模式下照常输出（含 stream:true），方便调试
- 新增流式响应分支（`$is_stream` 时进入）：
  - `$| = 1` autoflush，保证 delta 实时输出
  - 若 `--header`（含 `-i` 隐含时）先打印 `## assistant >>` 再流式输出
  - STDIN + `-i` 模式：先复制缓冲的原始输入到 stdout，再流式输出响应
  - 流式结束后，若 `-i` + 有输入文件，还将完整响应追加到文件
  - 若 `--json`，直接转发原始 SSE 行到 stdout

- 新增 `call_api_stream($json, $url, $key)` 子函数：
  - 与 `call_api` 相同的 curl 调用方式（临时文件、列表形式防注入）
  - 按行读取响应，`$opt_json` 时转发原始行；否则解析 `data:` SSE 行
  - 跳过 `[DONE]` 与解析失败的 chunk
  - 返回 `($role, $accumulated_content)` 或 `(undef, undef)`（`--json` 模式）

- 新增 `_extract_stream_delta($chunk, \$role)` 辅助函数：
  - OpenAI/兼容格式：`choices[].delta.content`，首 chunk 更新 role
  - Anthropic 原生格式：`type=content_block_delta` + `delta.type=text_delta` 提取 text
  - Anthropic `type=message_start` 更新 role；其他 chunk 类型返回空串

- 更新 `usage()` 与 POD 文档，添加 `--stream` 选项说明

**`CLAUDE.md`**

- Running the Tools 节添加 `--stream` 示例
- 架构流程更新：步骤 8 分流式/非流式路径说明
- 测试文件表补充 07/08/09

### 新增测试

**`perl/t/09-stream.t`** — 15 个测试

- `_extract_stream_delta`：OpenAI 单词/空/中文/role 更新、Anthropic content_block_delta/message_start/ping、未知类型
- `--stream --encode`：subprocess 验证输出 JSON 中 `stream` 字段为 true
- 模板含 `stream:true`：subprocess 验证自动检测，无需 `--stream` 选项

### 测试验证

`prove perl/t/` — 全部 142 个测试通过（新增 15 个），无回归。

### COMMIT: 529bfe56008e51a69e0b5d9ba94d2f311dfb827f

## TASK:20260516-102547
-----------------------

**需求**: 2026-05-16/1 — 新增 `--fix-level` 选项修正 AI 回复标题等级

### 实现

**`perl/ai-chat.pl`**

- 新增全局选项 `$opt_fix_level = undef`（undef 为自动模式）/ `--fix-level 0|1`
- 新增 `fix_heading_level($content)` 纯文本变换函数（不检查全局，由调用方决定是否调用）：
  - `h1`（`# text`）→ `h3`（`### text`）：将开头单个 `#` 替换为 `###`
  - `h2+`（`## text` 及以上）→ 各加一级：前置一个 `#`
  - 无空格的 `#标签` 不受影响（仅匹配 `^(#+) ` 模式）
- 调用方差异化默认值：
  - `append_to_file`（写回文件）：默认 `$opt_fix_level // 1`，即未指定时自动修正
  - `print_response`（标准输出）：默认 `$opt_fix_level // 0`，即未指定时不修正
  - 显式 `--fix-level 0/1` 同时覆盖两处行为
- 更新 `usage()` 与 POD 文档，添加 `--fix-level` 选项说明

**`perl/t/09-stream.t`**（顺带修复）

- 删除 lines 91-101 的残留 `do{}` 块：该块用 `open '-|'` 生成子进程并继承测试进程
  的真实 STDIN，导致 `prove` 运行时子进程阻塞等待终端输入，整个测试文件卡死。
  该块本为废弃代码（结尾为 `undef`），实际测试已改由下方 `open2` 完成。

### 新增测试

**`perl/t/10-fix-level.t`** — 19 个测试

- `fix_heading_level` 直接单元测试：h1→h3、h2→h3、h3→h4、h4→h5、无空格不变、普通行不变、多行混合
- `append_to_file`：undef(默认修正) / 显式 0(不修正) / 显式 1(修正)
- `print_response`：undef(默认不修正) / 显式 1(修正) / 显式 0(不修正)

### 测试验证

`prove perl/t/` — 全部 161 个测试通过（新增 19 个），无回归。

### COMMIT: c8f106ec0272a25efe032432a0db06aa23c5567c

## TASK:20260516-154114
-----------------------
- 关联需求：TODO:2026-05-16/2
- 执行工具：claude-code (claude-sonnet-4-6)

重构 `ai-chat.pl` 交互逻辑：两阶段输出、选项合并重命名、拆分流式/非流式子函数、stderr 摘要。

### 变更总结

**`perl/ai-chat.pl`** — 主要重构

选项重命名与合并：
- `--inplace/-i` → `--append/-a`（语义更准确，只会追加文件末尾）
- `--header` + `--fix-level` 合并为 `--reformat 0|1`（undef=自动）
  - 写文件时默认 1（开启：添加 `## role >>` 标题行 + 修正标题等级）
  - 打印 stdout 时默认 0（关闭）
  - 显式指定时对所有输出路径生效

两阶段输出：
- 阶段一：始终打印 AI 回复到 stdout（不管是否有 `-a`）
- 阶段二：`-a` + 实际文件时追加到文件，并向 stderr 输出摘要行：
  `# <!-- N lines appended to file: path; reformated lines: N -->`
- stdin + `-a` 特殊处理：stdout 充当"虚拟文件"，网络请求前先复制原 stdin 到 stdout；
  阶段一与阶段二合并，按文件模式格式化输出（两阶段合并为一）

主流程拆分：
- 新增 `run_stream()` — 流式路径（含两阶段输出逻辑）
- 新增 `run_non_stream()` — 非流式路径（含两阶段输出逻辑）
- `run()` 负责准备工作后分发至两者，避免重复代码

`fix_heading_level` 升级：
- 列表上下文返回 `($new_content, $reformed_count)`，便于 `append_to_file` 统计

`append_to_file` 升级：
- 返回 `($lines_appended, $reformed_count)` 供调用方打印 stderr 摘要

**`perl/t/10-fix-level.t`** — 重写测试

- 更新所有 `$main::opt_fix_level` → `$main::opt_reformat`
- 删除 `$main::opt_header`（已并入 `--reformat`）
- 补充 `fix_heading_level` 列表上下文测试（count 返回值）
- 补充 `print_response` 的 `$for_file` 参数测试（新增 for_file=1 场景）
- 补充 `append_to_file` 返回值（lines/reformed 计数）测试

**`perl/t/07-simple-json-postdir.t`** — 小更新

- `$main::opt_inplace` → `$main::opt_append`
- `$main::opt_header` → `$main::opt_reformat = undef`

**`AGENTS.md`** — 文档同步

- 更新示例命令（`-i` → `-a`，`--fix-level` → `--reformat`，新增 stdin+`-a` 示例）
- 更新架构说明，描述两阶段输出与 `run_stream`/`run_non_stream` 拆分
- 更新测试文件表格描述

### 测试验证

`prove perl/t/` — 全部 176 个测试通过，无回归。

### COMMIT: e1aac485aed0c77cf5387ed5268f8e1240501351

## TASK:20260516-180109
-----------------------

- 关联需求：TODO:2026-05-16/3 — ai-chat.pl 代码风格重构优化
- 执行工具：claude-code (claude-sonnet-4-6)

### 变更内容

**`perl/ai-chat.pl`** — 综合重构

- **Allman 大括号风格**：所有 `sub` 函数的开大括号改为独立新行，支持 vim `[[`/`]]` 跳转
- **`open_stdin` / `open_input` 拆分**：抽出 `open_stdin` 处理 stdin 特殊逻辑（单循环同时写临时文件与 stdout），`open_input` 只返回单一文件句柄；`--encode` 时先抑止 `$opt_append`
- **`find_config_file` 统一**：将 `find_env_file`/`find_system_file`/`find_template_file` 的共同搜索逻辑提取为 `find_config_file($suffix, $opt_val)`；三个函数保留为薄封装
- **选项默认值 `undef` 化**：`$opt_env`/`$opt_template`/`$opt_system` 默认改为 `undef`（表示自动搜索），移除 `$opt_system_given`；`inject_system` 改用 `defined $opt_system` 判断
- **`prepare_request_file`**：新函数，优先保存到 `--postdir`，失败时才创建临时文件，返回 `($file, $is_temp)`；`call_api`/`call_api_stream` 参数改为接收文件路径而非 JSON 字符串；临时文件清理移到 `run()` 统一处理
- **curl 调试日志前移**：`[debug] curl: POST` 日志从 `call_api` 移至 `run()` 中分发前，流式与非流式路径共用
- **精简注释**：删除显而易见或与代码重复的内联注释

**`perl/CLAUDE.md`** — 新增 Perl 代码风格文件

- 记录 Allman 大括号风格要求及 vim 跳转原理
- 记录 `our` 全局变量、选项默认值 `undef` 语义、mock 方式等约定

**`perl/t/05-mock-api.t`、`perl/t/07-simple-json-postdir.t`** — 移除 `$opt_system_given`

**`perl/t/08-find-env.t`** — `$opt_env = ''` 全改为 `undef`（与新默认值语义一致）

### 测试验证

`prove perl/t/` — 全部 176 个测试通过，无回归。

### COMMIT: d94b4ea98b411d09b736df7e6a3eb15a809c5bdb

## TASK:20260518-151541
-----------------------

- 关联需求：TODO:2026-05-18/1 — ai-chat.pl 查找配置文件及读取全文件优化
- 执行工具：claude-code (claude-sonnet-4-6)

### 变更内容

**`perl/ai-chat.pl`** — 配置文件查找逻辑重构 + 工具函数提取

**`find_config_file` 修正**：
- 参数由 `($suffix, $opt_val)` 改为仅 `($suffix)`，调用方负责在有命令行选项时跳过此函数
- 修正搜索顺序：先遍历 `prog_name` 的全部目录（`./` → `.chatedit/` → `~/.chatedit/`），
  再遍历 ai-chat 回退名的全部目录，消除了旧代码中目录与名称交叉的排序问题
- 找到文件时打印 `[debug]` 调试信息

**`load_env` 重构**：
- `$opt_env` 有值时直接处理，不再调用 `find_env_file()`
  - 空串或 `0` → 抑止查找，`[debug]` 提示
  - 文件不存在 → `warn` 警告
  - 文件存在 → 加载
- `$opt_env = undef` 时才调用 `find_env_file()` 自动搜索

**`load_template` 同步重构**：
- `$opt_template` 有值时直接处理（同 `load_env` 逻辑），不再传入 `find_config_file`
- 改用 `read_file_content()` 读取模板文件

**`inject_system` 改进**：
- `$opt_system` 为 `'0'`（同空串）时抑止 system 注入
- 改用 `read_file_content()` 读取 sys 文件（替代内联 `local $/; <$fh>; chomp`）

**新增 `read_file_content($file)`**：
- 统一封装读取整个文件的逻辑，去除首尾空白后返回字符串
- 供 `inject_system`、`load_template` 调用，消除重复模式

**`decode_to_md` 合并简化**：
- 合并原 `open_file_or_stdin` 逻辑：直接在函数内处理 `@ARGV` 或 STDIN
- 函数改为无参数调用，`run()` 中只需 `decode_to_md(); exit 0`
- 删除 `open_file_or_stdin` 独立函数

**`--decode` 提前**：
- 在 `run()` 中将 `--decode` 分支移至 `load_env()` 之前，decode 模式不需加载 env

**薄封装更新**：
- `find_env_file`/`find_system_file`/`find_template_file` 改为单纯调用 `find_config_file($suffix)`

---

**`perl/t/08-find-env.t` → `perl/t/08-find-config.t`**（重命名并重写）：
- 新增 `load_env` 选项行为测试：显式文件加载、文件不存在警告、空串抑止
- 修正 test-12：新搜索顺序下 `.chatedit/test-chatedit.env` 优先于 `./ai-chat.env`
- 新增 `find_system_file` 与 `find_template_file` 的基本搜索测试

**`perl/t/10-fix-level.t` → `perl/t/10-reformat.t`**（重命名，内容不变）

**`perl/t/04-decode-to-md.t`**：
- `capture_decode` 改为重定向 STDIN（而非传 filehandle 参数），适配新 `decode_to_md()` 接口

**`CLAUDE.md`**：更新测试文件表格（文件名与描述）

### 测试验证

`prove perl/t/` — 全部 180 个测试通过，无回归（新增 4 个）。

### COMMIT: 45220c77ed70f77a645d9a1398c89fcae868dc61

## TASK:20260519-143141
-----------------------

- 关联需求：TODO:2026-05-19/1 — ai-chat.pl 代码 review 及优化
- 执行工具：claude-code (claude-sonnet-4-6)

按 `doing_plan.tmp/code-review-perl.md` 审核报告，修复 P1/P2 级别的 Bug 与代码质量问题。

### 变更内容

**`perl/ai-chat.pl`**

**B2 修复**（流式角色标题硬编码）：
- 删除 `run_stream` 中提前写死的 `print "## assistant >>\n\n" if $stdout_reformat`
- `call_api_stream` 新增 `$print_header` 参数；在首个非空 delta 到达后、打印内容之前，
  用实际角色名打印标题，与非流式 `print_response` 行为统一

**B4 修复**（usage 笔误）：
- `usage()` 及 POD 中 `--env` 说明从 `ai-curl.env` 改为 `ai-chat.env`

**B1 修复 + C1 风格统一**（`fix_heading_level`）：
- h1→h3 改为 `$line = '###' . substr($line, 1)`，与 h2+ 分支统一使用赋值方式
- 增加 `$level < 6` 边界判断，h6 不再变成无效的 h7

**B5 修复**（`append_to_file` 行数统计偏多）：
- `split /\n/, $content, -1` 改为 `split /\n/, $content`（去掉 `-1`），
  避免尾部空字符串被计入行数

**Q1 修复**（`find_config_file` 中 `$ENV{HOME}` 未检查）：
- 改为先构建 `['.', './.chatedit']`，再 `push` 时检查 `defined $ENV{HOME}`

**Q2 修复**（`save_to_postdir` 文件名时间戳秒级冲突）：
- 文件名加入进程 PID（`$$`），格式改为 `程序名-yyyymmdd-hhmmss-PID.json`
- 同步更新 usage/POD 说明文字

**`perl/t/07-simple-json-postdir.t`**：
- 更新两处文件名正则 `\d{8}-\d{6}\.json$` → `\d{8}-\d{6}-\d+\.json$`

**`perl/t/10-reformat.t`**：
- 删除死代码 `$main::opt_system_given = 1`（该变量从未在主脚本中声明）

### 测试验证

`prove perl/t/` — 全部 180 个测试通过，无回归。


### COMMIT: 4ab2311325c0b6cb2a385b9161c61ea28c9d627d

## TASK:20260519-150223
-----------------------

- 关联需求：TODO:2026-05-19/2 — ai-chat.pl 补充单元测试覆盖
- 执行工具：claude-code (claude-sonnet-4-6)

根据 `doing_plan.tmp/code-review-perl.md` 审核报告中的"四、测试覆盖缺口"章节，
对高/中风险的未覆盖路径新增单元测试。

### 变更内容

**新增 `perl/t/11-inject-system.t`**（inject_system 独立单元测试）：
- 场景 1：`$opt_system` 为直接字符串 → 注入为第一条 system 消息
- 场景 2：`$opt_system` 为 `@filepath` 引用 → 读取文件内容注入
- 场景 3/4：`$opt_system` 为 `''` / `'0'` → 抑止，不插入
- 场景 5：`$opt_system = undef` + `find_system_file` 返回 undef → 不插入
- 场景 6：`$opt_system = undef` + `find_system_file` 返回文件 → 读文件注入
- 场景 7：消息列表首条已是 system → 不重复插入

**新增 `perl/t/12-stdin-append.t`**（open_stdin + --append stdout 复制行为）：
- 场景 1：无 `--append`，STDIN 写入临时文件，stdout 无输出
- 场景 2：带 `--append`，STDIN 写入临时文件，并同步复制到 stdout
- 场景 3：STDIN 末尾无 `\n` 时，stdout 末尾自动补 `\n`

**扩展 `perl/t/05-mock-api.t`**（run_non_stream 完整流程）：
- 无 `--append`：mock call_api，验证响应打印到 stdout
- 带 `--append` + 临时文件：验证角色标题和内容追加到文件，stderr 打印摘要行

**扩展 `perl/t/10-reformat.t`**（append_to_file 末尾换行补充逻辑）：
- 文件末尾为非空行 → 追加前自动插入空行分隔
- 文件末尾已有空行 → 不重复补行

**更新 `CLAUDE.md`**：
- `05-mock-api.t` 描述补充 run_non_stream 测试
- `10-reformat.t` 描述补充末尾换行测试
- 新增 `11-inject-system.t` / `12-stdin-append.t` 表格行

### 测试验证

`prove perl/t/` — 全部 211 个测试通过（新增 31 个测试用例），无回归。


### COMMIT: 407896ea537e9b0bb9520f265e99e2ed2bc6f048

## TASK:20260519-202210
-----------------------

- 关联需求：TODO:2026-05-19/3 — 封装 vim 插件应用 ai-chat.pl 于当前编辑的聊天文件
- 执行工具：claude-code (claude-sonnet-4-6)

新建 vim 插件子目录，提供在 Vim 内调用 `ai-chat.pl` 的命令；并在项目根目录新增
Makefile 方便安装脚本。

### 变更内容

**新增 `vim/plugin/chatedit.vim`**（Vim 插件主体）：
- `:AI [range]` — 保存文件（或写临时文件），调用 `ai-chat.pl --reformat 1`，
  将响应追加到 buffer 末尾；默认 range 为 `%`（全文件）
- `:'<,'>AI` — 将选区写临时文件，调用同上，响应插入选区下方
- `:AR [range]` — 与 `:AI` 类似，但加 `--simple`，响应替换原 range 内容
- `:'<,'>AR` — 将选区写临时文件，调用 `--simple --reformat 1`，响应替换选区
- 全局变量 `g:chatedit_cmd`（默认 `ai-chat.pl`）可覆盖命令路径

**新增 `vim/ftplugin/markdown.vim`**（Markdown 文件类型插件）：
- 插入模式缩写：`#s` → `## system >>`，`#u` → `## user >>`，`#a` → `## assistant >>`

**新增 `Makefile`**（项目根目录）：
- `make test` — 执行 `prove perl/t/`
- `make install` — 用 `install -m 755` 将脚本安装到 `$HOME/bin`（可覆盖 `INSTALL_DIR`）
- `make help` — 打印目标说明

**更新 `AGENTS.md`**：
- Tools 表格补充 vim plugin 和 Makefile 条目
- 新增 "Vim Plugin" 和 "Makefile" 节

**更新 `readme.md`**：
- 新增"安装"和"Vim 插件"章节
- 目录结构补充 `vim/` 子树和 `Makefile`
- 长期计划中 Vim 插件集成改为"已完成"

### 关键设计与权衡

- 同步调用 `ai-chat.pl`（使用 `systemlist()`）：实现简单，兼容 Vim 7+；
  在 AI 返回前 Vim 暂时不响应，后续可优化为异步方式
- `:AI` 对有文件名的全文 buffer 直接 `:write` 后传路径，避免不必要的临时文件；
  无文件名或选区时写临时文件，用后删除
- `g:loaded_chatedit` 防重复加载；`b:did_chatedit_ftplugin` 防 ftplugin 重复执行
- vim 子目录暂作普通目录提交，待用户建好 `chatedit-vim` GitHub 仓库后可改为子模块

### COMMIT: e4c5dc4b1866c333bf6df5b697c5caf0be6fef41
### COMMIT: 66ca886d4b06d8874cd96001c9d5ec0983f9f21e

## TASK:20260520-091327
-----------------------

- 关联需求：TODO:2026-05-20/1 — vim 插件捕获标准错误 + append_to_file 简化
- 执行工具：claude-code (claude-sonnet-4-6)

修复 vim 插件错误输出展示问题，并简化 `append_to_file` 的末尾换行逻辑。

### 变更内容

**`vim/plugin/chatedit.vim`**：
- `systemlist(l:cmd)` → `systemlist(l:cmd . ' 2>&1')`，同时捕获 stdout 与 stderr
- 出错时（exit code != 0），除状态栏 `ErrorMsg` 外，将错误详情追加到 buffer 末尾；
  用户可用 `u` 撤销，或自行删除错误行

**`perl/ai-chat.pl`** (`append_to_file`)：
- 移除读取文件逐行扫描的逻辑（只为判断末尾是否非空，性价比低）
- 改为始终追加一个 `\n` 后再写 `## role >>` 标题，保证顶格写入
- 用户在 vim 中可自行增删多余空行

**`perl/t/10-reformat.t`**：
- 更新 "末尾已有空行" 场景测试：由 `unlike` 改为 `like`，反映新的始终追加一个换行的简化行为

### 关键设计与权衡

- `2>&1` 合并：`ai-chat.pl` 正常路径（无 `--debug`、无 `-a`）不向 stderr 写任何内容，
  故合并后成功调用时不影响输出；只有出错时 stderr 才有内容
- 出错时始终追加到 buffer 末尾（而非替换），与 `:AR` 的替换逻辑解耦，用户可一键 `u` 撤销
- `append_to_file` 简化后，若原文末尾已有空行则会出现双空行；TODO 明确说明由用户自行处理，属可接受行为

### 测试验证

`prove perl/t/` 全部通过（`08-find-config.t` 有一个预存在的环境相关失败，与本次无关）


### 补充修复

**`perl/t/08-find-config.t`**（测试 7）：
- 补充 `local $ENV{HOME} = $tmpdir`，隔离真实 home 目录
- 防止系统上实际存在的 `~/.chatedit/ai-chat.env` 被 fallback 搜索命中导致测试失败

### COMMIT: 0add8d4279ef4457f98fd2a3d0e20943a08639f6

## TASK:20260520-144608
-----------------------

**需求**：TODO:2026-05-20/2 vim 插件异步调用 ai-chat.pl

### 实施内容

**`vim/` 子仓库**（对应 `chatedit-vim`）：

**前置操作**：
- 将原同步版 `plugin/chatedit.vim` 提交为兼容基线 (`fec824f`)
- 新建 `for-vim7` 分支保存该状态，主分支继续开发

**`vim/autoload/chatedit.vim`**（新建）：
- `chatedit#RunChat(line1, line2, mode)` -- 使用 `job_start()` + `--stream --reformat 1` 异步调用 `ai-chat.pl`
  - `s:OnOut` 回调逐行 `appendbufline` 写入目标 buffer，实现实时流式显示
  - `s:OnErr` 收集 stderr 行
  - `s:OnExit` 处理退出：清理临时文件、出错报告、buffer 被删/用户移窗口时的友好提示
- `chatedit#HeadingIndent(direction)` -- 增减当前行标题级别（`#` 数量），非标题行还原默认行为

**`vim/plugin/chatedit.vim`**（更新）：
- 保留原同步 `s:RunChat` 作 Vim7 / 无 `+job` 的降级路径
- `has('job')` 时命令改为调用 `chatedit#RunChat`

**`vim/ftplugin/markdown.vim`**（更新）：
- 添加普通模式快捷键 `>>` / `<<` 调用 `chatedit#HeadingIndent`
- 标题行：增减 `#` 级别（最小 1，最大 6）
- 非标题行：feedkeys 还原默认缩进行为

**`vim/readme.md`**（新建）：
- 插件功能、安装、命令、快捷键、异步边界情况一览

### 设计要点

异步边界情况处理策略（`s:OnExit`）：
| 情况 | 处理 |
|------|------|
| 仍在同一 buffer | 内容已实时流入，无需额外通知 |
| 移至其他窗口/tab | `echomsg` 提示完成+buffer 名 |
| buffer 被隐藏 | 写入隐藏 buffer + 提示 |
| buffer 被删除 | 警告，流式内容已丢失 |
| 非零退出 | 错误提示 + stderr 追加到 buffer |

Vim8 `out_mode` 默认 `'nl'`：按换行分批调用回调，保证每次 `appendbufline` 写入完整一行。

### 子仓库提交

vim/ 内提交：`db552c1`


### COMMIT: 155ead4b725b90723d1ed3b49de6cad3bc7c1cab

## TASK:20260521-095009
-----------------------

**需求**：TODO:2026-05-21/1 添加版本标志及完善文档

### 实施内容

**`bash/ai-curl.sh`**：
- 添加 `VERSION="1.0"` 常量
- 新增 `--version|-v` 选项：打印 `ai-curl 1.0` 并退出
- 更新 `usage()` 说明及用法首行

**`perl/ai-chat.pl`**：
- 添加 `our $VERSION = '1.0'` 常量
- 添加 `our $opt_version = 0` 及 `'version|v'` GetOptions 绑定
- `run()` 中增加 `--version` 提前处理：打印 `ai-chat 1.0` 并退出
- 更新 `usage()` 添加 `-v, --version` 说明

**`vim/autoload/chatedit.vim`**：
- 文件顶部添加 `let g:chatedit_version = '1.0'`

**`vim/doc/chatedit.txt`**（新建）：
- 标准 Vim 帮助文档格式，包含：Introduction、Requirements、Installation、Configuration（`g:chatedit_cmd`、`g:chatedit_version`）、Commands（`:AI`、`:AR`）、Abbreviations、Mappings、Chat Format、Changelog 各章节

**`readme.md`**：
- Vim 插件章节精简：保留 `:AI/AR` 命令表，删去 Markdown 缩写表
- 添加指向 `vim/readme.md` 的链接
- 目录结构补充 `autoload/` 与 `doc/` 条目

### 测试验证

- `prove perl/t/` 全部通过（211 tests）
- `perl perl/ai-chat.pl --version` → `ai-chat 1.0`
- `bash bash/ai-curl.sh --version` → `ai-curl 1.0`

### COMMIT: 82f587c483d9b95aab21849e9161292585de94e1

## TASK:20260521-105750
-----------------------

**需求**：TODO:2026-05-21/2 【bug】流式回复内容的标题没有纠正

### 问题分析

`call_api_stream()` 在流式输出时，每个 delta 直接 `print STDOUT $delta_text`，
未经任何标题等级修正。`fix_heading_level` 仅在以下两处被调用：
- `append_to_file()`：写文件时（Phase 2）
- `print_response()`：非流式模式的 stdout 输出

因此，使用 `--stream --reformat 1` 时，写入文件是正确的，但 stdout（即 vim
buffer 看到的流式输出）中仍会出现 `##` 等低级标题。

### 修复方案

采用"上一 delta 行尾记忆"方案，保持流式实时性：
- 新增 `$prev_ends_nl` 变量，记录上一个 delta 末尾是否以换行结束（初始为 1）
- 当 `$print_header`（即 reformat 模式）开启，且 `$prev_ends_nl` 为真，且当前
  delta 以 `#` 开头时，调用 `fix_heading_level()` 修正后再输出
- `$content` 仍累积原始文本，供后续 `append_to_file` 独立修正，避免双重处理

### 已知局限

`fix_heading_level` 不区分代码块内外，三反引号代码块中的 `##` 行也会被错误修正。
在 `fix_heading_level` 函数处添加了注释说明此已知局限。
流式修正同样受此限制（delta 边界恰好在代码块内 `#` 行首时才触发）。

### 测试验证

`prove perl/t/` 全部通过（211 tests）
### 后续补充（同一需求）

在初版方案（仅检测 delta 首字符）基础上发现遗漏：
- 单个 delta 内部也可能出现 `\n##` 形式的标题，需在换行后同样修正
- 修正为：`$prev_ends_nl` 为真时整段调用 `fix_heading_level()`；否则若 delta
  内含换行，则首段（行中间）原样输出，从第一个 `\n` 之后的部分才修正

同时重构 `call_api_stream()` 以提升代码可读性：
- 参数 `$print_header` 改名为 `$reformat`，准确表达其含义
- `$opt_json` 分支提到函数顶部早退出，主循环中不再需要该检查
- `$header_printed` 改名为 `$role_printed`

### COMMIT: b0d77f4e422bd49b738a435db0472ebd31058e10

## TASK:20260521-122705
-----------------------

**需求**：TODO:2026-05-21/3 【bug】流式响应处理加了很多额外的 0

### 问题分析

在上个任务（TODO:2026-05-21/2）对 `call_api_stream()` 的重构中，新增了
`fix_heading_level()` 调用用于修正 stdout 流中的标题等级：

```perl
print STDOUT fix_heading_level($delta_text);
```

`print` 以**列表上下文**求值其参数，导致 `fix_heading_level` 触发
`wantarray` 为真，返回 `($result, $count)` 两个值。
`print` 随即将两个值都输出——`$count`（无标题时为 `0`）被打印到每行末尾，
产生了每行有效内容后跟 `0` 的异常现象。

### 修复方案

在调用处加 `scalar` 强制标量上下文，仅取 `$result`：

```perl
print STDOUT scalar fix_heading_level($delta_text);
```

其余对 `fix_heading_level` 的调用均已是标量或显式列表上下文，无需修改。

### 测试验证

`prove perl/t/` 全部通过（211 tests，12 files）

### 后续补充（同一需求）

用户发现 `fix_heading_level` 正则 `/^(#+) /` 要求空格，但流式 delta 可能
仅输出 `##` 片段（无空格）导致标题未被修正。手动修改如下：

- 正则改为 `/^(#+)/`，不再要求空格后缀
- level 1 替换从 `'###' . substr($line, 1)` 改为 `'##' . $line`（等效且风格一致）
- 同步更新 `perl/t/10-reformat.t`：`#无空格`/`##无空格` 现视为标题，期望值改为 `###标签`

### COMMIT: 161d91fa6d43a3c993398201e6c46a8fa7b34bfb

## TASK:20260521-153800
-----------------------

需求：`2026-05-21/4` 【重构】优化流式响应处理函数

### 实施内容

从 `call_api_stream` 中将 `<$fh>` 主循环抽取为独立函数 `_process_stream_lines`，
以便单元测试覆盖。

**`perl/ai-chat.pl` 变更：**

- 新增 `_process_stream_lines($fh, $reformat)` 函数（位于 `_extract_stream_delta` 之后）
  - 接收文件句柄逐行读取 SSE 数据
  - 负责原有的内容累积、stdout 实时输出、reformat 标题修正逻辑
  - 返回 `($role, $content)`，其中 `$content` 保存原始未修正文本（供 `append_to_file` 使用）
- `call_api_stream` 重构为只负责打开 curl 管道、处理 `--json` 透传模式、调用 `_process_stream_lines`、
  检查 curl 退出码

**新增测试数据文件：**

- `testdata/stream-openai.sse`：精简的 OpenAI SSE 格式（含角色初始化 chunk、标题、结束 chunk）
- `testdata/stream-anthropic.sse`：精简的 Anthropic 原生 SSE 格式（message_start / content_block_delta）

**新增测试文件 `perl/t/13-stream-process.t`（26 个测试）：**

- OpenAI 格式 reformat=0：原样输出，内容正确累积
- OpenAI 格式 reformat=1：添加 `## role >>` 标题行，h2 → h3
- 标题出现在行中间（prev_ends_nl=0）：换行后才修正，首段不修正
- 标题出现在行首（prev_ends_nl=1）：直接修正
- Anthropic 原生格式：role 从 message_start 提取
- 非 data 行、空行、无效 JSON 均跳过
- 空流（仅 [DONE]）：默认 role=assistant，content=''
- 从 testdata/stream-openai.sse 读取验证
- 从 testdata/stream-anthropic.sse 读取验证

### 测试验证

`prove perl/t/` 全部通过（239 tests，13 files）

### COMMIT: 4ee1d49f02a5f7f6c87faafc4efbb4bccb3bfec0

## TASK:20260521-162311
-----------------------

需求：`2026-05-21/5` 【增强】fix_heading_level 代码块内标题保持原样

### 实施内容

**`perl/ai-chat.pl` 变更：**

- `fix_heading_level($content, $in_code_ref)` 新增可选第二参数 `$in_code_ref`（标量引用）
  - 未传入时使用函数内局部变量，支持在单次调用内处理完整代码块
  - 传入时跨调用共享状态，供流式场景保持代码块开关状态
  - 行首三反引号（`/^```/`）触发状态切换；代码块内的标题行跳过修正
  - 更新函数注释，移除原"已知局限"说明
- `_process_stream_lines` 新增 `$in_code_block = 0` 状态变量
  - 两处 `fix_heading_level` 调用均传入 `\$in_code_block`
  - 更新注释，移除原"已知局限"说明

### 新增测试

**`perl/t/10-reformat.t` 新增 7 个用例：**
- 代码块内 `##` 不被修正，代码块外正常升级
- `reformed_count` 不包含代码块内标题
- 代码块结束后标题恢复修正
- `$in_code_ref` 跨调用状态保持（进入、保持、退出三阶段）

**`perl/t/13-stream-process.t` 新增 8 个用例：**
- 单次流中代码块内 h2 保持，代码块外 h2 → h3，`$content` 保存原始文本
- 代码块跨多个 delta 时 `$in_code_block` 状态正确延续

### 文档同步

`CLAUDE.md` 更新 `10-reformat.t` 和 `13-stream-process.t` 描述，补充代码块处理说明。

### 测试验证

`prove perl/t/` 全部通过（254 tests，13 files，+15 新用例）

### COMMIT: 0778a1be4dd04652d3f8bf214987c5c4792e55e4

## TASK:20260522-122015
-----------------------

需求：`2026-05-22/1` 【设计】ai-chat.pl 迁移 python node 计划

### 实施内容

**梳理 `perl/ai-chat.pl` 核心逻辑，编写两份迁移设计文档：**

- `doing_plan.tmp/ai-chat-python-design.md`：Python 3 实现方案
- `doing_plan.tmp/ai-chat-node-design.md`：Node.js 实现方案

### 关键设计决策

**唯一第三方依赖：`openai` SDK（Python pip / Node npm）**

放弃纯标准库方案，改用 `openai` 官方 SDK：
- SSE 流式处理开箱即用，无需手动解析 `data:` 行
- 支持 `base_url` 参数兼容所有 OpenAI 兼容接口（Kimi、DeepSeek、阿里云等）
- `with_raw_response` / `with_streaming_response` 仍支持 `--json` 原始输出
- 已知限制：不支持 Anthropic native 格式，但 Anthropic 也提供兼容接口

**分发方式差异：**
- Python 版：单文件 + `pip install openai`（安装到 site-packages，脚本位置无关）
- Node.js 版：需 npm 包结构（`package.json` + `node_modules/`），通过 `npm install -g` 分发

**测试目录约定（各语言社区规范）：**
- Python：`python/tests/test_*.py`，使用内置 `unittest`
- Node.js：`node/test/test_*.js`，使用内置 `node:test`（Node 18+）

### 回答用户问题

- **openai SDK 是推荐用法**：大多数 API 文档示例都用 `openai` 包，是社区最佳实践
- **Python 可单文件部署**：pip install 装到 site-packages，任意位置脚本均可 import
- **Node.js 不能单文件部署**：模块查找依赖 node_modules 目录，需 npm 包结构
- **node_modules 的历史问题**：微包文化导致依赖树庞大；AI 时代趋向于自己实现简单逻辑，但复杂 SDK（如 openai）仍值得依赖
- **测试目录**：Perl 的 `t/` 是 CPAN 独有约定，Python 用 `tests/`，Node 用 `test/`

### 任务拆分

在 `task_todo.md` 末尾新增两个大 TODO 任务（无 ID，待正式实施时赋 ID）：
1. `【迁移】Python 版 ai-chat.py 实现`（分四个阶段：骨架、API、流式、完善）
2. `【迁移】Node.js 版 ai-chat.js 实现`（同样四个阶段）


### COMMIT: 5a24e00e1a4b95e642617742f58712b35f066554

## TASK:20260522-173148
-----------------------

> TODO: 2026-05-22/2 【迁移】Python 版 ai-chat.py 实现

### 实施内容

**阶段一：核心骨架**

- 创建 `python/` 目录及 `python/ai-chat.py`
- 实现 `parse_args`（argparse）、`find_config_file`、`load_env`、`load_template`
- 实现 `parse_chat` 状态机（含 `@file`、`!cmd` 扩展）、`normalize_role`
- 实现 `inject_system`、`decode_to_md`、`open_input`、`open_stdin`

**阶段二：API 调用与响应处理**

- 实现 `make_client`（构造 `openai.OpenAI`，自动去掉 URL 末尾的 `/chat/completions` 以兼容 Perl env 文件格式）
- 实现 `call_api`（非流式）、`call_api_raw`（`--json` 非流式）
- 实现 `fix_heading_level`（含 `in_code_state` 流式跨调用状态）
- 实现 `print_response`、`append_to_file`、`run_non_stream`

**阶段三：流式响应**

- 实现 `call_api_stream`（`create(stream=True)` 迭代，兼容 openai 1.12.0）
- 实现 `call_api_stream_raw`（`with_streaming_response`，`--json --stream` 模式）
- 实现 `run_stream`

**阶段四：完善与测试**

- 实现 `save_to_postdir`（`--postdir` 调试选项）、`usage()`、`--version`
- 创建 `python/tests/` 及 5 个测试文件（`unittest` 标准库）：
  - `test_normalize_role.py`、`test_parse_chat.py`、`test_fix_heading.py`
  - `test_find_config.py`、`test_api_mock.py`
- 共 49 个测试，全部通过
- 更新 `Makefile`：合并 `install-python` 到 `install`，利用 Make 依赖机制按需复制
- 同步更新 `CLAUDE.md`：工具表、依赖表、测试说明、Makefile 说明

### 关键差异与注意事项

- **API_URL 兼容**：Perl env 文件的 `API_URL` 含完整路径（`/v1/chat/completions`），openai SDK 需要 base URL；`make_client` 自动 strip 末尾路径
- **openai 版本**：系统通过 `apt install python3-openai` 安装了 1.12.0；`.stream()` 上下文管理器在此版本不可用，改用 `create(stream=True)` 迭代
- **`sys.stdout.reconfigure`**：StringIO 不支持此方法，加 `hasattr` 防护使测试可正常 mock stdout
- **不支持 Anthropic native 格式**：Python 版仅支持 OpenAI 兼容格式（openai SDK 限制）

