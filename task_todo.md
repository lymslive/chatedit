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

## TODO:2026-05-12/2 补充文档

至此已用 perl 脚本实现了基本功能。
请根据当前已实现功能，以及参考 `task_todo.md` 与 `task_log.md` 任务文档，
完善项目 readme 文档，以及 claude 文档。

另请确认 claude 是否也能自动读取 AGENTS.md 文档，考虑到项目可能也用其他工具辅助
开发，最好命名为通用文件名。

### DONE: 20260512~173130

## TODO:2026-05-12/3 模型回复中文时仍然偶发乱码

测试现象：

perl/ai-chat.pl -t testdata/kimi-nothink.json testdata/chat-system.md
正常显示中文

perl/ai-chat.pl -t testdata/kimi-nothink.json docs/chat-format.md
出现乱码

perl/ai-chat.pl -t testdata/kimi-nothink.json docs/chat-format.md --encode | bash/ai-curl.sh
正常显示中文

请分析可能的原因。

另外我有疑问，为什么在实现中要专门开启 utf8 模式处理输入输出。
我想简单处理的话，就将一个汉字当成 3 个字节流好了。
没有在内部处理每个独立汉字的需求，只要在输出终端时能正常显示就好。
避免 utf8 编解码，也能提升性能。

如果这样简化处理，会有什么其他问题吗？

### DONE: 20260512-183920

## TODO:2026-05-13/1 完善 perl 脚本实现的单元测试

为 perl/ai-chat.pl 设计自动化单元测试。
应符合 perl 社区测试规范。如果需要安装依赖模块，请先告知于我。

测试代码也放在 perl 子目录。

请求真实 API 可能较费时，单元测试如何模拟 api 响应？

### DONE: 20260513-122409

## TODO:2026-05-13/2 自动查找辅助配置文件功能优化

ai-chat.pl 与 ai-curl.sh 涉及自动查几种配置文件，当前是查固定文件名。
想改为随程序脚本名变化，即 `$0` 。

查找目录的优先级不变，仍是 ./ ./.chatedit/ ~/.chatedit/

用意是允许用户为脚本创建软链接如 kimi-chat 至 ai-char.pl ，
然后它就自动查找 kimi-chat.env kimi-chat.json kimi-chat.sys 等。
最后仍支持回滚兼容查找通用的 ai-chat.env 等文件。

目前 ai-chat.pl 查的是 ai-curl.env ，按此逻辑纠正为查 ai-chat.env

注意如果不是直接执行脚本，而是通过解释器启动时，
如 bash ai-curl.sh 或 perl ai-chat.pl
脚本名仍能用 `$0` 正确获取吗？

### DONE: 20260513-145043

## TODO:2026-05-13/3 ai-chat.pl 功能扩展 -j -s --postdir

之前 ai-curl.sh 支持的 --json 与 --simple 也集成到 ai-chat.pl

当指定 --simple(-s) 选项时，将整个输入当成简单一段 user 问话，而不必解析为
mardown 文档。

当指定 --json 时，不必再解析 API 响应信息，直接打印原 json 至标准输出，且忽略
-i 原位修改选项。

此外，如果 --postdir 指定了一个有效目录（例如 `post.tmp/`），则将发送给 API 的
json 内容保存至该目录，用 `程序名-yyyymmdd-hhmmss.json` 命名。程序名即
`ai-chat` ，但可能被改名或软链接为其他名字。指定目录不存在时，不主动新建目录，
但可打印一条调试告警信息。此选项的用途在于不想用 `--debug` 打印太多冗余信息时
仍可保存最终发送的 json 内容，以备后续可能的排查之需。

需要补充单元测试用例覆盖新功能。

另外，再检查上次任务修改的配置文件查找顺序功能，似乎也没有覆盖单元测试。
与配置文件相关的测试用例文件可以放在 testdata/ 目录（及其子目录）中，也可以放
脚本的软链接改名。

testdata/ 目录可提交版本库，与测试用例同步。`.chatedit` 目录不提交，用于手动真
实请求 API 的测试验证。

### DONE: 20260513-154929

## TODO:2026-05-14/1 ai-chat.pl 支持流式响应与解析

可以两种方式开启流式响应：
- 命令行选项 --stream
- json 模板中明确写入 `"stream":true`

主流 AI 平台都是用这个字段表示流式响应吗？
还是说直接从响应判断是否流式响应更靠谱。

是否会与原位修改文件的 `-i` 选项冲突？
流式响应先实时打印到标准输出。如果也开启了 `-i` 再追加到原文件。

流式应该不会与 `-json` 冲突，直接打印原 json 流到标准输出。

### DONE: 20260514-121333

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
