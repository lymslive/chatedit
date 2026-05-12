# 原始需求管理

## TODO:2026-05-09/1 实现在 bash 中利用 curl 命令行工具调用 api 

创建 ai-curl.sh 脚本，放在 bash/ 子目录中。封装 curl 命令行原始调用 AI 模型的
API 用法。

期望支持特性：
- 用 source 读取 ai-curl.env 文件，配置 API 的基本 URL 与 KEY 环境变量，优先级
  - 指定选项 --env /path/to/file
  - 当前目录下 ./ai-curl.env
  - 当前目录下 ./.chatedit/ai-curl.env
  - 用户目录下 ~/.chatedit/ai-curl.env
- 支持可选选项 --url --key --model 指定参数，优先级高于 env 文件
- 位置参数期望输入一个 json 文件，其格式应适配 api 接受的格式
- 如果没有位置参数，支持从 STDIN 读入 json

env 文件也应满足 bash 语法，相当于在调用 curl 之前执行的前置命令，但主要目的主
要是用于配置环境变量，所以 `=` 前后不应有空格，暴露的环境变更命名为：
- `API_URL`
- `API_KEY`
- `API_MODEL`

待发送的 json 文件，一般必填的 `model` 字段，可用 `$API_MODEL` 环境变量指代。
在 curl 发送前需要处理环境环境变量替换。

然后在 testdata/ 子目录增加一个 ai-curl.env 文件，与一些示例 json 文件，能被
ai-curl.sh 脚本使用。

在 bin/ 子目录下创建 ai-curl 软链接至 bash/ai-curl.sh 脚本。

### DONE:20260509-121506

## TODO:2026-05-09/2 优化 ai-curl 在单次聊天的内容输入用法

现在 ai-curl.sh 脚本只支持发送完整合法的 json 。
假设只想做单轮简单聊天，希望支持快捷输入无格式内容。

增加一个选项 --simple|-s ，将标准输入或位置参数的文件当作普通文本文件，
然后按 testdata/chat-simple.json 格式拼装最简 json 。

为保证 json 拼装正确，至少要处理输入文本转义引号与回车换行符，
但不必处理复杂的 utf-8 中文转义。
有什么常用的 linux 命令行工具可处理这项工作?
ai-curl bash 脚本希望尽量保持依赖简单。

如果参数文件名以 `.json` 结束，则忽略 -s 选项，仍认为输入是完整 json 。

最终希望支持如下用法：
```bash
echo "Hello, who are you?" | bin/ai-curl --simple
```

另外，希望扩展支持 --system 选项，在拼装 json 时额外插入一条 system 消息。
如果 --system 参数值以 `@` 开头，认为后续是一个文本文件。否则允许将不长的一句
话直接写在命令行中。

按此前设计，拼装的 json 先写临时文件，以便支持原来的环境变量替换。

请评估只用 bash 实现该功能的复杂性与可行性。

### DONE:20260509-160151

## TODO:2026-05-11/1 用 perl 实现将 markdown 聊天文件转换为能发给 api 的 JSON 文件

新建 perl/ai-chat.pl 脚本，根据 `docs/chat-format.md` 文档描叙的格式解析文档，
转为适合发往大模型 API 的 json 内容。

文档主要提供对话内容，调用 API 所需的其他参数写在 json 模板文件中。
模板文件优先级：
- 支持 `--template|-t` 选项指定一个 json 模板文件
- 当前目录 `./ai-chat.json`
- 当前目录 ./.chatedit/ai-chat.json
- 用户目录 ~/.chatedit/ai-chat.json
- 内联固定模板类似 `testdata/chat-simple.json`

模板文件可以省略 `messages` 或留个空数组，即使用非空 `messages` 也被文档解析内
容替换。建议将 `messages` 空数组写在最后。

实施要求，尽可能低依赖，只使用系统安装的 perl 5 自带模块，不额外从 cpan 下载第
三方扩展模块。可以当前开发环境的 perl 安装情况为参考。

输入内容如 `input.md` 文件名可放在命令行参数中，也可通过标准输入。
目前可限定只允许一个输入文件，忽略多余文件。没有输入文件时，读取标准输入。

输出 json 打印到标准输出。故脚本中若有任何调试或警告错误信息打印出标准错误。
可以支持 `--debug|-d` 选项开启打印更详细的有助于调试问题的信息。

这个脚本初步功能完成后，应该可以联用 `ai-curl.sh` 调用 API 。例如：

cat docs/chat-format.md | perl/ai-chat.pl | bash/ai-curl.sh

并且在 `testdata/` 子目录中也增加一两个 `.md` 示例文件。原来的 `.json` 示例文
件应该能充当模板文件。

perl 脚本实现开启 strict 模式，不要炫技晦涩，要求易读可维护。编写 pod 内嵌文档，
其他注释保持简明。

### DONE: 20260511-165415

## TODO:2026-05-11/2 优化 ai-chat.pl 外部引入错误处理

外部引入内容 `@` 与 `!` 的规则改为只允许在有效二级对话段 `## role >>` 中出现。
此前规则声明在 `# ` 注释段就地扩展包含可能涉及递归引入，实现复杂而实用不高，性
价比不高。

此外，增加规定错误处理。
如果 `@` 或 `!` 出错，输出原文本行，再于行尾隔一空格加上错误标记：
- 读取 `@` 文件失败或运行 `!` 命令失败，加 `(Read Error)` 后缀
- 当 `@` 或 `!` 无输出或仅空白输出时，加 `(Read Empty)` 后缀

同步更新 `ai-char.pl` 脚本内的相关注释与文档。

另外，也再检查一下 `## role >>` 段下是否支持 `###` 等次级子标题，它不应该结束
当前段。因为 `###` 也匹配 `/^##/` 与 `/^#/` ，我怀疑在 `sub parse_chat` 中会
提前结束当前行循环。

docs/chat-format.md 可随本次任务一起提交，上个任务漏提交了。

### DONE: 20260511-215428

## TODO:2026-05-12/1 扩展 ai-chat.pl 集成 ai-curl 实际发送功能

当前这两个脚本必须管理联用，如 
cat input.md | perl/ai-chat.pl | bash/ai-curl.sh

现想将发送功能集成到一个脚本，两个目的：
- 提升效率，原 ai-curl.sh 脚本调用很多工具，开启多个进程
- 支持原位修改输入的聊天文件.md，附在末尾，然后重复调用达到多轮聊天效果

期望的功能流程：
- 读取 md 文档
- 结合模板拼装 json
- 请求 https API
- 解析 API 响应的 json，回写 md 文档

扩充的命令行选项及相关功能：
- 支持 ai-curl.sh 的 --env --url --key --model --system 选项，逻辑类似；
- 模板 json 的 model 字段检查替换 `$API_MODEL` 环境变量；
- 扩展 --system 功能，命令行未指定该选项时，可依次按优先级读取
  (. | ./.charedit | ~/.charedit)/ai-chat.sys 文件，
  可以用 `--system ""` 空参数或不带参数时抑止查找文件，
  非空参数时将内容插入 messages 第一个元素，role = system
- 支持 `-i` 选项(长选项名该用哪个单词？)表示原位修改输入的 `.md` 文件，
  否则只将 API 回复内容打印至标准输出；
  如果从标准输入无文件可修改，则先复制原输入到标准输出；
- 支持无参选项 `--header` 表示打印额外的 `## role >>` 二级标题，回复的 role 一
  般是 `assistant`；`-i` 隐含 `--header` ，并且输入文件最后一行不是空行时额外
  加一空行，以便与原内容有分隔感；
- 支持 `--encode` 选项跳过请求 API 请求及后续流程，相当于当前 `ai-chat.pl` 功
  能，只打印组装的 json 内容至标准输出，忽略 `-i` 选项；此时以 pretty 格式打印
  json 结果可用于观察调试，而正常流程要发送至 API 时，按压缩单行的 json 发送，
  减少消耗；
- 支持逆向操作的 `--decode` 选项，输入 json ，输出 mardown （仅有对话段二级标
  题系列）

最终应该支持的功能用法：
```bash
# --encode 降级兼容，保持与 ai-curl.sh 原始脚本的管道联用
cat input.md | perl/ai-chat.pl --encode | bash/ai-curl.sh

# --decode/--encode 互逆操作互相测验
cat input.md | perl/ai-chat.pl --encode | perl/ai-chat.pl --decode

# 原位修改下的多轮对话迭代
perl/ai-chat.pl -i chat.md
# 追加问题后再执行
perl/ai-chat.pl -i chat.md
...
```

关于执行 https 请求 API 的技术选型，我有几个备选想法：
- 仍然调用 curl 工具，捕获输出，除 perl 解释器，curl 应该是唯一的额外进程，其
  他字符串操作用 perl 完成；
- 保持最低依赖，perl5 自带模块能否实现 https 请求
- 从 cpan 额外安装最常用的 https 请求模块
- 调查有没现成的开源模块已封装 openai 的 API 请求模块

先采用第一种最简单的调用 curl 工具实现一个可用版本。其他几种方案的评估先写到
`doing_plan.tmp/` 子目录的文档中，留作后续参考。

调用 API 的错误处理，如果返回 json 包含错误，无法提取对话内容，则将返回的原始
json 打印标准错误，忽略 `-i`；此前的其他任何错误也直接打印标准错误提前终止。

### DONE: 20260512-122319

## TODO: ai-chat.pl 支持流式响应与解析

可以两种方式开启流式响应：
- 命令行选项 --stream
- json 模板中明确写入 `"stream":true`

请分析流式响应是否会与原位修改文件的 `-i` 选项冲突，能如何解决吗？

## TODO: 长期计划

尝试用不同的语言实现基本的 AI 聊天功能。

- [Y] bash 基本 curl 请求封装
- [Z] perl 实现
- [O] vim 插件集成
- [O] 其他脚本实现如 python node
- [O] 编译型实现，供预编译可执行程序，如 cpp rust go
- [O] web 浏览器独立前端页面实现

图例：
- O: 未实施
- X: 取消实现
- Y: 已实施
- Z: 实施中
