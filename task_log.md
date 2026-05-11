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

