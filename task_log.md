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

